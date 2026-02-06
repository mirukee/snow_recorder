import SwiftUI
import Combine
import SwiftData

/// 앱 시작 로딩 컨테이너
struct LaunchContainerView: View {
    @StateObject private var coordinator = AppLaunchCoordinator()
    
    var body: some View {
        ZStack {
            if coordinator.isReady {
                ContentView()
            } else {
                LaunchLoadingView(
                    progress: coordinator.progress,
                    statusKey: coordinator.statusKey,
                    tipKey: coordinator.tipKey
                )
                .transition(.opacity)
            }
        }
        .task {
            await coordinator.start()
        }
    }
}

/// 앱 시작 로딩 상태 관리
@MainActor
final class AppLaunchCoordinator: ObservableObject {
    @Published var isReady: Bool = false
    @Published var progress: Double = 0.0
    @Published var statusKey: String = "launch.status_syncing"
    @Published var tipKey: String = "launch.tip_1"
    
    private let tipKeys: [String] = [
        "launch.tip_1",
        "launch.tip_2",
        "launch.tip_3"
    ]
    
    private let statusKeys: [String] = [
        "launch.status_syncing",
        "launch.status_calibrating",
        "launch.status_warming"
    ]
    
    private var hasStarted: Bool = false
    
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        tipKey = tipKeys.randomElement() ?? "launch.tip_1"
        statusKey = statusKeys.first ?? "launch.status_syncing"
        
        await animateProgress(to: 0.35, duration: 0.45)
        statusKey = statusKeys[safe: 1] ?? statusKey
        tipKey = nextTip(after: tipKey)
        
        await animateProgress(to: 0.7, duration: 0.6)
        statusKey = statusKeys[safe: 2] ?? statusKey
        tipKey = nextTip(after: tipKey)
        
        await animateProgress(to: 1.0, duration: 0.4)
        
        try? await Task.sleep(nanoseconds: 220_000_000)
        withAnimation(.easeOut(duration: 0.35)) {
            isReady = true
        }
    }
    
    private func animateProgress(to target: Double, duration: Double) async {
        withAnimation(.easeInOut(duration: duration)) {
            progress = target
        }
        let nanos = UInt64(duration * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanos)
    }
    
    private func nextTip(after current: String) -> String {
        guard let index = tipKeys.firstIndex(of: current) else {
            return tipKeys.first ?? current
        }
        let nextIndex = (index + 1) % tipKeys.count
        return tipKeys[nextIndex]
    }
}

/// 로딩 화면
struct LaunchLoadingView: View {
    let progress: Double
    let statusKey: String
    let tipKey: String
    
    private let neonGreen = Color(red: 107/255, green: 249/255, blue: 6/255)
    private let bgDark = Color(red: 5/255, green: 5/255, blue: 5/255)
    
    var body: some View {
        ZStack {
            bgDark.ignoresSafeArea()
            
            GridBackground(neonGreen: neonGreen)
                .ignoresSafeArea()
            ScanlineOverlay()
                .ignoresSafeArea()
            
            CornerHUD(neonGreen: neonGreen)
                .padding(24)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // 상단 상태
                Text("launch.system_online")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(neonGreen.opacity(0.8))
                    .padding(.top, 12)
                
                Spacer()
                
                // 타이틀
                Text("launch.title")
                    .font(.system(size: 64, weight: .black))
                    .tracking(-2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .shadow(color: neonGreen.opacity(0.12), radius: 18, x: 0, y: 0)
                    .minimumScaleFactor(0.6)
                    .lineSpacing(-6)
                
                // 진행 바
                VStack(spacing: 10) {
                    HStack {
                        Text("launch.loading_modules")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(neonGreen.opacity(0.6))
                            .tracking(1)
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(neonGreen)
                    }
                    LoadingProgressBar(progress: progress, neonGreen: neonGreen)
                        .frame(height: 2)
                }
                .padding(.horizontal, 8)
                
                // 프로 팁
                VStack(spacing: 10) {
                    Text("launch.pro_tip")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(neonGreen)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(neonGreen.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(neonGreen.opacity(0.4), lineWidth: 1)
                        )
                    
                    Text(LocalizedStringKey(tipKey))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 16)
                }
                
                Spacer()
                
                // 하단 상태 라인
                LoadingStatusLine(statusKey: statusKey, neonGreen: neonGreen)
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
    }
}

/// 네온 그리드 배경
struct GridBackground: View {
    let neonGreen: Color
    
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let step: CGFloat = 60
                var path = Path()
                for x in stride(from: 0, through: size.width, by: step) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: 0, through: size.height, by: step) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(neonGreen.opacity(0.07)), lineWidth: 1)
            }
            .mask(
                RadialGradient(
                    colors: [.black, .black.opacity(0.2), .clear],
                    center: .center,
                    startRadius: 40,
                    endRadius: max(geo.size.width, geo.size.height)
                )
            )
        }
        .drawingGroup()
    }
}

/// 스캔라인 오버레이
struct ScanlineOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let lineHeight: CGFloat = 1
                let gap: CGFloat = 3
                var y: CGFloat = 0
                while y < size.height {
                    let rect = CGRect(x: 0, y: y, width: size.width, height: lineHeight)
                    context.fill(Path(rect), with: .color(.black.opacity(0.2)))
                    y += lineHeight + gap
                }
            }
            .opacity(0.12)
        }
        .allowsHitTesting(false)
    }
}

/// 코너 HUD 라인
struct CornerHUD: View {
    let neonGreen: Color
    
    var body: some View {
        GeometryReader { geo in
            let length: CGFloat = min(geo.size.width, geo.size.height) * 0.08
            Path { path in
                // 좌상단
                path.move(to: CGPoint(x: 0, y: length))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: length, y: 0))
                // 우상단
                path.move(to: CGPoint(x: geo.size.width - length, y: 0))
                path.addLine(to: CGPoint(x: geo.size.width, y: 0))
                path.addLine(to: CGPoint(x: geo.size.width, y: length))
                // 좌하단
                path.move(to: CGPoint(x: 0, y: geo.size.height - length))
                path.addLine(to: CGPoint(x: 0, y: geo.size.height))
                path.addLine(to: CGPoint(x: length, y: geo.size.height))
                // 우하단
                path.move(to: CGPoint(x: geo.size.width - length, y: geo.size.height))
                path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height - length))
            }
            .stroke(neonGreen, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .opacity(0.9)
        }
        .allowsHitTesting(false)
    }
}

/// 로딩 진행 바
struct LoadingProgressBar: View {
    let progress: Double
    let neonGreen: Color
    
    @State private var shimmerOffset: CGFloat = -1.2
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.08))
                RoundedRectangle(cornerRadius: 1)
                    .fill(neonGreen)
                    .frame(width: max(2, width * progress))
                    .shadow(color: neonGreen.opacity(0.6), radius: 8, x: 0, y: 0)
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.25), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width * 0.35)
                    .offset(x: width * shimmerOffset)
                    .opacity(0.6)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                    shimmerOffset = 1.2
                }
            }
        }
    }
}

/// 하단 상태 표시
struct LoadingStatusLine: View {
    let statusKey: String
    let neonGreen: Color
    
    @State private var isRotating: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(neonGreen)
                .rotationEffect(.degrees(isRotating ? 360 : 0))
                .onAppear {
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                        isRotating = true
                    }
                }
            Text(LocalizedStringKey(statusKey))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .tracking(2)
        }
    }
}

#Preview {
    LaunchContainerView()
        .modelContainer(for: RunSession.self, inMemory: true)
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
