import Foundation
import Combine
import SwiftData
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

/// 랭킹 로직 및 데이터 처리를 담당하는 싱글톤 서비스
/// - 유효 런 검증 및 자동 업로드 (모의)
/// - 시즌/주간 데이터 집계
/// - Best Score vs Total Mileage 계산
class RankingService: ObservableObject {
    static let shared = RankingService()
    
    // 업로드 정책
    enum UploadPolicy {
        case none
        case smart
    }
    
    // User Settings (Privacy) - 추후 AppStorage나 UserDefaults로 영구 저장 필요
    @Published var isRankingEnabled: Bool = true
    
    // Local Cache
    @Published var myProfile: RankingProfile
    @Published var leaderboard: [LeaderboardEntry] = []
    @Published var isLoadingLeaderboard: Bool = false
    @Published var lastErrorMessage: String? // Debug Info
    @Published var lastLeaderboardUpdatedAt: Date?
    
    private let db = Firestore.firestore()
    private let kstTimeZone = TimeZone(identifier: "Asia/Seoul")!
    private let seasonId = "25_26"
    private let userDefaults = UserDefaults.standard
    private let statsQueue = DispatchQueue(label: "com.snowrecord.ranking.stats", qos: .userInitiated)
    private var pendingRecalcWorkItem: DispatchWorkItem?
    private let recalcDebounce: TimeInterval = 0.35
    
    // 마지막으로 요청한 리더보드 필터(업로드 직후 동일 조건으로 갱신하기 위함)
    private var lastFetchCycle: RankingCycle?
    private var lastFetchMetric: RankingMetric?
    private var lastFetchScope: RankingScope?
    private var lastFetchResortKey: String?
    
    // 리조트 키 매핑 (표시명 -> 저장 키)
    private let resortKeyByDisplayName: [String: String] = [
        "하이원": "high1",
        "용평": "yongpyong",
        "휘닉스": "phoenix",
        "비발디": "vivaldi"
    ]
    private let resortKeys: [String] = ["high1", "yongpyong", "phoenix", "vivaldi"]
    
    private init() {
        // 초기화 시 더미/로컬 데이터 로드
        self.myProfile = RankingProfile(userId: Auth.auth().currentUser?.uid ?? "guest", userName: Auth.auth().currentUser?.displayName ?? "Guest")
    }

    private struct RunSessionSnapshot {
        let startTime: Date
        let distance: Double
        let duration: TimeInterval
        let runCount: Int
        let edgeScores: [Int]
        let flowScores: [Int]
        let locationName: String
        let isDomestic: Bool
    }
    
    // MARK: - Public Methods
    
    /// 런 세션 종료 시 호출되어 랭킹 데이터를 업데이트하고 서버에 업로드
    func processRun(latestSession: RunSession, sessions: [RunSession]) {
        guard isRankingEnabled else { return }
        guard isValidRun(latestSession) else { return }
        guard isSaneSession(latestSession) else {
            print("⚠️ 랭킹 업로드 스킵: 비정상 세션 감지")
            return
        }
        scheduleRecalculateStats(from: sessions, uploadPolicy: .smart)
    }
    
