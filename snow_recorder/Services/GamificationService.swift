import Foundation
import SwiftData
import Combine

class GamificationService: ObservableObject {
    static let shared = GamificationService()
    
    // Published Profile for Views to observe
    @Published var profile: GamificationProfile
    @Published private(set) var featuredBadgeTitles: [String] = []
    
    // Constants
    private let xpPerKm: Int = 10
    private let xpPerRun: Int = 50
    private let speedBonusThreshold: Double = 50.0 // km/h
    private let speedBonusXP: Int = 5
    private let statsQueue = DispatchQueue(label: "com.snowrecord.gamification.stats", qos: .userInitiated)
    private var pendingUpdateWorkItem: DispatchWorkItem?
    private let updateDebounce: TimeInterval = 0.35
    private var cancellables = Set<AnyCancellable>() // For observing RankingService
    
    // Badges Configuration
    private var allBadges: [Badge] = [
        Badge(title: "First Steps", description: NSLocalizedString("badge.desc.first_steps", comment: "첫 번째 런을 완료하세요."), iconName: "figure.skiing.downhill", unlockCondition: { stats in stats.totalRuns >= 1 }),
        Badge(title: "Marathoner", description: NSLocalizedString("badge.desc.marathoner", comment: "총 100km를 주행하세요."), iconName: "figure.walk", unlockCondition: { stats in stats.totalDistance >= 100.0 }),
        Badge(title: "Speed Demon", description: NSLocalizedString("badge.desc.speed_demon", comment: "최고 속도 80km/h에 도달하세요."), iconName: "flame.fill", unlockCondition: { stats in stats.maxSpeed >= 80.0 }),
        Badge(title: "Century Club", description: NSLocalizedString("badge.desc.century_club", comment: "100런을 완주하세요."), iconName: "100.square.fill", unlockCondition: { stats in stats.totalRuns >= 100 }),
        Badge(title: "Everest", description: NSLocalizedString("badge.desc.everest", comment: "총 하강고도 8,848m를 달성하세요."), iconName: "mountain.2.fill", unlockCondition: { stats in stats.totalVerticalDrop >= 8848.0 }),
        
        // New Badges
        Badge(title: "High Flyer", description: NSLocalizedString("badge.desc.high_flyer", comment: "총 하강고도 20,000m를 달성하세요."), iconName: "airplane.departure", unlockCondition: { stats in stats.totalVerticalDrop >= 20000.0 }),
        Badge(title: "Early Bird", description: NSLocalizedString("badge.desc.early_bird", comment: "오전 9시 이전에 출발하세요."), iconName: "sunrise.fill", unlockCondition: { _ in false }), // Needs session time check logic
        Badge(title: "Night Owl", description: NSLocalizedString("badge.desc.night_owl", comment: "오후 7시 이후에 주행하세요."), iconName: "moon.stars.fill", unlockCondition: { _ in false }), // Needs session time check logic
        Badge(title: "Safe Rider", description: NSLocalizedString("badge.desc.safe_rider", comment: "크래시 없이 10회 기록하세요."), iconName: "checkmark.shield.fill", unlockCondition: { stats in stats.totalRuns >= 50 }), // Placeholder
        Badge(title: "Speed Hunter", description: NSLocalizedString("badge.desc.speed_hunter_100", comment: "최고 속도 100km/h에 도달하세요."), iconName: "speedometer", unlockCondition: { stats in stats.maxSpeed >= 100.0 }),
        Badge(title: "Ultra Distance", description: NSLocalizedString("badge.desc.distance_300", comment: "총 300km를 주행하세요."), iconName: "figure.walk.circle.fill", unlockCondition: { stats in stats.totalDistance >= 300.0 }),
        Badge(title: "Vert King", description: NSLocalizedString("badge.desc.vertical_50k", comment: "총 하강고도 50,000m를 달성하세요."), iconName: "mountain.2.circle.fill", unlockCondition: { stats in stats.totalVerticalDrop >= 50000.0 }),
        Badge(title: "All Day Rider", description: NSLocalizedString("badge.desc.all_day", comment: "총 주행 시간 6시간을 달성하세요."), iconName: "clock.badge.checkmark", unlockCondition: { stats in stats.totalDuration >= 21600 }),
        Badge(title: "Edge Elite", description: NSLocalizedString("badge.desc.edge_elite", comment: "엣지 스코어 900점을 돌파하세요."), iconName: "bolt.circle.fill", unlockCondition: { stats in stats.highestEdgeScore >= 900 }),
        Badge(title: "Flow Elite", description: NSLocalizedString("badge.desc.flow_elite", comment: "플로우 스코어 900점을 돌파하세요."), iconName: "waveform.path.ecg", unlockCondition: { stats in stats.highestFlowScore >= 900 })
    ]
    
