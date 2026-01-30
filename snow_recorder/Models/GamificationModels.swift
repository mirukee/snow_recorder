import Foundation
import SwiftUI

// MARK: - Gamification Enums

enum Tier: String, Codable, CaseIterable {
    case bronze = "Bronze"
    case silver = "Silver"
    case gold = "Gold"
    case platinum = "Platinum"
    case diamond = "Diamond"
    
    var tierName: String { self.rawValue }
    
    // XP Thresholds for reaching this tier
    var minXP: Int {
        switch self {
        case .bronze: return 0
        case .silver: return 1001
        case .gold: return 3001
        case .platinum: return 6001
        case .diamond: return 10001
        }
    }
    
    // Color for UI
    var color: Color {
        switch self {
        case .bronze: return Color(red: 205/255, green: 127/255, blue: 50/255)
        case .silver: return Color(white: 0.8)
        case .gold: return Color(red: 1.0, green: 0.84, blue: 0.0)
        case .platinum: return Color(red: 0.89, green: 0.93, blue: 0.96)
        case .diamond: return Color(red: 0.7, green: 0.95, blue: 1.0)
        }
    }
    
    var iconName: String {
        switch self {
        case .bronze: return "shield.fill"
        case .silver: return "shield.lefthalf.filled"
        case .gold: return "crown.fill"
        case .platinum: return "aqi.medium"
        case .diamond: return "diamond.fill"
        }
    }
    
    // Next tier calculation
    var next: Tier? {
        switch self {
        case .bronze: return .silver
        case .silver: return .gold
        case .gold: return .platinum
        case .platinum: return .diamond
        case .diamond: return nil
        }
    }
    
    static func getTier(for xp: Int) -> Tier {
        if xp >= Tier.diamond.minXP { return .diamond }
        if xp >= Tier.platinum.minXP { return .platinum }
        if xp >= Tier.gold.minXP { return .gold }
        if xp >= Tier.silver.minXP { return .silver }
        return .bronze
    }
    
    // Top % Estimate (Mock Logic for now)
    var topPercent: Double {
        switch self {
        case .bronze: return 80.0
        case .silver: return 40.0
        case .gold: return 15.0
        case .platinum: return 5.0
        case .diamond: return 1.0
        }
    }
    
    // Season End Date (Mock)
    var seasonEndDate: Date {
        // Assume season ends March 31, 2026
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 31
        return Calendar.current.date(from: components) ?? Date()
    }
}

// MARK: - Badge Model

struct Badge: Identifiable {
    var id: String { title }
    let title: String
    let description: String
    let iconName: String
    var isEarned: Bool
    let unlockCondition: (UserStats) -> Bool
    
    // CodingKeys to exclude closure from Codable
    enum CodingKeys: String, CodingKey {
        case title, description, iconName, isEarned
    }
    
    init(title: String, description: String, iconName: String, isEarned: Bool = false, unlockCondition: @escaping (UserStats) -> Bool) {
        self.title = title
        self.description = description
        self.iconName = iconName
        self.isEarned = isEarned
        self.unlockCondition = unlockCondition
    }
    
    // Manual Decodable/Encodable implementation if needed (simplified for passing data around, usually badges are static configs)
}

// MARK: - User Stats

struct UserStats: Codable {
    var totalRuns: Int = 0
    var totalDistance: Double = 0.0 // km
    var maxSpeed: Double = 0.0 // km/h
    var totalVerticalDrop: Double = 0.0 // meters
    var totalDuration: TimeInterval = 0 // seconds
    var globalRanking: Int = 0
    var highestEdgeScore: Int = 0
    var highestFlowScore: Int = 0
}

struct GamificationProfile {
    var level: Int
    var currentXP: Int
    var tier: Tier
    var stats: UserStats
    var badges: [Badge]
    var nickname: String
    var bio: String?
    var instagramId: String?
    var avatarUrl: String?
}
