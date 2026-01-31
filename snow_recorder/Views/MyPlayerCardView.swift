import SwiftUI

struct MyPlayerCardView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var gamificationService = GamificationService.shared
    @State private var showEditProfile = false
    
    // Design Colors
    let primaryGreen = Color(red: 107/255, green: 249/255, blue: 6/255) // #6bf906
    let backgroundDark = Color(red: 23/255, green: 35/255, blue: 15/255) // #17230f
    let cardBackground = Color(red: 36/255, green: 53/255, blue: 24/255) // #243518
    let glassEffect = Color.white.opacity(0.1)
    
    var profile: GamificationProfile {
        gamificationService.profile
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
                    // Optional: Share specific Logic
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
                        
                        // Default Avatar (or custom if stored)
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
                            Text("\(profile.tier.rawValue.uppercased()) TIER")
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
                        Text(profile.nickname.uppercased())
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .tracking(-1)
                        
                        if let bio = profile.bio, !bio.isEmpty {
                            Text(bio)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray)
                        } else {
                            Text("Ready to shred.")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray.opacity(0.5))
                        }
                    }
                    .padding(.top, 10)
                    
                    // Action Buttons (EDIT PROFILE)
                    Button(action: { showEditProfile = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "pencil")
                                .font(.system(size: 18))
                            Text("EDIT PROFILE")
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
                
                // Score Rings Section
                HStack(spacing: 16) {
                    // Always show own stats
                    scoreRingCard(title: "EDGE SCORE", score: profile.stats.highestEdgeScore)
                    scoreRingCard(title: "FLOW SCORE", score: profile.stats.highestFlowScore)
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
                        value: String(format: "%.1f", profile.stats.totalDistance),
                        unit: "km",
                        primaryGreen: primaryGreen,
                        bg: cardBackground
                    )
                    
                    // Card 2: Runs
                    StatCard(
                        icon: "figure.skiing.downhill",
                        title: "TOTAL RUNS",
                        value: "\(profile.stats.totalRuns)",
                        unit: "Runs",
                        primaryGreen: primaryGreen,
                        bg: cardBackground
                    )
                }
                .padding(24)
                
                // Highlights Section (Best Run - Mock Logic for UI consistency)
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
                                Text("MY BEST RUN")
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(1)
                                    .foregroundColor(primaryGreen)
                            }
                            
                            Text("High1 Apollo") // Mock
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                            
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(Int(profile.stats.maxSpeed))")
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
                
                // Featured Badges
                VStack(alignment: .leading, spacing: 16) {
                    Text("FEATURED BADGES")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(.gray)
                        .padding(.horizontal, 24)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            Spacer().frame(width: 8)
                            
                            // Load featured badges (fallback to earned)
                            ForEach(featuredBadges) { badge in
                                ProfileBadgeItem(
                                    icon: badge.iconName,
                                    title: badge.title,
                                    primaryGreen: primaryGreen,
                                    bg: cardBackground
                                )
                            }
                            
                            // Placeholders if empty
                            if featuredBadges.isEmpty {
                                Text("No badges earned yet.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                                    .padding(.leading, 16)
                            }
                            
                            Spacer().frame(width: 8)
                        }
                    }
                }
                .padding(.top, 24)
                .padding(.bottom, 60)
            }
        }
        .background(backgroundDark.ignoresSafeArea())
        .sheet(isPresented: $showEditProfile) {
            EditProfileView(isPresented: $showEditProfile)
        }
    }
    
    // MARK: - Helper Views (Reusing logic from OtherUserProfileView via copy, or could refactor to shared)
    // For now, duplicating simple helpers to keep file self-contained as requested.
    
    private func scoreRingCard(title: String, score: Int) -> some View {
        VStack {
            ZStack {
                // Background Track
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 6)
                    .frame(width: 70, height: 70) 
                
                // Ring Gauge
                RingGaugeView(progress: Double(score) / 1000.0, color: primaryGreen)
                    .frame(width: 70, height: 70)
                
                // Score Text
                VStack(spacing: -2) {
                    Text("\(score)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
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

    private var featuredBadges: [Badge] {
        let earned = profile.badges.filter { $0.isEarned }
        let featuredTitles = profile.featuredBadgeTitles
        if featuredTitles.isEmpty {
            return Array(earned.prefix(3))
        }
        let badgeByTitle = Dictionary(uniqueKeysWithValues: earned.map { ($0.title, $0) })
        let ordered = featuredTitles.compactMap { badgeByTitle[$0] }
        return Array(ordered.prefix(3))
    }
}
