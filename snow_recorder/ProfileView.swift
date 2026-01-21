import SwiftUI
import SwiftData

/// 마이페이지 뷰 (Tab 3) - Gamified Profile Design
struct ProfileView: View {
    @StateObject private var viewModel = MyPageViewModel()
    
    // SwiftData에서 모든 주행 기록 가져오기
    @Query private var sessions: [RunSession]
    
    let neonGreen = Color(red: 107/255, green: 249/255, blue: 6/255)
    let surfaceDark = Color(red: 18/255, green: 18/255, blue: 18/255)
    
    var body: some View {
        ZStack {
            // [Background] Pattern
            Color.black.ignoresSafeArea()
            VStack {
                // 상단 그리드 패턴 (이미지 대용)
               GridPattern()
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    .frame(height: 300)
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                Spacer()
            }
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // [Header]
                    HStack {
                        // Avatar
                        ZStack(alignment: .bottomTrailing) {
                            Circle()
                                .fill(Color.gray)
                                .frame(width: 48, height: 48)
                                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                            
                            // Level Badge
                            Text("LV.\(viewModel.userProfile.level)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(neonGreen)
                                .clipShape(Capsule())
                                .offset(x: 4, y: 4)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.userProfile.nickname)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                            Text("Online")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        // Settings Button
                        Button(action: {}) {
                            Circle()
                                .fill(surfaceDark)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Image(systemName: "gearshape.fill")
                                        .foregroundColor(.white)
                                )
                                .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    
                    // [Hero Status Card] Dynamic Tier
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(surfaceDark)
                            .overlay(
                                RoundedRectangle(cornerRadius: 24)
                                    .stroke(
                                        LinearGradient(colors: [neonGreen.opacity(0.5), .clear], startPoint: .topLeading, endPoint: .bottomTrailing),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: neonGreen.opacity(0.1), radius: 20, x: 0, y: 0)
                        
                        // Decor
                        VStack {
                            HStack { Spacer(); Circle().fill(neonGreen.opacity(0.1)).frame(width: 100, height: 100).blur(radius: 30) }
                            Spacer()
                            HStack { Circle().fill(Color.blue.opacity(0.1)).frame(width: 80, height: 80).blur(radius: 20); Spacer() }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(viewModel.userProfile.tier.tierName.rawValue.uppercased())
                                        .font(.system(size: 32, weight: .black))
                                        .italic()
                                        .foregroundColor(.white)
                                    Text("TIER")
                                        .font(.system(size: 32, weight: .black))
                                        .italic()
                                        .foregroundColor(neonGreen)
                                }
                                Spacer()
                                Image(systemName: "trophy.fill")
                                    .font(.title)
                                    .foregroundColor(neonGreen)
                            }
                            
                            Text("TOP \(String(format: "%.1f", viewModel.userProfile.tier.topPercent))% OF RIDERS")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.gray)
                                .padding(.bottom, 12)
                            
                            Divider().background(Color.white.opacity(0.1))
                            
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("SEASON ENDS")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.gray)
                                    Text(remainingDays(to: viewModel.userProfile.tier.seasonEndDate))
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                Spacer()
                                Button(action: {}) {
                                    Text("VIEW BENEFITS")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color.white.opacity(0.05))
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
                                }
                            }
                            .padding(.top, 12)
                        }
                        .padding(24)
                    }
                    .frame(height: 220)
                    .padding(.horizontal, 24)
                    
                    // [XP Progress]
                    VStack(spacing: 8) {
                        HStack {
                            Text("LEVEL PROGRESS")
                                .font(.system(size: 12, weight: .bold))
                                .tracking(1)
                                .foregroundColor(.gray)
                            Spacer()
                            HStack(spacing: 0) {
                                Text("\(viewModel.userProfile.currentXP)")
                                    .foregroundColor(neonGreen)
                                Text(" / 3,000 XP") // Max XP는 임시 고정
                                    .foregroundColor(.gray)
                            }
                            .font(.system(size: 12, weight: .bold))
                        }
                        
                        // Progress Bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(surfaceDark)
                                Capsule().fill(neonGreen)
                                    .frame(width: geo.size.width * (Double(viewModel.userProfile.currentXP) / 3000.0)) // Progress 계산
                                    .shadow(color: neonGreen.opacity(0.5), radius: 5)
                            }
                        }
                        .frame(height: 12)
                        
                        Text("\(3000 - viewModel.userProfile.currentXP) XP to Level \(viewModel.userProfile.level + 1)")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.horizontal, 24)
                    
                    // [Stats Grid]
                    HStack(spacing: 12) {
                        ProfileStatBox(icon: "globe", title: "GLOBAL RANK", value: "#\(viewModel.userProfile.stats.globalRanking)", subValue: "", neonGreen: neonGreen)
                        ProfileStatBox(icon: "figure.snowboarding", title: "TOTAL DIST", value: "\(Int(viewModel.userProfile.stats.totalDistance))", subValue: "km", neonGreen: neonGreen)
                        ProfileStatBox(icon: "speedometer", title: "MAX SPEED", value: "\(Int(viewModel.userProfile.stats.maxSpeed))", subValue: "km/h", neonGreen: neonGreen)
                    }
                    .padding(.horizontal, 24)
                    
                    // [Badges]
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("RECENT BADGES")
                                .font(.system(size: 12, weight: .bold))
                                .tracking(1)
                                .foregroundColor(.gray)
                            Spacer()
                            Text("View All")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(neonGreen)
                        }
                        .padding(.horizontal, 24)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 20) {
                                Spacer().frame(width: 4) // Left Padding
                                
                                ForEach(viewModel.userProfile.badges) { badge in
                                    HexBadge(
                                        icon: badge.iconName,
                                        title: badge.title,
                                        color: badge.isEarned ? neonGreen : .gray,
                                        isLocked: !badge.isEarned,
                                        neonGreen: neonGreen
                                    )
                                }
                                
                                Spacer().frame(width: 4) // Right Padding
                            }
                        }
                    }
                    
                    // [Leaderboard] (Mini)
                    VStack(spacing: 16) {
                         HStack {
                            Text("TOP SQUAD")
                                .font(.system(size: 12, weight: .bold))
                                .tracking(1)
                                .foregroundColor(.gray)
                            Spacer()
                        }
                        .padding(.horizontal, 24)
                        
                        VStack(spacing: 12) {
                            LeaderboardRow(rank: 1, name: "Snow_Bunny", level: 28, xp: "3,200", neonGreen: neonGreen)
                            LeaderboardRow(rank: 2, name: viewModel.userProfile.nickname, level: viewModel.userProfile.level, xp: "\(viewModel.userProfile.currentXP)", isMe: true, neonGreen: neonGreen)
                            LeaderboardRow(rank: 3, name: "IceCold", level: 22, xp: "2,150", neonGreen: neonGreen)
                        }
                }
            }
        }
        .onAppear {
            // 뷰가 나타날 때 통계 업데이트
            viewModel.updateStats(using: sessions)
        }
        .onChange(of: sessions) { _, newSessions in
            // 데이터가 변경(추가/삭제)될 때 통계 업데이트
            viewModel.updateStats(using: newSessions)
        }
    }
    }
    
    // 남은 기간 계산 헬퍼
    private func remainingDays(to date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: date)
        if let day = components.day, day >= 0 {
            return "\(day) Days"
        } else {
            return "Ended"
        }
    }
}

