import Foundation

/// 사용자 티어 정보 (등급, 상위 퍼센트, 시즌 정보)
enum TierName: String, Codable, CaseIterable {
    case bronze = "Bronze"
    case silver = "Silver"
    case gold = "Gold"
    case diamond = "Diamond"
}

struct UserTier: Codable {
    var tierName: TierName
    var topPercent: Double // 상위 n%
    var seasonEndDate: Date // 시즌 종료일
}

/// 사용자 통계 정보 (랭킹, 거리, 속도, 활강 횟수)
struct UserStats: Codable {
    var globalRanking: Int // 글로벌 랭킹
    var totalDistance: Double // 총 거리 (km)
    var maxSpeed: Double // 최고 속도 (km/h)
    var totalRuns: Int // 총 활강 횟수
}

/// 뱃지 정보 (아이콘, 제목, 획득 여부)
struct Badge: Identifiable, Codable {
    var id: UUID = UUID()
    var iconName: String // SF Symbols 이름 또는 에셋 이름
    var title: String
    var isEarned: Bool
}

/// 사용자 프로필 통합 모델
struct UserProfile: Codable, Identifiable {
    var id: UUID = UUID()
    var nickname: String
    var profileImageURL: URL? // 프로필 이미지 URL (옵셔널)
    var level: Int
    var currentXP: Int
    var tier: UserTier
    var stats: UserStats
    var badges: [Badge]
    
    // 초기 더미 데이터 생성을 위한 init
    init(nickname: String, level: Int, currentXP: Int, tier: UserTier, stats: UserStats, badges: [Badge]) {
        self.nickname = nickname
        self.level = level
        self.currentXP = currentXP
        self.tier = tier
        self.stats = stats
        self.badges = badges
    }
}
