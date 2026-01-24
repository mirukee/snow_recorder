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
    
    // User Settings (Privacy) - 추후 AppStorage나 UserDefaults로 영구 저장 필요
    @Published var isRankingEnabled: Bool = true
    
    // Local Cache
    @Published var myProfile: RankingProfile
    @Published var leaderboard: [LeaderboardEntry] = []
    @Published var isLoadingLeaderboard: Bool = false
    @Published var lastErrorMessage: String? // Debug Info
    
    private let db = Firestore.firestore()
    private let kstTimeZone = TimeZone(identifier: "Asia/Seoul")!
    private let seasonId = "25_26"
    
    private init() {
        // 초기화 시 더미/로컬 데이터 로드
        self.myProfile = RankingProfile(userId: Auth.auth().currentUser?.uid ?? "guest", userName: Auth.auth().currentUser?.displayName ?? "Guest")
    }
    
    // MARK: - Public Methods
    
    /// 런 세션 종료 시 호출되어 랭킹 데이터를 업데이트하고 서버에 업로드
    func processRun(session: RunSession) {
        guard isRankingEnabled else { return }
        guard isValidRun(session) else { return }
        
        // Note: processRun is called AFTER SwiftData save. 
        // We rely on recalculateStats to scan ALL sessions and update the profile, then upload.
        // This ensures consistency even if a run is deleted.
    }
    
    /// 리더보드 데이터 요청 (Async)
    func fetchLeaderboard(cycle: RankingCycle, metric: RankingMetric, scope: RankingScope) {
        // Scope가 Crew인 경우 등 별도 로직 필요하지만 일단 Individual 기준 구현
        // Cycle 구분 (Season vs Weekly) -> Firestore Collection or Query Field 분기
        
        isLoadingLeaderboard = true
        
        let collectionRef = db.collection("rankings")
        var query: FirebaseFirestore.Query = collectionRef
        
        // 국내(KR) 기준 필터
        query = query.whereField("country", isEqualTo: "KR")
        
        // 시즌/주차 필터
        switch cycle {
        case .season:
            query = query.whereField("seasonId", isEqualTo: seasonId)
        case .weekly:
            query = query.whereField("weekly_weekId", isEqualTo: currentWeekId(for: Date()))
        }
        
        // 정렬 기준 (Metric)
        let fieldName = getFieldName(for: metric, cycle: cycle)
        query = query.order(by: fieldName, descending: true)
        
        query.limit(to: 50).getDocuments { [weak self] (snapshot: QuerySnapshot?, error: Error?) in
            guard let self = self else { return }
            self.isLoadingLeaderboard = false
            
            if let error = error {
                print("❌ Error fetching leaderboard: \(error)")
                return
            }
            
            guard let documents = snapshot?.documents else { return }
            
            var rank = 1
            self.leaderboard = documents.compactMap { doc -> LeaderboardEntry? in
                let data = doc.data()
                let userId = doc.documentID
                let userName = data["nickname"] as? String ?? "Unknown"
                let value = data[fieldName] as? Double ?? 0.0
                
                // Exclude 0, maybe?
                
                let entry = LeaderboardEntry(
                    userId: userId, // Pass the Firestore document ID (User ID)
                    rank: rank,
                    userName: userName,
                    crewName: nil,
                    mainResort: "High1", // Mock or store in DB
                    slopeName: nil,
                    value: value,
                    metric: metric
                )
                rank += 1
                return entry
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
    func recalculateStats(from sessions: [RunSession]) {
        guard let user = Auth.auth().currentUser else { return }
        
        var newProfile = RankingProfile(userId: user.uid, userName: user.displayName ?? "Skier")
        print("🔄 Recalculating Stats for user: \(newProfile.userId)")
        
        let now = Date()
        let calendar = kstCalendar
        let weekId = currentWeekId(for: now)
        
        // Helper to calculate Top 3 Average
        func calculateTop3Average(_ scores: [Int]) -> Double {
            guard !scores.isEmpty else { return 0.0 }
            let sortedScores = scores.sorted(by: >) // Descending
            let top3 = sortedScores.prefix(3)
            let sum = top3.reduce(0, +)
            return Double(sum) / Double(top3.count)
        }
        
        let validSessions = sessions.filter { isValidRun($0) && isDomesticSession($0) && isWithinSeason($0.startTime) }
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
        
        // 1. Season Data
        let seasonSessions = validSessions
        newProfile.seasonRunCount = seasonSessions.reduce(0) { $0 + $1.runCount }
        newProfile.seasonDistance = seasonSessions.reduce(0) { $0 + $1.distance }
        
        let seasonEdgeScores = seasonSessions.map { $0.edgeScore }
        let seasonFlowScores = seasonSessions.map { $0.flowScore }
        
        newProfile.seasonBestEdge = calculateTop3Average(seasonEdgeScores)
        newProfile.seasonBestFlow = calculateTop3Average(seasonFlowScores)
            
        // 2. Weekly Data
        let weeklySessions = validSessions.filter { session in
            guard let weekInterval = weekInterval else { return false }
            return session.startTime >= weekInterval.start && session.startTime < weekInterval.end
        }
        newProfile.weeklyRunCount = weeklySessions.reduce(0) { $0 + $1.runCount }
        newProfile.weeklyDistance = weeklySessions.reduce(0) { $0 + $1.distance }
        
        let weeklyEdgeScores = weeklySessions.map { $0.edgeScore }
        let weeklyFlowScores = weeklySessions.map { $0.flowScore }
        
        newProfile.weeklyBestEdge = calculateTop3Average(weeklyEdgeScores)
        newProfile.weeklyBestFlow = calculateTop3Average(weeklyFlowScores)
        
        newProfile.countryCode = validSessions.isEmpty ? "UNKNOWN" : "KR"
        newProfile.seasonId = seasonId
        newProfile.weeklyWeekId = weekId
        
        DispatchQueue.main.async {
            self.myProfile = newProfile
            self.uploadProfileToServer(profile: newProfile)
        }
    }
    
    // MARK: - Private Logic
    
    private func isValidRun(_ session: RunSession) -> Bool {
        return session.distance >= 100.0 && session.duration >= 30.0
    }
    
    private func uploadProfileToServer(profile: RankingProfile) {
        guard isRankingEnabled, !profile.userId.isEmpty else { return }
        
        let docRef = db.collection("rankings").document(profile.userId)
        
        // Firestore Field Mapping
        let data: [String: Any] = [
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
            "season_edge": profile.seasonBestEdge,
            "season_flow": profile.seasonBestFlow,
            
            // Weekly
            "weekly_runCount": profile.weeklyRunCount,
            "weekly_distance_m": profile.weeklyDistance,
            "weekly_edge": profile.weeklyBestEdge,
            "weekly_flow": profile.weeklyBestFlow
        ]
        
        docRef.setData(data, merge: true) { [weak self] error in
            if let error = error {
                print("❌ Failed to upload profile: \(error)")
                DispatchQueue.main.async { self?.lastErrorMessage = "Upload Error: \(error.localizedDescription)" }
            } else {
                print("✅ Ranking Profile Uploaded Successfully")
                DispatchQueue.main.async {
                    self?.lastErrorMessage = nil
                    // Refresh leaderboard immediately after upload to show myself
                    self?.fetchLeaderboard(cycle: .season, metric: .runCount, scope: .individual) 
                    // Note: Ideally should use current selected filters, but they are in View. 
                    // Simplification: We blindly fetch default, or View triggers fetch via observing myProfile? 
                    // Actually, View handles fetch on appear. Let's just trust View's refresh or user manual refresh.
                    // But user complains "No Data". 
                    // Let's force a fetch here just to be sure DB has data.
                }
            }
        }
    }
    
    private func getFieldName(for metric: RankingMetric, cycle: RankingCycle) -> String {
        let prefix = cycle == .season ? "season_" : "weekly_"
        
        switch metric {
        case .runCount: return prefix + "runCount"
        case .distance: return prefix + "distance_m"
        case .edge: return prefix + "edge"
        case .flow: return prefix + "flow"
        }
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
    
    private func isDomesticSession(_ session: RunSession) -> Bool {
        if session.countryCode == "KR" {
            return true
        }
        if session.countryCode != "UNKNOWN" {
            return false
        }
        guard !session.routeCoordinates.isEmpty else { return false }
        
        for coord in session.routeCoordinates {
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
}
