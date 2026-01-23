import Foundation
import Combine
import SwiftData
import SwiftUI

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
    
    private init() {
        // 초기화 시 더미/로컬 데이터 로드
        self.myProfile = RankingProfile(userId: "my_user_id", userName: "Me")
    }
    
    // MARK: - Public Methods
    
    /// 런 세션 종료 시 호출되어 랭킹 데이터를 업데이트하고 서버에 업로드(모의)
    func processRun(session: RunSession) {
        guard isRankingEnabled else {
            print("🚫 Ranking is disabled by user. Skipping upload.")
            return
        }
        
        guard isValidRun(session) else {
            print("⚠️ Run rejected from ranking (Too short/brief).")
            return
        }
        
        // 1. Update Local Aggregation
        updateLocalStats(with: session)
        
        // 2. Upload to Server (Mock)
        uploadRunToServer(session)
    }
    
    /// 현재 선택된 필터에 맞는 리더보드 데이터 반환 (Mock Data Generator)
    func getLeaderboard(cycle: RankingCycle, metric: RankingMetric, scope: RankingScope, slope: String? = nil) -> [LeaderboardEntry] {
        // 실제 앱에서는 API 요청을 통해 받아와야 함
        // 여기서는 Mock Data 생성
        return generateMockLeaderboard(cycle: cycle, metric: metric, scope: scope, slope: slope)
    }
    
    /// SwiftData에 저장된 모든 세션을 기반으로 프로필 재계산 (앱 시작 시 호출 등)
    func recalculateStats(from sessions: [RunSession]) {
        var newProfile = RankingProfile(userId: "my_user_id", userName: "Me")
        
        let now = Date()
        let calendar = Calendar.current
        
        for session in sessions {
            guard isValidRun(session) else { continue }
            
            // 1. Season Totals (누적) - 시즌 구분 로직 필요하나 일단 전체 계산
            newProfile.seasonRunCount += session.runCount
            newProfile.seasonDistance += session.distance
            
            // Season Best (최고 점수 갱신) for Edge/Flow logic
            // (RunSession에 edge/flow 점수가 저장되어 있다고 가정 - 현재 모델에는 없으므로 추후 추가 필요)
            // 임시로 random 값을 가정하거나 0 처리. 
            // TODO: RunSession에 edgeScore, flowScore 필드 추가 후 연동
            
            // 2. Weekly Totals (이번 주 인지 확인)
            if calendar.isDate(session.startTime, equalTo: now, toGranularity: .weekOfYear) {
                newProfile.weeklyRunCount += session.runCount
                newProfile.weeklyDistance += session.distance
            }
        }
        
        DispatchQueue.main.async {
            self.myProfile = newProfile
        }
    }
    
    // MARK: - Private Logic
    
    /// 유효 런 검증 로직
    /// - 거리 100m 이상
    /// - 시간 30초 이상
    private func isValidRun(_ session: RunSession) -> Bool {
        return session.distance >= 100.0 && session.duration >= 30.0
    }
    
    private func updateLocalStats(with session: RunSession) {
        // 마일리지 누적
        myProfile.seasonRunCount += session.runCount
        myProfile.seasonDistance += session.distance
        
        // 주간 데이터 체크
        if Calendar.current.isDate(session.startTime, equalTo: Date(), toGranularity: .weekOfYear) {
            myProfile.weeklyRunCount += session.runCount
            myProfile.weeklyDistance += session.distance
        }
        
        // TODO: Update Best Scores (Edge/Flow) when available in data model
        // 예: myProfile.seasonBestEdge = max(myProfile.seasonBestEdge, session.edgeScore)
        
        print("✅ Local Ranking Stats Updated: Season Run Count = \(myProfile.seasonRunCount)")
    }
    
    private func uploadRunToServer(_ session: RunSession) {
        // Network Request Logic Here
        print("🚀 Uploading run to Ranking Server... (Success)")
    }
    
    // MARK: - Mock Data Helper
    
    private func generateMockLeaderboard(cycle: RankingCycle, metric: RankingMetric, scope: RankingScope, slope: String?) -> [LeaderboardEntry] {
        var entries: [LeaderboardEntry] = []
        let count = 20
        
        for i in 1...count {
            let rank = i
            let name = "User_\(cycle.rawValue)_\(i)"
            let crew = scope == .crew ? "Crew_\(i)" : nil
            let resort = ["High1", "Yongpyong", "Phoenix"].randomElement()!
            // If specific slope filter is requested, use it. Otherwise, random slope or nil.
            let entrySlope = slope ?? ["Zeus", "Athena", "Apollo", "Hera"].randomElement()
            
            var value: Double = 0
            
            // Generate plausible values based on rank and metric
            switch metric {
            case .runCount:
                let base = cycle == .season ? 200 : 50
                value = Double(base - (i * 5))
            case .distance:
                let base = cycle == .season ? 500.0 : 100.0
                value = base - Double(i * 10)
            case .edge, .flow:
                let base = 99.0
                value = base - Double(i) * 0.5
            }
            
            entries.append(LeaderboardEntry(
                rank: rank,
                userName: name,
                crewName: crew,
                mainResort: resort,
                slopeName: entrySlope,
                value: max(0, value),
                metric: metric
            ))
        }
        
        return entries
    }
}
