import SwiftUI

struct BadgeListView: View {
    @Environment(\.dismiss) var dismiss
    let badges: [Badge]
    @State private var selectedBadge: Badge?
    
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
                                BadgeItem(badge: badge, neonGreen: neonGreen) {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        selectedBadge = badge
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 50)
                    }
                }
                
                if let badge = selectedBadge {
                    Color.black.opacity(0.7)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) {
                                selectedBadge = nil
                            }
                        }
                    
                    BadgeDetailCard(
                        badge: badge,
                        neonGreen: neonGreen,
                        surfaceCard: surfaceCard
                    ) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            selectedBadge = nil
                        }
                    }
                    .padding(.horizontal, 24)
                    .transition(.scale.combined(with: .opacity))
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
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
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
                        Text("badge.detail.locked")
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
        .buttonStyle(.plain)
    }
}

private struct BadgeDetailCard: View {
    let badge: Badge
    let neonGreen: Color
    let surfaceCard: Color
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(LocalizedStringKey(badge.isEarned ? "badge.detail.earned" : "badge.detail.locked"))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundColor(badge.isEarned ? neonGreen : .gray)
                
                Spacer()
                
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            ZStack {
                Hexagon()
                    .fill(badge.isEarned ? neonGreen.opacity(0.15) : Color.white.opacity(0.08))
                    .frame(width: 100, height: 110)
                    .overlay(
                        Hexagon()
                            .stroke(badge.isEarned ? neonGreen : Color.white.opacity(0.2), lineWidth: 1.5)
                    )
                    .shadow(color: badge.isEarned ? neonGreen.opacity(0.5) : .clear, radius: 12)
                
                Image(systemName: badge.iconName)
                    .font(.system(size: 36))
                    .foregroundColor(badge.isEarned ? neonGreen : .gray)
            }
            
            VStack(spacing: 8) {
                Text(badge.title)
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text(LocalizedStringKey(badge.descriptionKey))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            
            Text("badge.detail.tap_to_close")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.0)
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(neonGreen.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

#Preview {
    BadgeListView(badges: [
        Badge(title: "First Run", descriptionKey: "badge.desc.first_steps", iconName: "figure.skiing.downhill", isEarned: true, unlockCondition: { _ in true }),
        Badge(title: "Marathoner", descriptionKey: "badge.desc.marathoner", iconName: "figure.walk", isEarned: false, unlockCondition: { _ in false })
    ])
    .preferredColorScheme(.dark)
}
