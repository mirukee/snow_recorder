import SwiftUI
import CoreLocation
import FirebaseAuth

struct OtherUserProfileView: View {
    @Environment(\.dismiss) var dismiss
    let initialUser: LeaderboardEntry
    @State private var fullUser: LeaderboardEntry?
    @State private var isLoading = false
    
    // Design Colors
    let primaryGreen = Color(red: 107/255, green: 249/255, blue: 6/255) // #6bf906
    let backgroundDark = Color(red: 23/255, green: 35/255, blue: 15/255) // #17230f
    let cardBackground = Color(red: 36/255, green: 53/255, blue: 24/255) // #243518
    let glassEffect = Color.white.opacity(0.1)
    
    // Active User (Initial -> Full)
    var user: LeaderboardEntry {
        fullUser ?? initialUser
    }

    private var isCurrentUser: Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        return uid == initialUser.userId
    }
    
    // Display Logic
    var displayedEdgeScore: Int {
        user.bestEdge ?? (user.metric == .edge ? Int(user.value) : 0)
    }
    
    var displayedFlowScore: Int {
        user.bestFlow ?? (user.metric == .flow ? Int(user.value) : 0)
    }
    
    var displayedDistance: String {
        let val = user.seasonDistance ?? (user.metric == .distance ? user.value : 0)
        return String(format: "%.1f", val / 1000.0)
    }
    
    var displayedRunCount: String {
        let val = user.seasonRunCount ?? (user.metric == .runCount ? Int(user.value) : 0)
        return "\(val)"
    }
    
    init(user: LeaderboardEntry) {
        self.initialUser = user
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header (Back + Share)
                HStack {
                    Button(action: { dismiss() }) {
                        Circle()
                            .fill(glassEffect)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Image(systemName: "chevron.left")
                                    .foregroundColor(.white)
                                    .font(.system(size: 16, weight: .bold))
                            )
                    }
                    Spacer()
                    Button(action: { /* Share Logic Placeholder */ }) {
                        Circle()
                            .fill(glassEffect)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundColor(.white)
                                    .font(.system(size: 16, weight: .bold))
                            )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 8)
                
                // Profile Section
                VStack(spacing: 24) {
                    // Avatar & Badge
                    ZStack(alignment: .bottom) {
                        // Glow
                        Circle()
                            .fill(primaryGreen)
                            .frame(width: 140, height: 140)
                            .blur(radius: 20)
                            .opacity(0.2)
                        
                        // Default Avatar
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 128, height: 128)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 60)
                                    .foregroundColor(.white.opacity(0.5))
                            )
                            .overlay(Circle().stroke(primaryGreen, lineWidth: 3))
                            .shadow(color: primaryGreen.opacity(0.3), radius: 10)
                        
                        // Tier Badge
                        HStack(spacing: 4) {
                            Image(systemName: "diamond.fill")
                                .font(.system(size: 12))
                                .foregroundColor(primaryGreen)
                            Text("DIAMOND TIER") // Placeholder for rank-based tier
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1)
                                .foregroundColor(primaryGreen)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(primaryGreen.opacity(0.5), lineWidth: 1))
                        .offset(y: 14)
                    }
                    .padding(.top, 20)
                    
                    // Name & Bio
                    VStack(spacing: 4) {
                        Text(user.userName.uppercased())
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .tracking(-1)
                        
                        Text("Chasing powder since '98") // Mock Bio
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 10)
                    
                    // Action Buttons (Instagram Only, Full Width)
                    Button(action: { /* Instagram Logic Placeholder */ }) {
                        HStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 18))
                            Text("INSTAGRAM")
                                .font(.system(size: 14, weight: .bold))
                                .tracking(1)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, 24)
                }
                
                if isLoading {
                    ProgressView()
                        .padding(40)
                        .tint(primaryGreen)
                } else {
                    // Score Rings Section
                    HStack(spacing: 16) {
                        // Edge Score (Always show if available, else 0)
                        scoreRingCard(title: "EDGE SCORE", score: displayedEdgeScore, isAvailable: displayedEdgeScore > 0)
                        // Flow Score
                        scoreRingCard(title: "FLOW SCORE", score: displayedFlowScore, isAvailable: displayedFlowScore > 0)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    
                    // Bento Grid Stats (Distance & Runs)
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        
                        // Card 1: Distance
                        StatCard(
                            icon: "map.fill",
                            title: "DISTANCE",
                            value: displayedDistance,
                            unit: "km",
                            primaryGreen: primaryGreen,
                            bg: cardBackground
                        )
                        
                        // Card 2: Runs
                        StatCard(
                            icon: "figure.skiing.downhill",
                            title: "TOTAL RUNS",
                            value: displayedRunCount,
                            unit: "Runs",
                            primaryGreen: primaryGreen,
                            bg: cardBackground
                        )
                    }
                    .padding(24)
                }
                
                // Highlights Section (Best Run)
                VStack(spacing: 16) {
                    ZStack(alignment: .bottomLeading) {
                        // Background Image
                        AsyncImage(url: URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuCSXpsiWszQbcckBonwMb3t2rJI6N59kSt9I6PefWB3y76Fjh3dG9DsMHvGa1h-JqymY0PpyoTFq4W3oPbYiukb_HljkqOZc0PQpX_Rj4Ftzq8BJ8Vnf4kdXMWXPsts0S9zndo_zJ-qc2VU0_ak9sAtyUqNGVYjaghn1eJvug8LGzSq9k3tiiGY-Yxocz2-IGRJ4Fsg9GMT0tUEzhN9AY7KZujMZuV7-x3ciOzHBvbnG-SdwuUJlfggzYlC2Qki5vfhrcym6dBfIBo")) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Color.gray.opacity(0.3)
                            }
                        }
                        .frame(height: 160)
                        .clipped()
                        .overlay(LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .top))
                        
                        // Content
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "trophy.fill")
                                    .foregroundColor(primaryGreen)
                                    .font(.system(size: 14))
                                Text("BEST RUN HIGHLIGHT")
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(1)
                                    .foregroundColor(primaryGreen)
                            }
                            
                            Text("Apollo 6")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                            
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("92")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(primaryGreen)
                                Text("km/h Top Speed")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                        .padding(20)
                    }
                    .cornerRadius(32)
                    .clipped()
                }
                .padding(.horizontal, 24)
                
                // Earned Badges
                VStack(alignment: .leading, spacing: 16) {
                    Text("EARNED BADGES")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(.gray)
                        .padding(.horizontal, 24)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            Spacer().frame(width: 8)
                            
                            ProfileBadgeItem(icon: "bolt.fill", title: "Speed Demon", primaryGreen: primaryGreen, bg: cardBackground)
                            ProfileBadgeItem(icon: "mountain.2.fill", title: "Explorer", themeColor: .gray, bg: cardBackground)
                            ProfileBadgeItem(icon: "snowflake", title: "Frostbite", themeColor: .gray, bg: cardBackground)
                            ProfileBadgeItem(icon: "alarm.fill", title: "Early Bird", themeColor: .gray, bg: cardBackground)
                            
                            Spacer().frame(width: 8)
                        }
                    }
                }
                .padding(.top, 24)
                .padding(.bottom, 60)
            }
        }
        .background(backgroundDark.ignoresSafeArea())
        .task {
            isLoading = true
            if isCurrentUser {
                fullUser = mergeLocalStats(into: initialUser)
            }
            if let fetched = await RankingService.shared.fetchUserProfile(userId: initialUser.userId) {
                // 리더보드에서 넘어온 컨텍스트(랭크/메트릭/값)는 유지하고, 확장 스탯만 덮어쓰기
                var merged = initialUser
                merged.seasonDistance = fetched.seasonDistance
                merged.seasonRunCount = fetched.seasonRunCount
                merged.bestEdge = fetched.bestEdge
                merged.bestFlow = fetched.bestFlow
                if isCurrentUser {
                    merged = mergeLocalStats(into: merged)
                }
                self.fullUser = merged
            }
            isLoading = false
        }
    }
    
    // MARK: - Helper Views
    
    private func scoreRingCard(title: String, score: Int, isAvailable: Bool) -> some View {
        VStack {
            ZStack {
                // Background Track
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 6)
                    .frame(width: 70, height: 70) 
                
                if isAvailable {
                    // Ring Gauge
                    RingGaugeView(progress: Double(score) / 1000.0, color: primaryGreen)
                        .frame(width: 70, height: 70)
                    
                    // Score Text
                    VStack(spacing: -2) {
                        Text("\(score)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }
                } else {
                    // Placeholder Text
                    Text("-")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.gray.opacity(0.3))
                }
            }
            .padding(.bottom, 8)
            
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(cardBackground)
        .cornerRadius(24)
    }

    // 내 프로필일 때는 로컬 통계로 엣지/플로우를 보강
    private func mergeLocalStats(into entry: LeaderboardEntry) -> LeaderboardEntry {
        let profile = GamificationService.shared.profile
        var updated = entry
        if profile.stats.highestEdgeScore > 0 {
            updated.bestEdge = profile.stats.highestEdgeScore
        }
        if profile.stats.highestFlowScore > 0 {
            updated.bestFlow = profile.stats.highestFlowScore
        }
        if profile.stats.totalRuns > 0 {
            updated.seasonRunCount = profile.stats.totalRuns
        }
        if profile.stats.totalDistance > 0 {
            updated.seasonDistance = profile.stats.totalDistance * 1000.0
        }
        return updated
    }
}