// MARK: - Subviews

struct ProfileStatBox: View {
    let icon: String
    let title: String
    let value: String
    let subValue: String
    let neonGreen: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(neonGreen)
            
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.gray)
            
            HStack(alignment: .bottom, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                Text(subValue)
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .padding(.bottom, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(red: 18/255, green: 18/255, blue: 18/255))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

struct HexBadge: View {
    let icon: String
    let title: String
    let color: Color
    var isLocked: Bool = false
    let neonGreen: Color
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Hexagon()
                    .fill(isLocked ? Color.white.opacity(0.05) : color.opacity(0.2))
                    .frame(width: 70, height: 80)
                    .overlay(
                        Hexagon()
                            .stroke(isLocked ? Color.white.opacity(0.1) : color.opacity(0.5), lineWidth: 2)
                    )
                
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isLocked ? .gray : color)
                    .shadow(color: isLocked ? .clear : color.opacity(0.5), radius: 5)
            }
            
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)
                .lineLimit(2)
        }
    }
}

struct LeaderboardRow: View {
    let rank: Int
    let name: String
    let level: Int
    let xp: String
    var isMe: Bool = false
    let neonGreen: Color
    
    var body: some View {
        HStack {
            Text("\(rank)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(isMe ? neonGreen : .white)
                .frame(width: 20)
            
            Circle()
                .fill(Color.gray)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isMe ? neonGreen : .white)
                Text("LV. \(level)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(xp)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text("XP")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(12)
        .background(isMe ? neonGreen.opacity(0.1) : Color(red: 18/255, green: 18/255, blue: 18/255))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isMe ? neonGreen.opacity(0.3) : Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

struct Hexagon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let corner = w / 4
        
        path.move(to: CGPoint(x: w / 2, y: 0))
        path.addLine(to: CGPoint(x: w, y: h / 4))
        path.addLine(to: CGPoint(x: w, y: h * 3 / 4))
        path.addLine(to: CGPoint(x: w / 2, y: h))
        path.addLine(to: CGPoint(x: 0, y: h * 3 / 4))
        path.addLine(to: CGPoint(x: 0, y: h / 4))
        path.closeSubpath()
        return path
    }
}

// Background Grid Pattern
struct GridPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 40
        
        for x in stride(from: 0, to: rect.width, by: step) {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
        }
        
        for y in stride(from: 0, to: rect.height, by: step) {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        return path
    }
}

#Preview {
    ProfileView()
}
