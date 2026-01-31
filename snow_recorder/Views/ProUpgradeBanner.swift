import SwiftUI

struct ProUpgradeBanner: View {
    // Theme Colors matching the design
    private let neonGreen = Color(red: 107/255, green: 249/255, blue: 6/255)
    private let surfaceDark = Color(red: 18/255, green: 18/255, blue: 18/255)
    
    // Animation State
    @State private var isPulsing = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Glow Effect behind Icon
            ZStack {
                Circle()
                    .fill(neonGreen.opacity(0.1))
                    .frame(width: 80, height: 80)
                    .blur(radius: 20)
                    .offset(x: -20, y: -20)
            }
            .frame(width: 0, height: 0) // Zero frame so it doesn't affect layout
            
            // Icon (Crown)
            ZStack {
                Circle()
                    .fill(Color(red: 26/255, green: 26/255, blue: 26/255)) // surface-light equivalent
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                    .shadow(color: .black.opacity(0.2), radius: 2)
                
                // Animated Pulse Ring
                Circle()
                    .fill(neonGreen.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .scaleEffect(isPulsing ? 1.2 : 1.0)
                    .opacity(isPulsing ? 0.0 : 0.5)
                    .animation(Animation.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: isPulsing)
                
                Image(systemName: "crown.fill")
                    .font(.system(size: 20))
                    .foregroundColor(neonGreen)
                    .shadow(color: neonGreen.opacity(0.8), radius: 4, x: 0, y: 0)
            }
            .onAppear {
                isPulsing = true
            }
            
            // Text Content
            VStack(alignment: .leading, spacing: 2) {
                Text("UNLOCK PRO ANALYSIS")
                    .font(.system(size: 14, weight: .bold))
                    .italic()
                    .foregroundColor(.white)
                    .tracking(0.5)
                    .lineLimit(1)
                
                Text("Get full access to Edge & Flow scores.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Upgrade Button
            Text("UPGRADE")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(neonGreen)
                .clipShape(Capsule())
                .shadow(color: neonGreen.opacity(0.3), radius: 10, x: 0, y: 0)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        }
        .padding(12)
        .background(surfaceDark.opacity(0.95))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [neonGreen, neonGreen.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
        .padding(.horizontal, 24)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        ProUpgradeBanner()
    }
}