    /// 리더보드 데이터 요청 (Async)
    func fetchLeaderboard(cycle: RankingCycle, metric: RankingMetric, scope: RankingScope, resortKey: String? = nil) {
        // Scope가 Crew인 경우 등 별도 로직 필요하지만 일단 Individual 기준 구현
        isLoadingLeaderboard = true
        lastFetchCycle = cycle
        lastFetchMetric = metric
        lastFetchScope = scope
        lastFetchResortKey = resortKey
        
        let boardId = makeBoardId(cycle: cycle, metric: metric, resortKey: resortKey)
        let boardRef = db.collection("leaderboards").document(boardId)
        
        boardRef.getDocument { [weak self] boardDoc, error in
            guard let self = self else { return }
            
            if let error = error {
                self.isLoadingLeaderboard = false
                self.lastErrorMessage = "Fetch Error: \(error.localizedDescription)"
                print("❌ Error fetching leaderboard meta: \(error)")
                return
            }
            
            if let data = boardDoc?.data(),
               let timestamp = data["updatedAt"] as? Timestamp {
                self.lastLeaderboardUpdatedAt = timestamp.dateValue()
            }
            
            boardRef.collection("shards").document("page_1").getDocument { [weak self] shardDoc, shardError in
                guard let self = self else { return }
                self.isLoadingLeaderboard = false
                
                if let shardError = shardError {
                    self.lastErrorMessage = "Fetch Error: \(shardError.localizedDescription)"
                    print("❌ Error fetching leaderboard shard: \(shardError)")
                    self.leaderboard = []
                    return
                }
                
                guard let shardData = shardDoc?.data(),
                      let rawEntries = shardData["entries"] as? [[String: Any]] else {
                    self.leaderboard = []
                    return
                }
                
                self.lastErrorMessage = nil
                self.leaderboard = rawEntries.compactMap { raw in
                    let userId = raw["uid"] as? String ?? "unknown"
                    let userName = raw["nickname"] as? String ?? "Unknown"
                    let rank = (raw["rank"] as? Int) ?? (raw["rank"] as? Double).map(Int.init) ?? 0
                    let value = (raw["value"] as? Double) ?? (raw["value"] as? Int).map(Double.init) ?? 0.0
                    
                    if value <= 0 || rank <= 0 {
                        return nil
                    }
                    
                    return LeaderboardEntry(
                        userId: userId,
                        rank: rank,
                        userName: userName,
                        crewName: nil,
                        mainResort: "All",
                        slopeName: nil,
                        value: value,
                        metric: metric
                    )
                }
            }
        }
    }
    
    /// 내 현재 순위를 문자열로 반환 (예: "RANK 1", "TOP 10%")
    func getMyRankString() -> String {
        guard let myId = Auth.auth().currentUser?.uid else { return "-" }
        
        if let myEntry = leaderboard.first(where: { $0.userId == myId }) {
            return "RANK \(myEntry.rank)"
        } else {
            // 리더보드(50위) 안에 없으면
            return "UNRANKED"
        }
    }
    
    // View에서 호출하는 Helper (기존 코드 호환용 w/o params logic changes)
    // 하지만 View는 이제 subscribed to $leaderboard
    
    /// SwiftData에 저장된 모든 세션을 기반으로 프로필 재계산 및 서버 업로드
    func recalculateStats(from sessions: [RunSession], uploadPolicy: UploadPolicy = .none) {
        let snapshots = makeSnapshots(from: sessions)
        recalculateStats(from: snapshots, uploadPolicy: uploadPolicy)
    }

    func scheduleRecalculateStats(from sessions: [RunSession], uploadPolicy: UploadPolicy = .none) {
        let snapshots = makeSnapshotsSafely(from: sessions)
        scheduleRecalculateStats(from: snapshots, uploadPolicy: uploadPolicy)
    }

    func syncAfterLocalChange(sessions: [RunSession]) {
        let snapshots = makeSnapshotsSafely(from: sessions)
        let hasValidSessions = snapshots.contains { isValidRun($0) && $0.isDomestic && isWithinSeason($0.startTime) }

        if hasValidSessions {
            scheduleRecalculateStats(from: snapshots, uploadPolicy: .smart)
        } else {
            scheduleRecalculateStats(from: snapshots, uploadPolicy: .none)
            clearProfileOnServer()
            clearLastUploadedTechnical()
        }
    }

