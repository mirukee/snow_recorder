import SwiftUI

struct BadgeListView: View {
    @Environment(\.dismiss) var dismiss
    let badges: [Badge]
    
    // Theme Colors
    let neonGreen = Color(red: 107/255, green: 249/255, blue: 6/255)
    let backgroundDark = Color.black
    let surfaceCard = Color(hex: "111111")
    
    // Computed Properties for Stats
    private var earnedCount: Int {
        badges.filter { $0.isEarned }.count
    }
    
    private var completionPercentage: String {
        guard !badges.isEmpty else { return "0%" }
        let percent = Int(Double(earnedCount) / Double(badges.count) * 100)
        return "\(percent)%"
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                backgroundDark.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 30) {
                         // Header Stats
                        HStack(spacing: 40) {
                            statItem(value: "\(badges.count)", label: "TOTAL")
                            statItem(value: "\(earnedCount)", label: "EARNED", color: neonGreen)
                            statItem(value: completionPercentage, label: "COMPLETION")
                        }
                        .padding(.top, 20)
                        
                        // Badge Grid
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 20)], spacing: 30) {
                            ForEach(badges) { badge in
                                BadgeItem(badge: badge, neonGreen: neonGreen)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 50)
                    }
                }
            }
            .navigationTitle("BADGE COLLECTION")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
        }
    }
    
    private func statItem(value: String, label: String, color: Color = .white) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .heavy, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.gray)
                .tracking(1)
        }
    }
}

private struct BadgeItem: View {
    let badge: Badge
    let neonGreen: Color
    
    var body: some View {
        VStack(spacing: 12) {
            // Hexagon Icon
            ZStack {
                Hexagon()
                    .fill(badge.isEarned ? neonGreen.opacity(0.1) : Color.white.opacity(0.05))
                    .frame(width: 80, height: 90)
                    .overlay(
                        Hexagon()
                            .stroke(badge.isEarned ? neonGreen : Color.white.opacity(0.1), lineWidth: badge.isEarned ? 2 : 1)
                    )
                    .shadow(color: badge.isEarned ? neonGreen.opacity(0.5) : .clear, radius: 10)
                
                Image(systemName: badge.iconName)
                    .font(.system(size: 30))
                    .foregroundColor(badge.isEarned ? neonGreen : .gray)
            }
            .grayscale(badge.isEarned ? 0 : 1.0)
            
            // Text Info
            VStack(spacing: 4) {
                Text(badge.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(badge.isEarned ? .white : .gray)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(height: 30, alignment: .top) // Fixed height for alignment
                
                if !badge.isEarned {
                    Text("LOCKED")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.gray.opacity(0.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(badge.isEarned ? 1.0 : 0.6)
    }
}

#Preview {
    BadgeListView(badges: [
        Badge(title: "First Run", description: "Desc", iconName: "figure.skiing.downhill", isEarned: true, unlockCondition: { _ in true }),
        Badge(title: "Marathoner", description: "Desc", iconName: "figure.walk", isEarned: false, unlockCondition: { _ in false })
    ])
    .preferredColorScheme(.dark)
}