    private enum Keys {
        static let nickname = "user_nickname"
        static let bio = "user_bio"
        static let instagramId = "user_instagram_id"
        static let earnedBadges = "user_earned_badges"
        static let featuredBadges = "profile_featured_badges"
        static let featuredBadgesLastChangedAt = "profile_featured_badges_last_changed_at"
        static let featuredBadgesPendingUpload = "profile_featured_badges_pending_upload"
    }
    
    private init() {
        // Load persist data
        let savedNickname = UserDefaults.standard.string(forKey: Keys.nickname) ?? "skier"
        let savedBio = UserDefaults.standard.string(forKey: Keys.bio)
        let savedInstagramId = UserDefaults.standard.string(forKey: Keys.instagramId)
        let earnedBadgeTitles = UserDefaults.standard.stringArray(forKey: Keys.earnedBadges) ?? []
        let savedFeaturedBadges = UserDefaults.standard.stringArray(forKey: Keys.featuredBadges) ?? []
        
        // Sync badges initial state
        for i in 0..<allBadges.count {
            if earnedBadgeTitles.contains(allBadges[i].title) {
                allBadges[i].isEarned = true
            }
        }
        
        // Initialize with default/empty profile
        self.profile = GamificationProfile(
            level: 1,
            currentXP: 0,
            tier: .bronze,
            stats: UserStats(),
            badges: [], // Will be populated in init
            featuredBadgeTitles: savedFeaturedBadges,
            nickname: savedNickname,
            bio: savedBio,
            instagramId: savedInstagramId,
            avatarUrl: nil
        )
        // Set badges from updated allBadges
        self.profile.badges = allBadges
        self.featuredBadgeTitles = savedFeaturedBadges
    }

    private struct SessionStatsSnapshot {
        let runCount: Int
        let distanceMeters: Double
        let maxSpeed: Double
        let verticalDrop: Double
        let duration: TimeInterval
        let allEdgeScores: [Int]
        let allFlowScores: [Int]
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
        // Deprecated: user updateProfileInfo instead
        updateProfileInfo(nickname: name, bio: self.profile.bio, instagramId: self.profile.instagramId)
    }
    
    func updateProfileInfo(nickname: String, bio: String?, instagramId: String?) {
        // Update local object
        self.profile.nickname = nickname
        self.profile.bio = bio
        self.profile.instagramId = instagramId
        
        // Persist
        UserDefaults.standard.set(nickname, forKey: Keys.nickname)
        if let bio = bio { UserDefaults.standard.set(bio, forKey: Keys.bio) }
        else { UserDefaults.standard.removeObject(forKey: Keys.bio) }
        
        if let instagramId = instagramId { UserDefaults.standard.set(instagramId, forKey: Keys.instagramId) }
        else { UserDefaults.standard.removeObject(forKey: Keys.instagramId) }
    }

    // MARK: - Featured Badges

    var canChangeFeaturedBadges: Bool {
        guard let lastDate = featuredBadgesLastChangedDate else { return true }
        return !Calendar.current.isDateInToday(lastDate)
    }

