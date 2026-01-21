import Foundation
import SwiftUI
import Combine

/// 마이페이지 뷰모델
/// 유저 프로필 데이터 관리 및 더미 데이터 제공
class MyPageViewModel: ObservableObject {
    
    // UI와 바인딩될 유저 프로필 데이터
    @Published var userProfile: UserProfile
    
    // 초기화 시 더미 데이터 로드 (디자인 시안 기준)
    init() {
        // 더미 뱃지 데이터 생성
        let dummyBadges = [
            Badge(iconName: "airplane", title: "Air Time\nKing", isEarned: true),
            Badge(iconName: "moon.fill", title: "Night\nRider", isEarned: true),
            Badge(iconName: "bolt.fill", title: "Speed\nDemon", isEarned: true),
            Badge(iconName: "lock.fill", title: "Mystery\nBadge", isEarned: false)
        ]
        
        // 더미 티어 데이터 (Diamond, Top 1%)
        // 시즌 종료일은 현재 날짜로부터 14일 뒤로 설정
        let dummyTier = UserTier(
            tierName: .diamond,
            topPercent: 1.0,
            seasonEndDate: Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
        )
        
        // 더미 통계 데이터 (랭킹 124위, 거리 542km, 최고속도 92km/h)
        let dummyStats = UserStats(
            globalRanking: 124,
            totalDistance: 542.0,
            maxSpeed: 92.0,
            totalRuns: 156
        )
        
        // 더미 유저 프로필 생성
        self.userProfile = UserProfile(
            nickname: "CyberShredder",
            level: 24,
            currentXP: 2400,
            tier: dummyTier,
            stats: dummyStats,
            badges: dummyBadges
        )
    }
    
    /// 유저 데이터 불러오기 (추후 구현 예정)
    /// 서버 또는 SwiftData에서 최신 데이터를 가져오는 로직이 들어갈 곳
    func fetchUserData() {
        // TODO: 실제 데이터 로딩 로직 구현
        print("Fetching user data...")
    }
    
    /// SwiftData의 주행 기록을 바탕으로 통계 업데이트
    /// - Parameter sessions: 저장된 주행 세션 리스트
    func updateStats(using sessions: [RunSession]) {
        guard !sessions.isEmpty else { return }
        
        // 1. 총 거리 계산 (미터 -> 킬로미터 변환)
        let totalDistanceMeters = sessions.reduce(0.0) { $0 + $1.distance }
        let totalDistanceKm = totalDistanceMeters / 1000.0
        
        // 2. 최고 속도 계산 (이미 km/h 단위라고 가정)
        let maxSpeed = sessions.map { $0.maxSpeed }.max() ?? 0.0
        
        // 3. 총 활강 횟수
        let totalRuns = sessions.count
        
        // 4. 통계 업데이트 (메인 스레드에서 UI 반영 보장)
        DispatchQueue.main.async {
            self.userProfile.stats.totalDistance = totalDistanceKm
            self.userProfile.stats.maxSpeed = maxSpeed
            self.userProfile.stats.totalRuns = totalRuns
            
            // 랭킹 로직은 서버가 필요하므로 현재는 더미 유지 또는 로컬 계산 로직 추가 필요
            // self.userProfile.stats.globalRanking = ...
        }
    }
}