// MARK: - Components

struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let unit: String
    let primaryGreen: Color
    let bg: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(.gray)
                    .font(.system(size: 16))
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundColor(.gray)
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                
                if !unit.isEmpty && value != "-" {
                    Text(unit)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bg)
        .cornerRadius(32)
    }
}

struct ProfileBadgeItem: View {
    let icon: String
    let title: String
    var primaryGreen: Color? = nil
    var themeColor: Color = .gray
    let bg: Color
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                HexagonShape()
                    .fill(bg)
                    .frame(width: 80, height: 80)
                
                if let green = primaryGreen {
                    HexagonShape()
                        .fill(green.opacity(0.1))
                        .frame(width: 80, height: 80)
                }

                Image(systemName: icon)
                    .font(.system(size: 30))
                    .foregroundColor(primaryGreen ?? themeColor.opacity(0.5))
                    .shadow(color: (primaryGreen ?? .clear).opacity(0.6), radius: 8)
            }
            
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundColor(.gray)
        }
    }
}

// Reuse HexagonShape
struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        
        path.move(to: CGPoint(x: width * 0.5, y: 0))
        path.addLine(to: CGPoint(x: width, y: height * 0.25))
        path.addLine(to: CGPoint(x: width, y: height * 0.75))
        path.addLine(to: CGPoint(x: width * 0.5, y: height))
        path.addLine(to: CGPoint(x: 0, y: height * 0.75))
        path.addLine(to: CGPoint(x: 0, y: height * 0.25))
        path.closeSubpath()
        
        return path
    }
}