    var featuredBadgesRemainingDays: Int? {
        guard let nextDate = featuredBadgesNextChangeDate, !canChangeFeaturedBadges else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: nextDate).day ?? 0
        return max(1, days)
    }

    var isFeaturedBadgesUploadPending: Bool {
        UserDefaults.standard.bool(forKey: Keys.featuredBadgesPendingUpload)
    }

    func clearFeaturedBadgesUploadPending() {
        UserDefaults.standard.set(false, forKey: Keys.featuredBadgesPendingUpload)
    }

    @discardableResult
    func updateFeaturedBadges(_ titles: [String]) -> Bool {
        let normalized = titles.filter { !$0.isEmpty }
        if normalized == featuredBadgeTitles {
            return true
        }
        guard canChangeFeaturedBadges else {
            return false
        }
        featuredBadgeTitles = normalized
        profile.featuredBadgeTitles = normalized
        UserDefaults.standard.set(normalized, forKey: Keys.featuredBadges)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Keys.featuredBadgesLastChangedAt)
        UserDefaults.standard.set(true, forKey: Keys.featuredBadgesPendingUpload)
        return true
    }

    private var featuredBadgesLastChangedDate: Date? {
        let interval = UserDefaults.standard.double(forKey: Keys.featuredBadgesLastChangedAt)
        guard interval > 0 else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    private var featuredBadgesNextChangeDate: Date? {
        guard let lastDate = featuredBadgesLastChangedDate else { return nil }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: lastDate)
        return calendar.date(byAdding: .day, value: 1, to: startOfDay)
    }
    
    // MARK: - Private Logic

    private func updateProfile(from snapshots: [SessionStatsSnapshot]) {
        var newStats = UserStats()
        var totalXP = 0
        
        var allEdgeScores: [Int] = []
        var allFlowScores: [Int] = []
        
        for session in snapshots {
            // 1. Accumulate Stats
            newStats.totalRuns += session.runCount
            newStats.totalDistance += (session.distanceMeters / 1000.0) // Convert m to km
            newStats.maxSpeed = max(newStats.maxSpeed, session.maxSpeed)
            newStats.totalVerticalDrop += session.verticalDrop
            newStats.totalDuration += session.duration
            
            // Collect scores
            allEdgeScores.append(contentsOf: session.allEdgeScores)
            allFlowScores.append(contentsOf: session.allFlowScores)
            
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
        
        // Calculate Top 3 Averages for Edge/Flow
        newStats.highestEdgeScore = calculateTop3Average(allEdgeScores)
        newStats.highestFlowScore = calculateTop3Average(allFlowScores)
        
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
                featuredBadgeTitles: self.featuredBadgeTitles,
                nickname: self.profile.nickname,
                bio: self.profile.bio,
                instagramId: self.profile.instagramId,
                avatarUrl: self.profile.avatarUrl
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
        // Mutate allBadges in-place to persist state
        for i in 0..<allBadges.count {
            if !allBadges[i].isEarned && allBadges[i].unlockCondition(stats) {
                allBadges[i].isEarned = true
                print("🏆 Badge Unlocked: \(allBadges[i].title)")
                saveBadgeEarned(allBadges[i].title)
            }
        }
        return allBadges
    }
    
    private func saveBadgeEarned(_ title: String) {
        var names = UserDefaults.standard.stringArray(forKey: Keys.earnedBadges) ?? []
        if !names.contains(title) {
            names.append(title)
            UserDefaults.standard.set(names, forKey: Keys.earnedBadges)
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
            
            return SessionStatsSnapshot(
                runCount: session.runCount,
                distanceMeters: session.distance,
                maxSpeed: session.maxSpeed,
                verticalDrop: session.verticalDrop,
                duration: session.duration,
                allEdgeScores: runScores.edge,
                allFlowScores: runScores.flow
            )
        }
    }
    
    // MARK: - Helpers
    
    private func calculateTop3Average(_ scores: [Int]) -> Int {
        guard !scores.isEmpty else { return 0 }
        let top3 = scores.sorted(by: >).prefix(3)
        let sum = top3.reduce(0, +)
        let avg = Double(sum) / Double(top3.count)
        return Int(avg.rounded())
    }
}
