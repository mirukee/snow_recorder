import SwiftUI
import SwiftData

/// 메인 대시보드 뷰 (Tab 1) - Real-time Riding Tracker Design
/// 검은색 배경(#000000)과 네온 그린(#6bf906) 포인트를 사용한 힙한 디자인
struct DashboardView: View {
    @StateObject private var locationManager = LocationManager.shared
    @StateObject private var recordManager = RecordManager.shared
    @Environment(\.modelContext) var context
    
    // MARK: - Colors
    let neonGreen = Color(red: 107/255, green: 249/255, blue: 6/255) // #6bf906
    let surfaceDark = Color(red: 17/255, green: 17/255, blue: 17/255) // #111111
    
    // MARK: - State
    @State private var isBlinking = false // REC 점 깜빡임 상태
    
    var body: some View {
        ZStack {
            // 1. 전체 배경: 리얼 블랙
            Color.black.ignoresSafeArea()
            
            // 배경 미세 그리드 라인 (수직/수평 중앙선) - Opacity 10%
            GeometryReader { geometry in
                ZStack {
                    // 수직선
                    Path { path in
                        path.move(to: CGPoint(x: geometry.size.width / 2, y: 0))
                        path.addLine(to: CGPoint(x: geometry.size.width / 2, y: geometry.size.height))
                    }
                    .stroke(neonGreen.opacity(0.1), lineWidth: 1)
                    
                    // 수평선
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geometry.size.height / 2))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height / 2))
                    }
                    .stroke(neonGreen.opacity(0.1), lineWidth: 1)
                }
            }
            .allowsHitTesting(false)
            
            // 2. 모서리 장식 (Corner Lines)
            VStack {
                HStack {
                    CornerShape(place: .topLeft).frame(width: 32, height: 32).foregroundColor(.white.opacity(0.3))
                    Spacer()
                    CornerShape(place: .topRight).frame(width: 32, height: 32).foregroundColor(.white.opacity(0.3))
                }
                Spacer()
                HStack {
                    CornerShape(place: .bottomLeft).frame(width: 32, height: 32).foregroundColor(.white.opacity(0.3))
                    Spacer()
                    CornerShape(place: .bottomRight).frame(width: 32, height: 32).foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(16)
            .allowsHitTesting(false)
            
            // 3. 메인 콘텐츠
            VStack(spacing: 0) {
                // [Header] REC, GPS, Battery
                HStack(alignment: .top) {
                    // REC & GPS
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)
                            .opacity(isBlinking ? 1.0 : 0.3) // 깜빡임 효과
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("REC")
                                .font(.system(size: 12, weight: .bold))
                                .tracking(1.0)
                                .foregroundColor(.white)
                            Text("GPS LOCKED")
                                .font(.system(size: 10, weight: .medium))
                                .tracking(0.5)
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    
                    Spacer()
                    
                    // Designed Label
                    Text("DESIGNED IN SEOUL")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                
                Spacer()
                
                // [Center] Speed Display
                VStack(spacing: 0) {
                    HStack(alignment: .bottom, spacing: 0) {
                        Text("\(String(format: "%.1f", locationManager.speed))")
                            .font(.system(size: 100, weight: .bold, design: .rounded)) // Size 130 -> 100 (화면 크기 고려 조절)
                            .tracking(-2) // 자간 좁게
                            .foregroundColor(.white)
                            .shadow(color: .white.opacity(0.1), radius: 15, x: 0, y: 0)
                        
                        Text("KM")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                            .rotationEffect(.degrees(-90))
                            .offset(x: 0, y: -20) // 위치 조정
                    }
                    
                    // Speed Bar
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(white: 0.2))
                            .frame(width: 250, height: 6)
                        
                        // 속도에 따라 차오르는 바 (최대 100km/h 가정)
                        Capsule()
                            .fill(neonGreen)
                            .frame(width: min(CGFloat(locationManager.speed) / 100.0 * 250, 250), height: 6)
                            .shadow(color: neonGreen, radius: 5)
                            .animation(.spring(), value: locationManager.speed)
                    }
                    .padding(.top, 8)
                }
                .offset(y: -20)
                
                // [Status Badge] 현재 상태 표시 (RIDING, PAUSED, ON_LIFT, RESTING)
                HStack(spacing: 6) {
                    Image(systemName: locationManager.currentState.iconName)
                        .font(.system(size: 12))
                    Text(locationManager.currentState.rawValue)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.15))
                .clipShape(Capsule())
                .foregroundColor(.white)
                .padding(.bottom, 8)
                
                // [Center Bottom] Location Badge
                HStack(spacing: 8) {
                    Image(systemName: "mountain.2.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.black)
                    
                    if let slope = locationManager.currentSlope {
                        Text("HIGH1 RESORT - \(slope.name) (\(slope.difficulty.rawValue))")
                            .font(.system(size: 12, weight: .bold))
                            .textCase(.uppercase)
                            .foregroundColor(.black)
                    } else {
                        Text("HIGH1 RESORT - LOCATING...")
                            .font(.system(size: 12, weight: .bold))
                            .textCase(.uppercase)
                            .foregroundColor(.black)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(neonGreen)
                .clipShape(Capsule())
                .shadow(color: neonGreen.opacity(0.3), radius: 10, x: 0, y: 0)
                .padding(.bottom, 24)
                
                // [Footer] Stats Grid - 6개 메트릭
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    // Row 1
                    StatsCompactCard(
                        icon: "timer",
                        title: "ELAPSED",
                        value: recordManager.formattedElapsedTime(),
                        accentColor: neonGreen
                    )
                    
                    StatsCompactCard(
                        icon: "arrow.down.right",
                        title: "VERTICAL",
                        value: "\(Int(locationManager.verticalDrop))m",
                        accentColor: neonGreen
                    )
                    
                    StatsCompactCard(
                        icon: "figure.skiing.downhill",
                        title: "RUNS",
                        value: "\(locationManager.runCount)",
                        accentColor: neonGreen
                    )
                    
                    // Row 2
                    StatsCompactCard(
                        icon: "point.topleft.down.to.point.bottomright.curvepath",
                        title: "DISTANCE",
                        value: formatDistance(locationManager.totalDistance),
                        accentColor: neonGreen
                    )
                    
                    StatsCompactCard(
                        icon: "gauge.with.dots.needle.67percent",
                        title: "MAX",
                        value: "\(Int(locationManager.maxSpeed))km/h",
                        accentColor: neonGreen
                    )
                    
                    StatsCompactCard(
                        icon: "speedometer",
                        title: "AVG",
                        value: "\(Int(locationManager.avgSpeed))km/h",
                        accentColor: neonGreen
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                
                // [Bottom] Control Buttons
                ZStack(alignment: .bottom) {
                    if recordManager.isRecording {
                        if recordManager.isPaused {
                            // [Paused State] -> Resume OR Stop
                            HStack(spacing: 40) {
                                // Resume Button
                                VStack(spacing: 12) {
                                    Button(action: {
                                        HapticManager.shared.impact(style: .medium)
                                        recordManager.resumeRecording()
                                    }) {
                                        ZStack {
                                            Circle()
                                                .fill(Color(white: 0.15))
                                                .frame(width: 80, height: 80)
                                                .overlay(
                                                    Circle().stroke(neonGreen.opacity(0.5), lineWidth: 2)
                                                )
                                            
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 30))
                                                .foregroundColor(neonGreen)
                                        }
                                    }
                                    Text("RESUME")
                                        .font(.system(size: 10, weight: .bold))
                                        .tracking(2)
                                        .foregroundColor(neonGreen.opacity(0.8))
                                }
                                
                                // Stop Button
                                VStack(spacing: 12) {
                                    Button(action: {
                                        HapticManager.shared.notification(type: .success)
                                        recordManager.stopRecording(context: context)
                                    }) {
                                        ZStack {
                                            // Outer Glow
                                            Circle()
                                                .stroke(Color.red.opacity(0.5), lineWidth: 1)
                                                .scaleEffect(1.1)
                                            
                                            // Button Base
                                            Circle()
                                                .fill(Color.white)
                                                .frame(width: 80, height: 80)
                                                .shadow(color: .white.opacity(0.2), radius: 15, x: 0, y: 0)
                                            
                                            // Stop Icon
                                            Rectangle()
                                                .fill(Color.red)
                                                .frame(width: 32, height: 32)
                                                .cornerRadius(4)
                                        }
                                    }
                                    Text("STOP")
                                        .font(.system(size: 10, weight: .bold))
                                        .tracking(2)
                                        .foregroundColor(.white.opacity(0.4))
                                }
                            }

                        } else {
                            // [Recording State] -> Pause Only (Safety)
                            VStack(spacing: 12) {
                                Button(action: {
                                    HapticManager.shared.impact(style: .heavy)
                                    recordManager.pauseRecording()
                                }) {
                                    ZStack {
                                        Circle()
                                            .fill(Color(white: 0.15))
                                            .frame(width: 80, height: 80)
                                            .overlay(
                                                Circle().stroke(Color.white.opacity(0.2), lineWidth: 1)
                                            )
                                        
                                        Image(systemName: "pause.fill")
                                            .font(.system(size: 30))
                                            .foregroundColor(.yellow)
                                    }
                                }
                                Text("PAUSE")
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(2)
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                    } else {
                        // Start Button
                        VStack(spacing: 12) {
                            Button(action: {
                                HapticManager.shared.notification(type: .success)
                                recordManager.startRecording()
                            }) {
                                ZStack {
                                    // Outer Glow
                                    Circle()
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        .scaleEffect(1.25)
                                    
                                    // White Button Base
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 80, height: 80)
                                        .shadow(color: .white.opacity(0.2), radius: 15, x: 0, y: 0)
                                    
                                    // Start Icon
                                    Circle()
                                        .fill(Color.black)
                                        .frame(width: 32, height: 32)
                                }
                            }
                            Text("START TRACKING")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(2)
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                }
                .frame(height: 140) // Fixed height container
                
                // Bottom Spacer to lift everything up
                Spacer()
                    .frame(height: 20) // Reduced from 50 since texts are now in layout
                
                // [Footer Info] Version
                HStack {
                    Text("SNOW RECORD™")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.2))
                    Spacer()
                    // Vertical Bars Deco
                    HStack(spacing: 2) {
                        Rectangle().fill(Color.white).frame(width: 2, height: 8)
                        Rectangle().fill(Color.white).frame(width: 2, height: 8)
                        Rectangle().fill(Color.white).frame(width: 2, height: 8)
                    }
                    .opacity(0.2)
                    Spacer()
                    Text("V.2.0.4")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.2))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 110) // Footer itself has the padding now
            }
        }
        .onAppear {
            locationManager.requestPermission()
            
            // REC Blinking Animation
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isBlinking = true
            }
        }
    }
}

