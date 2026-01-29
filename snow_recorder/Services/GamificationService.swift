import Foundation
import SwiftData
import Combine

class GamificationService: ObservableObject {
    static let shared = GamificationService()
    
    // Published Profile for Views to observe
    @Published var profile: GamificationProfile
    
    // Constants
    private let xpPerKm: Int = 10
    private let xpPerRun: Int = 50
    private let speedBonusThreshold: Double = 50.0 // km/h
    private let speedBonusXP: Int = 5
    private let statsQueue = DispatchQueue(label: "com.snowrecord.gamification.stats", qos: .userInitiated)
    private var pendingUpdateWorkItem: DispatchWorkItem?
    private let updateDebounce: TimeInterval = 0.35
    
    // Badges Configuration
    private var allBadges: [Badge] = [
        Badge(title: "First Steps", description: "Complete your first run.", iconName: "figure.skiing.downhill", unlockCondition: { stats in stats.totalRuns >= 1 }),
        Badge(title: "Marathoner", description: "Ski a total of 100km.", iconName: "figure.walk", unlockCondition: { stats in stats.totalDistance >= 100.0 }),
        Badge(title: "Speed Demon", description: "Reach a speed of 80km/h.", iconName: "flame.fill", unlockCondition: { stats in stats.maxSpeed >= 80.0 }),
        Badge(title: "Century Club", description: "Complete 100 runs.", iconName: "100.circle.fill", unlockCondition: { stats in stats.totalRuns >= 100 }),
        Badge(title: "Everest", description: "Ski 8,848m vertical drop.", iconName: "mountain.2.fill", unlockCondition: { stats in stats.totalVerticalDrop >= 8848.0 }),
        
        // New Badges
        Badge(title: "High Flyer", description: "Ski 20,000m vertical drop.", iconName: "airplane.departure", unlockCondition: { stats in stats.totalVerticalDrop >= 20000.0 }),
        Badge(title: "Early Bird", description: "Start skiing before 9 AM.", iconName: "sunrise.fill", unlockCondition: { _ in false }), // Needs session time check logic
        Badge(title: "Night Owl", description: "Ski after 7 PM.", iconName: "moon.stars.fill", unlockCondition: { _ in false }), // Needs session time check logic
        Badge(title: "Safe Rider", description: "Record 10 sessions without crashing (Mock).", iconName: "checkmark.shield.fill", unlockCondition: { stats in stats.totalRuns >= 50 }) // Placeholder
    ]
    
    private init() {
        // Initialize with default/empty profile
        self.profile = GamificationProfile(
            level: 1,
            currentXP: 0,
            tier: .bronze,
            stats: UserStats(),
            badges: [], // Will be populated in init
            nickname: "Skier"
        )
        // Sync badges initial state
        self.profile.badges = allBadges
    }

    private struct SessionStatsSnapshot {
        let runCount: Int
        let distanceMeters: Double
        let maxSpeed: Double
        let verticalDrop: Double
        let duration: TimeInterval
    }
    
    // MARK: - Public API
    
    /// Calculate stats and XP from a list of sessions (e.g., from @Query)
    func updateProfile(from sessions: [RunSession]) {
        let snapshots = makeSnapshots(from: sessions)
        updateProfile(from: snapshots)
    }

    func scheduleUpdateProfile(from sessions: [RunSession]) {
        let snapshots = makeSnapshotsSafely(from: sessions)
        scheduleUpdateProfile(from: snapshots)
    }

    private func scheduleUpdateProfile(from snapshots: [SessionStatsSnapshot]) {
        pendingUpdateWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.updateProfile(from: snapshots)
        }
        pendingUpdateWorkItem = workItem
        statsQueue.asyncAfter(deadline: .now() + updateDebounce, execute: workItem)
    }
    
    func setNickname(_ name: String) {
        self.profile.nickname = name
    }
    
    // MARK: - Private Logic

    private func updateProfile(from snapshots: [SessionStatsSnapshot]) {
        var newStats = UserStats()
        var totalXP = 0
        
        for session in snapshots {
            // 1. Accumulate Stats
            newStats.totalRuns += session.runCount
            newStats.totalDistance += (session.distanceMeters / 1000.0) // Convert m to km
            newStats.maxSpeed = max(newStats.maxSpeed, session.maxSpeed)
            newStats.totalVerticalDrop += session.verticalDrop
            newStats.totalDuration += session.duration
            
            // 2. Calculate XP for this session
            let runXP = session.runCount * xpPerRun
            let distXP = Int((session.distanceMeters / 1000.0) * Double(xpPerKm))
            
            // Speed Bonus logic (Simplified: if session max speed > threshold, add bonus)
            var sessionSpeedBonus = 0
            if session.maxSpeed > speedBonusThreshold {
                let over = session.maxSpeed - speedBonusThreshold
                sessionSpeedBonus = Int(over / 10.0) * speedBonusXP
            }
            
            totalXP += (runXP + distXP + sessionSpeedBonus)
        }
        
        // Mock Global Ranking Calculation
        newStats.globalRanking = calculateMockRanking(xp: totalXP)
        
        // 3. Update Level & Tier
        let newLevel = calculateLevel(xp: totalXP)
        let newTier = Tier.getTier(for: totalXP)
        
        // 4. Check Badges
        let updatedBadges = checkBadges(stats: newStats)
        
        // 5. Publish Changes
        DispatchQueue.main.async {
            self.profile = GamificationProfile(
                level: newLevel,
                currentXP: totalXP,
                tier: newTier,
                stats: newStats,
                badges: updatedBadges,
                nickname: self.profile.nickname // Preserve nickname
            )
        }
    }
    
    private func calculateLevel(xp: Int) -> Int {
        // Simple Level Formula: Level = sqrt(XP) * 0.1 (Just an example curve)
        // Or linear: Level = 1 + (XP / 500)
        return 1 + (xp / 500)
    }
    
    private func calculateMockRanking(xp: Int) -> Int {
        // The higher the XP, the lower (better) the rank.
        // Mock logic: 10000 XP -> Rank 1, 0 XP -> Rank 10000
        return max(1, 10000 - (xp / 2))
    }
    
    private func checkBadges(stats: UserStats) -> [Badge] {
        return allBadges.map { badge in
            var newBadge = badge
            if !newBadge.isEarned && newBadge.unlockCondition(stats) {
                newBadge.isEarned = true
                // Here we could trigger a notification or visual alert
                print("🏆 Badge Unlocked: \(newBadge.title)")
            }
            return newBadge
        }
    }

    private func makeSnapshotsSafely(from sessions: [RunSession]) -> [SessionStatsSnapshot] {
        if Thread.isMainThread {
            return makeSnapshots(from: sessions)
        }
        return DispatchQueue.main.sync {
            makeSnapshots(from: sessions)
        }
    }

    private func makeSnapshots(from sessions: [RunSession]) -> [SessionStatsSnapshot] {
        sessions.map { session in
            SessionStatsSnapshot(
                runCount: session.runCount,
                distanceMeters: session.distance,
                maxSpeed: session.maxSpeed,
                verticalDrop: session.verticalDrop,
                duration: session.duration
            )
        }
    }
}
