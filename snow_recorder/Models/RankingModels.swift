import Foundation

// MARK: - Enums

enum RankingCycle: String, CaseIterable, Identifiable {
    case season = "SEASON"
    case weekly = "WEEKLY"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .season: return "25/26 SEASON"
        case .weekly: return "THIS WEEK"
        }
    }
}

enum RankingMetric: String, CaseIterable, Identifiable {
    case runCount = "RUNS"
    case distance = "DIST"
    case edge = "EDGE"
    case flow = "FLOW"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .runCount: return "RUN COUNT"
        case .distance: return "DISTANCE"
        case .edge: return "EDGE SCORE"
        case .flow: return "FLOW SCORE"
        }
    }
    
    var unit: String {
        switch self {
        case .runCount: return "RUNS"
        case .distance: return "KM"
        case .edge: return "PTS"
        case .flow: return "PTS"
        }
    }
}

enum RankingScope: String, CaseIterable {
    case individual = "INDIVIDUAL"
    case crew = "CREW"
}

// MARK: - Models

/// 사용자의 개인 랭킹 프로필 (내 기록)
struct RankingProfile {
    var userId: String
    var userName: String
    
    // Season Totals
    var seasonRunCount: Int = 0
    var seasonDistance: Double = 0.0 // meters
    var seasonBestEdge: Int = 0
    var seasonBestFlow: Int = 0
    
    // Weekly Totals
    var weeklyRunCount: Int = 0
    var weeklyDistance: Double = 0.0 // meters
    var weeklyBestEdge: Int = 0
    var weeklyBestFlow: Int = 0
    
    // Helper to get value by metric/cycle
    func getValue(for metric: RankingMetric, cycle: RankingCycle) -> Double {
        switch cycle {
        case .season:
            switch metric {
            case .runCount: return Double(seasonRunCount)
            case .distance: return seasonDistance / 1000.0 // km 변환
            case .edge: return Double(seasonBestEdge)
            case .flow: return Double(seasonBestFlow)
            }
        case .weekly:
            switch metric {
            case .runCount: return Double(weeklyRunCount)
            case .distance: return weeklyDistance / 1000.0 // km 변환
            case .edge: return Double(weeklyBestEdge)
            case .flow: return Double(weeklyBestFlow)
            }
        }
    }
    
    func getRank(for metric: RankingMetric, cycle: RankingCycle) -> String {
        // 실제 서버 연동 시에는 서버에서 받아온 등수 리턴
        // 현재는 Mock 로직 (예: 상위 15% 등)
        return "TOP 15%"
    }
}

/// 리더보드 항목 (타인 기록)
struct LeaderboardEntry: Identifiable {
    let id = UUID()
    let rank: Int
    let userName: String
    let crewName: String?
    let mainResort: String
    let slopeName: String? // Optional specific slope
    let value: Double // Display value (runs, km, or score)
    let metric: RankingMetric
}