/// 유리 질감과 반사 효과가 있는 스탯 카드
struct StatsReflectiveCard: View {
    let icon: String
    let title: String
    let value: String
    let accentColor: Color
    
    var body: some View {
        VStack(spacing: 12) {
            // Label
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(accentColor)
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.white)
            }
            .opacity(0.8)
            
            // Value
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.5)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            Color.white.opacity(0.05)
                .cornerRadius(20)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

/// 구석 장식용 모양 (ㄱ, ㄴ 모양 등)
struct CornerShape: Shape {
    enum Place { case topLeft, topRight, bottomLeft, bottomRight }
    let place: Place
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let t: CGFloat = 2 // thickness
        
        switch place {
        case .topLeft:
            path.addRect(CGRect(x: 0, y: 0, width: t, height: h)) // Vertical
            path.addRect(CGRect(x: 0, y: 0, width: w, height: t)) // Horizontal
        case .topRight:
            path.addRect(CGRect(x: w - t, y: 0, width: t, height: h))
            path.addRect(CGRect(x: 0, y: 0, width: w, height: t))
        case .bottomLeft:
            path.addRect(CGRect(x: 0, y: 0, width: t, height: h))
            path.addRect(CGRect(x: 0, y: h - t, width: w, height: t))
        case .bottomRight:
            path.addRect(CGRect(x: w - t, y: 0, width: t, height: h))
            path.addRect(CGRect(x: 0, y: h - t, width: w, height: t))
        }
        
        return path
    }
}

#Preview {
    DashboardView()
}

// MARK: - 컴팩트 스탯 카드 (LazyVGrid용)
struct StatsCompactCard: View {
    let icon: String
    let title: String
    let value: String
    let accentColor: Color
    
    var body: some View {
        VStack(spacing: 6) {
            // Icon + Title
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(accentColor)
                Text(title)
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.6))
            }
            
            // Value
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .tracking(-0.5)
                .foregroundColor(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            Color.white.opacity(0.05)
                .cornerRadius(14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - 헬퍼 함수

/// 거리를 포맷팅 (m 또는 km)
private func formatDistance(_ meters: Double) -> String {
    if meters >= 1000 {
        return String(format: "%.1fkm", meters / 1000)
    } else {
        return "\(Int(meters))m"
    }
}