    private func scheduleRecalculateStats(from snapshots: [RunSessionSnapshot], uploadPolicy: UploadPolicy = .none) {
        pendingRecalcWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.recalculateStats(from: snapshots, uploadPolicy: uploadPolicy)
        }
        pendingRecalcWorkItem = workItem
        statsQueue.asyncAfter(deadline: .now() + recalcDebounce, execute: workItem)
    }

    private func recalculateStats(from snapshots: [RunSessionSnapshot], uploadPolicy: UploadPolicy = .none) {
        guard let user = Auth.auth().currentUser else { return }
        
        var newProfile = RankingProfile(userId: user.uid, userName: user.displayName ?? "Skier")
        print("🔄 Recalculating Stats for user: \(newProfile.userId)")
        
        let now = Date()
        let calendar = kstCalendar
        let weekId = currentWeekId(for: now)
        
        // Top3 평균 계산 헬퍼
        func calculateTop3Average(_ scores: [Int]) -> Double {
            guard !scores.isEmpty else { return 0.0 }
            let sortedScores = scores.sorted(by: >) // Descending
            let top3 = sortedScores.prefix(3)
            let sum = top3.reduce(0, +)
            return Double(sum) / Double(top3.count)
        }
        
        // 런 단위 점수 수집 (런 메트릭 없는 세션은 세션 최고점으로 보정)
        func collectRunScores(from sessions: [RunSessionSnapshot]) -> (edge: [Int], flow: [Int]) {
            var edgeScores: [Int] = []
            var flowScores: [Int] = []
            
            for session in sessions {
                edgeScores.append(contentsOf: session.edgeScores)
                flowScores.append(contentsOf: session.flowScores)
            }
            
            return (edgeScores, flowScores)
        }
        
        let validSessions = snapshots.filter { isValidRun($0) && $0.isDomestic && isWithinSeason($0.startTime) }
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
        
        // 1. Season Data
        let seasonSessions = validSessions
        newProfile.seasonRunCount = seasonSessions.reduce(0) { $0 + $1.runCount }
        newProfile.seasonDistance = seasonSessions.reduce(0) { $0 + $1.distance }
        let seasonResortMetrics = aggregateResortMetrics(from: seasonSessions)
        newProfile.seasonRunCountByResort = seasonResortMetrics.runCount
        newProfile.seasonDistanceByResort = seasonResortMetrics.distance
        
        let seasonRunScores = collectRunScores(from: seasonSessions)
        
        newProfile.seasonBestEdge = calculateTop3Average(seasonRunScores.edge)
        newProfile.seasonBestFlow = calculateTop3Average(seasonRunScores.flow)
            
        // 2. Weekly Data
        let weeklySessions = validSessions.filter { session in
            guard let weekInterval = weekInterval else { return false }
            return session.startTime >= weekInterval.start && session.startTime < weekInterval.end
        }
        newProfile.weeklyRunCount = weeklySessions.reduce(0) { $0 + $1.runCount }
        newProfile.weeklyDistance = weeklySessions.reduce(0) { $0 + $1.distance }
        let weeklyResortMetrics = aggregateResortMetrics(from: weeklySessions)
        newProfile.weeklyRunCountByResort = weeklyResortMetrics.runCount
        newProfile.weeklyDistanceByResort = weeklyResortMetrics.distance
        
        let weeklyRunScores = collectRunScores(from: weeklySessions)
        
        newProfile.weeklyBestEdge = calculateTop3Average(weeklyRunScores.edge)
        newProfile.weeklyBestFlow = calculateTop3Average(weeklyRunScores.flow)
        
        newProfile.countryCode = validSessions.isEmpty ? "UNKNOWN" : "KR"
        newProfile.seasonId = seasonId
        newProfile.weeklyWeekId = weekId
        
        DispatchQueue.main.async {
            self.myProfile = newProfile
            if uploadPolicy == .smart, !validSessions.isEmpty {
                let technicalSnapshot = self.makeTechnicalSnapshot(from: newProfile)
                let shouldUploadTechnical = self.hasTechnicalChange(technicalSnapshot)
                self.uploadProfileToServer(
                    profile: newProfile,
                    includeTechnicalFields: shouldUploadTechnical,
                    technicalSnapshot: shouldUploadTechnical ? technicalSnapshot : nil
                )
            }
        }
    }
    
    // MARK: - Private Logic
    
    private func isValidRun(_ session: RunSession) -> Bool {
        return session.distance >= 100.0 && session.duration >= 30.0
    }

    private func isValidRun(_ snapshot: RunSessionSnapshot) -> Bool {
        return snapshot.distance >= 100.0 && snapshot.duration >= 30.0
    }
    
    private func isSaneSession(_ session: RunSession) -> Bool {
        // 비정상 값 필터 (클라이언트 업로드 최소 방어)
        let maxAvgSpeedKmh = 120.0
        let maxMaxSpeedKmh = 180.0
        let maxDistanceMeters = 200_000.0
        let maxRunCount = 200
        
        if session.duration <= 0 || session.distance <= 0 {
            return false
        }
        
        let computedAvgSpeedKmh = (session.distance / session.duration) * 3.6
        if computedAvgSpeedKmh > maxAvgSpeedKmh || session.avgSpeed > maxAvgSpeedKmh {
            return false
        }
        if session.maxSpeed > maxMaxSpeedKmh {
            return false
        }
        if session.distance > maxDistanceMeters {
            return false
        }
        if session.runCount > maxRunCount {
            return false
        }
        if session.edgeScore < 0 || session.edgeScore > 1000 {
            return false
        }
        if session.flowScore < 0 || session.flowScore > 1000 {
            return false
        }
        
        return true
    }
    
    private func uploadProfileToServer(
        profile: RankingProfile,
        includeTechnicalFields: Bool,
        technicalSnapshot: TechnicalSnapshot?
    ) {
        guard isRankingEnabled, !profile.userId.isEmpty else { return }
        
        let docRef = db.collection("rankings").document(profile.userId)
        
        // Firestore Field Mapping
        var data: [String: Any] = [
            "nickname": profile.userName,
            "country": profile.countryCode,
            "seasonId": profile.seasonId,
            "weekly_weekId": profile.weeklyWeekId,
            "updatedAt": FieldValue.serverTimestamp(),
            
            // Season
            "season_runCount": profile.seasonRunCount,
            "season_distance": profile.seasonDistance / 1000.0, // Save as KM? or Meter? Let's save as KM for easy Query, or generic Value. Logic: RankingModels uses Meter. Query expects consistency. Let's save as Raw Unit (Meter) or convert?
            // Models say Distance is "KM" unit in display.
            // Let's store standardized values.
            // distance: Meters
            "season_distance_m": profile.seasonDistance,
            
            // Weekly
            "weekly_runCount": profile.weeklyRunCount,
            "weekly_distance_m": profile.weeklyDistance
        ]
        
        if includeTechnicalFields {
            data["season_edge"] = profile.seasonBestEdge
            data["season_flow"] = profile.seasonBestFlow
            data["weekly_edge"] = profile.weeklyBestEdge
            data["weekly_flow"] = profile.weeklyBestFlow
        }
        
        // 리조트별 마일리지 (미터 기준)
        for resortKey in resortKeys {
            data["season_runCount_\(resortKey)"] = profile.seasonRunCountByResort[resortKey] ?? 0
            data["season_distance_m_\(resortKey)"] = profile.seasonDistanceByResort[resortKey] ?? 0.0
            data["weekly_runCount_\(resortKey)"] = profile.weeklyRunCountByResort[resortKey] ?? 0
            data["weekly_distance_m_\(resortKey)"] = profile.weeklyDistanceByResort[resortKey] ?? 0.0
        }
        
        docRef.setData(data, merge: true) { [weak self] error in
            if let error = error {
                print("❌ Failed to upload profile: \(error)")
                DispatchQueue.main.async { self?.lastErrorMessage = "Upload Error: \(error.localizedDescription)" }
            } else {
                print("✅ Ranking Profile Uploaded Successfully")
                DispatchQueue.main.async {
                    self?.lastErrorMessage = nil
                    if let technicalSnapshot {
                        self?.saveLastUploadedTechnical(technicalSnapshot)
                    }
                    // 업로드 직후 현재 선택된 필터로 갱신 (잘못된 지표로 덮어쓰는 문제 방지)
                    if let cycle = self?.lastFetchCycle,
                       let metric = self?.lastFetchMetric,
                       let scope = self?.lastFetchScope {
                        self?.fetchLeaderboard(cycle: cycle, metric: metric, scope: scope, resortKey: self?.lastFetchResortKey)
                    }
                }
            }
        }
    }
    
    private func getFieldName(for metric: RankingMetric, cycle: RankingCycle, resortKey: String?) -> String {
        let prefix = cycle == .season ? "season_" : "weekly_"
        
        switch metric {
        case .runCount:
            if let resortKey = resortKey, !resortKey.isEmpty {
                return prefix + "runCount_\(resortKey)"
            }
            return prefix + "runCount"
        case .distance:
            if let resortKey = resortKey, !resortKey.isEmpty {
                return prefix + "distance_m_\(resortKey)"
            }
            return prefix + "distance_m"
        case .edge: return prefix + "edge"
        case .flow: return prefix + "flow"
        }
    }
    
    private func makeBoardId(cycle: RankingCycle, metric: RankingMetric, resortKey: String?) -> String {
        let cycleKey = cycle == .season ? "season" : "weekly"
        let metricKey: String
        
        switch metric {
        case .runCount:
            metricKey = "runCount"
        case .distance:
            metricKey = "distance_m"
        case .edge:
            metricKey = "edge"
        case .flow:
            metricKey = "flow"
        }
        
        let scopeKey = resortKey?.isEmpty == false ? (resortKey ?? "all") : "all"
        return "\(cycleKey)_\(metricKey)_\(scopeKey)"
    }

    // MARK: - 국내/시즌/주차 계산
    
    private var kstCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = kstTimeZone
        calendar.locale = Locale(identifier: "ko_KR")
        calendar.firstWeekday = 2 // 월요일 시작
        return calendar
    }
    
    private func makeKSTDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = kstTimeZone
        return kstCalendar.date(from: components) ?? Date()
    }
    
    private var seasonStartDate: Date {
        makeKSTDate(year: 2025, month: 11, day: 1, hour: 0, minute: 0, second: 0)
    }
    
    private var seasonEndDate: Date {
        makeKSTDate(year: 2026, month: 3, day: 31, hour: 23, minute: 59, second: 59)
    }
    
    private func isWithinSeason(_ date: Date) -> Bool {
        return date >= seasonStartDate && date <= seasonEndDate
    }
    
    private func currentWeekId(for date: Date) -> String {
        let calendar = kstCalendar
        let year = calendar.component(.yearForWeekOfYear, from: date)
        let week = calendar.component(.weekOfYear, from: date)
        return String(format: "%04d-W%02d", year, week)
    }
    
    private func isDomesticSession(countryCode: String, routeCoordinates: [[Double]]) -> Bool {
        if countryCode == "KR" {
            return true
        }
        if countryCode != "UNKNOWN" {
            return false
        }
        guard !routeCoordinates.isEmpty else { return false }
        
        for coord in routeCoordinates {
            guard coord.count >= 2 else { continue }
            let lat = coord[0]
            let lon = coord[1]
            if isDomesticCoordinate(lat: lat, lon: lon) {
                return true
            }
        }
        return false
    }
    
    private func isDomesticCoordinate(lat: Double, lon: Double) -> Bool {
        // 한국 대략 바운딩 박스 (제주/독도 포함 여유 범위)
        return lat >= 33.0 && lat <= 39.0 && lon >= 124.5 && lon <= 132.0
    }
    
    // MARK: - 테크니컬 업로드 판단
    
    private struct TechnicalSnapshot {
        let seasonEdge: Double
        let seasonFlow: Double
        let weeklyEdge: Double
        let weeklyFlow: Double
    }
    
    private enum TechnicalUploadKey {
        static let seasonEdge = "last_uploaded_season_edge"
        static let seasonFlow = "last_uploaded_season_flow"
        static let weeklyEdge = "last_uploaded_weekly_edge"
        static let weeklyFlow = "last_uploaded_weekly_flow"
    }
    
    private func makeTechnicalSnapshot(from profile: RankingProfile) -> TechnicalSnapshot {
        return TechnicalSnapshot(
            seasonEdge: profile.seasonBestEdge,
            seasonFlow: profile.seasonBestFlow,
            weeklyEdge: profile.weeklyBestEdge,
            weeklyFlow: profile.weeklyBestFlow
        )
    }
    
    private func hasTechnicalChange(_ snapshot: TechnicalSnapshot) -> Bool {
        guard let last = loadLastUploadedTechnical() else {
            return true
        }
        let epsilon = 0.0001
        return abs(snapshot.seasonEdge - last.seasonEdge) > epsilon
            || abs(snapshot.seasonFlow - last.seasonFlow) > epsilon
            || abs(snapshot.weeklyEdge - last.weeklyEdge) > epsilon
            || abs(snapshot.weeklyFlow - last.weeklyFlow) > epsilon
    }
    
    private func loadLastUploadedTechnical() -> TechnicalSnapshot? {
        guard
            let seasonEdge = userDefaults.object(forKey: TechnicalUploadKey.seasonEdge) as? Double,
            let seasonFlow = userDefaults.object(forKey: TechnicalUploadKey.seasonFlow) as? Double,
            let weeklyEdge = userDefaults.object(forKey: TechnicalUploadKey.weeklyEdge) as? Double,
            let weeklyFlow = userDefaults.object(forKey: TechnicalUploadKey.weeklyFlow) as? Double
        else {
            return nil
        }
        return TechnicalSnapshot(
            seasonEdge: seasonEdge,
            seasonFlow: seasonFlow,
            weeklyEdge: weeklyEdge,
            weeklyFlow: weeklyFlow
        )
    }
    
    private func saveLastUploadedTechnical(_ snapshot: TechnicalSnapshot) {
        userDefaults.set(snapshot.seasonEdge, forKey: TechnicalUploadKey.seasonEdge)
        userDefaults.set(snapshot.seasonFlow, forKey: TechnicalUploadKey.seasonFlow)
        userDefaults.set(snapshot.weeklyEdge, forKey: TechnicalUploadKey.weeklyEdge)
        userDefaults.set(snapshot.weeklyFlow, forKey: TechnicalUploadKey.weeklyFlow)
    }

    private func clearLastUploadedTechnical() {
        userDefaults.removeObject(forKey: TechnicalUploadKey.seasonEdge)
        userDefaults.removeObject(forKey: TechnicalUploadKey.seasonFlow)
        userDefaults.removeObject(forKey: TechnicalUploadKey.weeklyEdge)
        userDefaults.removeObject(forKey: TechnicalUploadKey.weeklyFlow)
    }
    
    // MARK: - 리조트 매핑/집계
    
    func resortKey(forDisplayName name: String) -> String? {
        return resortKeyByDisplayName[name]
    }
    
    private func resortKey(forLocationName name: String) -> String? {
        let lower = name.lowercased()
        if lower.contains("high1") || lower.contains("high 1") || lower.contains("하이원") {
            return "high1"
        }
        if lower.contains("용평") || lower.contains("yongpyong") || lower.contains("yong pyong") {
            return "yongpyong"
        }
        if lower.contains("휘닉스") || lower.contains("phoenix") {
            return "phoenix"
        }
        if lower.contains("비발디") || lower.contains("vivaldi") {
            return "vivaldi"
        }
        return nil
    }
    
    private func aggregateResortMetrics(from sessions: [RunSessionSnapshot]) -> (runCount: [String: Int], distance: [String: Double]) {
        var runCountByResort: [String: Int] = [:]
        var distanceByResort: [String: Double] = [:]
        
        for session in sessions {
            guard let resortKey = resortKey(forLocationName: session.locationName) else { continue }
            runCountByResort[resortKey, default: 0] += session.runCount
            distanceByResort[resortKey, default: 0.0] += session.distance
        }
        
        return (runCountByResort, distanceByResort)
    }

    private func makeSnapshotsSafely(from sessions: [RunSession]) -> [RunSessionSnapshot] {
        if Thread.isMainThread {
            return makeSnapshots(from: sessions)
        }
        return DispatchQueue.main.sync {
            makeSnapshots(from: sessions)
        }
    }

    private func makeSnapshots(from sessions: [RunSession]) -> [RunSessionSnapshot] {
        sessions.map { session in
            let runScores: (edge: [Int], flow: [Int]) = {
                if session.runMetrics.isEmpty {
                    if session.runCount > 0 {
                        return ([session.edgeScore], [session.flowScore])
                    }
                    return ([], [])
                }
                return (
                    session.runMetrics.map { $0.edgeScore },
                    session.runMetrics.map { $0.flowScore }
                )
            }()
            
            let isDomestic = isDomesticSession(
                countryCode: session.countryCode,
                routeCoordinates: session.routeCoordinates
            )
            
            return RunSessionSnapshot(
                startTime: session.startTime,
                distance: session.distance,
                duration: session.duration,
                runCount: session.runCount,
                edgeScores: runScores.edge,
                flowScores: runScores.flow,
                locationName: session.locationName,
                isDomestic: isDomestic
            )
        }
    }

    private func clearProfileOnServer() {
        guard isRankingEnabled, let user = Auth.auth().currentUser else { return }
        
        let docRef = db.collection("rankings").document(user.uid)
        docRef.delete { [weak self] error in
            if let error {
                print("❌ Failed to delete ranking profile: \(error)")
                DispatchQueue.main.async {
                    self?.lastErrorMessage = "Delete Error: \(error.localizedDescription)"
                }
            } else {
                print("✅ Ranking Profile Deleted Successfully")
                DispatchQueue.main.async {
                    self?.lastErrorMessage = nil
                }
            }
        }
    }
}
