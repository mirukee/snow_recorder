import SwiftUI
import PhotosUI
import SwiftData

struct SharePreviewView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var storeManager: StoreManager
    let session: RunSession
    
    // MARK: - State
    @State private var selectedItem: PhotosPickerItem?
    @State private var backgroundUIImage: UIImage?
    @State private var selectedLayout: ShareLayout = .standard
    @State private var showShareSheet = false
    @State private var imageToShare: UIImage?
    @State private var showSaveToast = false
    @State private var showPaywall = false
    
    // Image Transform
    @GestureState private var pinchScale: CGFloat = 1.0
    @State private var steadyScale: CGFloat = 1.0
    @GestureState private var panOffset: CGSize = .zero
    @State private var steadyOffset: CGSize = .zero
    
    var currentScale: CGFloat { steadyScale * pinchScale }
    var currentOffset: CGSize {
        CGSize(
            width: steadyOffset.width + panOffset.width,
            height: steadyOffset.height + panOffset.height
        )
    }
    
    let primaryColor = Color(red: 107/255, green: 249/255, blue: 6/255)
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                // Image with gestures
                if let uiImage = backgroundUIImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(currentScale)
                        .offset(currentOffset)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .ignoresSafeArea()
                        .gesture(
                            MagnificationGesture()
                                .updating($pinchScale) { value, state, _ in
                                    state = value
                                }
                                .onEnded { value in
                                    steadyScale = min(max(steadyScale * value, 1.0), 3.0)
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .updating($panOffset) { value, state, _ in
                                    state = value.translation
                                }
                                .onEnded { value in
                                    steadyOffset = CGSize(
                                        width: steadyOffset.width + value.translation.width,
                                        height: steadyOffset.height + value.translation.height
                                    )
                                }
                        )
                } else {
                    LinearGradient(
                        colors: [Color(white: 0.15), Color.black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                }
                
                // Gradient overlay
                LinearGradient(
                    colors: [
                        .black.opacity(0.6), // Darker top
                        .clear,
                        .clear, // Push gradient down
                        .black.opacity(0.9)  // Darker bottom
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
                
                // Stats
                VStack {
                    Spacer()
                    previewStatsView
                        .padding(.horizontal, 20)
                        .padding(.bottom, 180) // Increased padding to clear Layout Selector
                }
                .allowsHitTesting(false)
                
                // Pro 템플릿 잠금 오버레이
                if selectedLayout.isPro && !storeManager.isPro {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .overlay(
                            VStack(spacing: 10) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(.yellow)
                                Text("PRO TEMPLATE")
                                    .font(.system(size: 14, weight: .bold))
                                    .tracking(2)
                                    .foregroundColor(.white)
                                Text("share.locked_share_hint")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.gray)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                        )
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
                
                // Brand Watermark (설정 기반)
                if selectedLayout.getWatermarkConfig().show {
                    watermarkOverlay(config: selectedLayout.getWatermarkConfig(), scaled: false)
                        .allowsHitTesting(false)
                }
                
                // Save Toast
                if showSaveToast {
                    VStack {
                        Spacer()
                        Text("share.save_complete")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(25)
                            .padding(.bottom, 180)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Controls
                VStack {
                    HStack {
                        Button(action: { dismiss() }) {
                            ZStack {
                                Circle().fill(Color.white).frame(width: 44, height: 44)
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.black)
                            }
                            .shadow(radius: 4)
                        }
                        
                        Spacer()
                        
                        Text("PREVIEW")
                            .font(.system(size: 14, weight: .bold))
                            .tracking(2)
                            .foregroundColor(.white)
                            .shadow(radius: 4)
                        
                        Spacer()
                        
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            ZStack {
                                Circle().fill(Color.white).frame(width: 44, height: 44)
                                Image(systemName: "photo")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.black)
                            }
                            .shadow(radius: 4)
                        }
                        .disabled(selectedLayout.isPro && !storeManager.isPro)
                        .opacity(selectedLayout.isPro && !storeManager.isPro ? 0.4 : 1.0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 60)
                    
                    if backgroundUIImage != nil {
                        Text("share.photo_adjust_hint")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.top, 8)
                    }
                    
                    Spacer()
                    
                    layoutSelector
                    
                    HStack(spacing: 16) {
                        if selectedLayout.isPro && !storeManager.isPro {
                            Button(action: { showPaywall = true }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "lock.fill")
                                    Text("UNLOCK PRO")
                                }
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.vertical, 16)
                                .padding(.horizontal, 24)
                                .background(primaryColor)
                                .clipShape(Capsule())
                            }
                        } else {
                            Button(action: shareToStory) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.up.circle.fill")
                                    Text("SHARE TO STORY")
                                }
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.vertical, 16)
                                .padding(.horizontal, 24)
                                .background(primaryColor)
                                .clipShape(Capsule())
                            }
                        }
                        
                        Button(action: saveToPhotos) {
                            ZStack {
                                Circle()
                                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
                                    .background(Circle().fill(Color.black.opacity(0.3)))
                                    .frame(width: 56, height: 56)
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .disabled(selectedLayout.isPro && !storeManager.isPro)
                        .opacity(selectedLayout.isPro && !storeManager.isPro ? 0.4 : 1.0)
                    }
                    .padding(.bottom, 50)
                }
            }
        }
        .onChange(of: selectedItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    backgroundUIImage = uiImage
                    steadyScale = 1.0
                    steadyOffset = .zero
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = imageToShare {
                ShareSheet(activityItems: [image])
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
    
    // MARK: - Enums
    
    /// 워터마크 위치 설정
    enum WatermarkPosition {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
        case custom(x: CGFloat, y: CGFloat) // 0.0 ~ 1.0 비율
    }
    
    /// 워터마크 설정 구조체 - 레이아웃별로 이 값을 수정하세요
    struct WatermarkConfig {
        let show: Bool              // 공통 워터마크 표시 여부
        let position: WatermarkPosition
        let opacity: CGFloat        // 0.0 ~ 1.0
        
        static let hidden = WatermarkConfig(show: false, position: .topLeft, opacity: 0)
        static let defaultConfig = WatermarkConfig(show: true, position: .topLeft, opacity: 1.0)
    }
    
    enum ShareLayout: String, CaseIterable, Identifiable {
        case standard = "Standard"
        case frostGlass = "Frost Glass"
        case photo = "Photo"
        case minimal = "Minimal"
        case speedDemon = "Speed Demon"
        case explorer = "Explorer"
        case techSpec = "Tech-Spec"
        case cover = "The Cover"
        case rewind = "Rewind"
        
        var id: String { self.rawValue }
        
        var displayName: LocalizedStringKey {
            switch self {
            case .standard: return "share.layout.standard"
            case .photo: return "share.layout.photo"
            case .minimal: return "share.layout.minimal"
            case .speedDemon: return "share.layout.speed_demon"
            case .explorer: return "share.layout.explorer"
            case .techSpec: return "share.layout.tech_spec"
            case .cover: return "share.layout.cover"
            case .rewind: return "share.layout.rewind"
            case .frostGlass: return "share.layout.frost_glass"
            }
        }
        
        var iconName: String {
            switch self {
            case .standard: return "rectangle.grid.1x2.fill"
            case .photo: return "photo.fill"
            case .minimal: return "list.bullet.below.rectangle"
            case .speedDemon: return "bolt.fill"
            case .explorer: return "map.fill"
            case .techSpec: return "viewfinder"
            case .cover: return "magazine.fill"
            case .rewind: return "video.fill"
            case .frostGlass: return "square.on.square.fill"
            }
        }
        
        var isPro: Bool {
            switch self {
            case .standard, .frostGlass:
                return false
            case .photo, .minimal, .speedDemon, .explorer, .techSpec, .cover, .rewind:
                return true
            }
        }
        
        // MARK: - 워터마크 설정 (여기서 레이아웃별로 조절하세요!)
        // MARK: - 워터마크 설정 (여기서 레이아웃별로 조절하세요!)
        func getWatermarkConfig() -> WatermarkConfig {
            switch self {
            // ✅ 공통 워터마크 표시
            case .standard:
                return WatermarkConfig(show: true, position: .topLeft, opacity: 1.0)
            case .photo:
                return WatermarkConfig(show: true, position: .topLeft, opacity: 1.0)
            case .minimal:
                return .hidden
            case .speedDemon:
                return WatermarkConfig(show: true, position: .custom(x: 0.25, y: 0.70), opacity: 1.0)
                
            // ❌ 자체 브랜딩 사용 (공통 워터마크 숨김)
            case .explorer:
                return .hidden
            case .techSpec:
                return .hidden
            case .cover:
                return .hidden
            case .rewind:
                return .hidden
            case .frostGlass:
                return .hidden
            }
        }
    }
    
    // MARK: - Layout Selector
    var layoutSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(ShareLayout.allCases) { layout in
                    let locked = layout.isPro && !storeManager.isPro
                    Button(action: {
                        withAnimation(.spring()) {
                            selectedLayout = layout
                        }
                    }) {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(selectedLayout == layout ? primaryColor : Color.white.opacity(0.1))
                                    .frame(width: 50, height: 50)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                                
                                Image(systemName: layout.iconName)
                                    .font(.system(size: 20))
                                    .foregroundColor(selectedLayout == layout ? .black : .white)
                                
                                if locked {
                                    Circle()
                                        .fill(Color.black.opacity(0.45))
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.yellow)
                                }
                            }
                            
                            Text(layout.displayName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(selectedLayout == layout ? primaryColor : .white.opacity(0.7))
                            
                            if layout.isPro {
                                Text("PRO")
                                    .font(.system(size: 9, weight: .bold))
                                    .tracking(1)
                                    .foregroundColor(locked ? .yellow : primaryColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background((locked ? Color.yellow.opacity(0.12) : primaryColor.opacity(0.15)))
                                    .cornerRadius(6)
                            }
                        }
                        .frame(width: 70) // Fixed width for consistency
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 20)
        .background(
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
        )
    }
    
    // MARK: - Brand Watermark
    var brandView: some View {
        HStack(spacing: 8) {
            Image(systemName: "snowflake")
                .font(.system(size: 22))
                .foregroundColor(primaryColor)
            Text("SNOW RECORD")
                .font(.system(size: 18, weight: .black))
                .italic()
                .foregroundColor(.white)
        }
        .padding(10)
        .background(Color.black.opacity(0.5))
        .cornerRadius(4)
    }
    
    /// 위치 기반 워터마크 오버레이 (Preview/Export 공용)
    /// 위치 기반 워터마크 오버레이 (Preview/Export 공용)
    // @ViewBuilder removed to avoid return issues
    func watermarkOverlay(config: WatermarkConfig, scaled: Bool) -> some View {
        let s: CGFloat = scaled ? 3.0 : 1.0
        let hPadding: CGFloat = scaled ? 60 : 20
        let topPadding: CGFloat = scaled ? 100 : 120
        let bottomPadding: CGFloat = scaled ? 100 : 50
        
        let watermark = HStack(spacing: 8 * s) {
            Image(systemName: "snowflake")
                .font(.system(size: 22 * s))
                .foregroundColor(primaryColor)
            Text("SNOW RECORD")
                .font(.system(size: 18 * s, weight: .black))
                .italic()
                .foregroundColor(.white)
        }
        .padding(10 * s)
        .background(Color.black.opacity(0.5))
        .cornerRadius(4 * s)
        .opacity(config.opacity)
        
        switch config.position {
        case .topLeft:
            return AnyView(
                VStack {
                    HStack { watermark; Spacer() }
                        .padding(.horizontal, hPadding)
                        .padding(.top, topPadding)
                    Spacer()
                }
            )
        case .topRight:
            return AnyView(
                VStack {
                    HStack { Spacer(); watermark }
                        .padding(.horizontal, hPadding)
                        .padding(.top, topPadding)
                    Spacer()
                }
            )
        case .bottomLeft:
            return AnyView(
                VStack {
                    Spacer()
                    HStack { watermark; Spacer() }
                        .padding(.horizontal, hPadding)
                        .padding(.bottom, bottomPadding)
                }
            )
        case .bottomRight:
            return AnyView(
                VStack {
                    Spacer()
                    HStack { Spacer(); watermark }
                        .padding(.horizontal, hPadding)
                        .padding(.bottom, bottomPadding)
                }
            )
        case .custom(let x, let y):
            return AnyView(
                GeometryReader { geo in
                    watermark
                        .position(x: geo.size.width * x, y: geo.size.height * y)
                }
            )
        }
    }
    
    // MARK: - Preview Stats (small, for screen)
    @ViewBuilder
    var previewStatsView: some View {
        switch selectedLayout {
        case .standard:
            previewStatsStandard
        case .photo:
            previewStatsPhoto
        case .minimal:
            previewStatsMinimal
        case .speedDemon:
            previewStatsSpeedDemon
        case .explorer:
            previewStatsExplorer
        case .techSpec:
            previewStatsTechSpec
        case .cover:
            previewStatsCover
        case .rewind:
            previewStatsRewind
        case .frostGlass:
            previewStatsFrostGlass
        }
    }
    
    // [Frost Glass Layout] - Modern Luxury
    var previewStatsFrostGlass: some View {
        VStack {
            Spacer()
            
            // Glass Card centered
            VStack(spacing: 0) {
                // Branding
                HStack(spacing: 6) {
                    Image(systemName: "snowflake")
                        .font(.system(size: 22))
                        .foregroundColor(primaryColor)
                    Text("SNOW RECORD")
                        .font(.system(size: 10, weight: .bold))
                        .textCase(.uppercase)
                         .tracking(2)
                        .foregroundColor(.white)
                }
                .opacity(0.9)
                .padding(.bottom, 20)
                
                // Main Metric
                Text(String(format: "%.1f", session.distance / 1000.0))
                    .font(.system(size: 72, weight: .light))
                    .foregroundColor(.white)
                    .tracking(-2)
                    .padding(.bottom, 4)
                
                Text("KILOMETERS")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.bottom, 30)
                
                // Sparkline Graph (Mock or actual Data)
                // Using a Shape to draw a smooth curve
                FrostSparkline()
                    .stroke(
                        LinearGradient(colors: [primaryColor, Color.blue], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
                    .frame(height: 60)
                    .background(
                        FrostSparkline()
                            .fill(LinearGradient(colors: [primaryColor.opacity(0.2), Color.blue.opacity(0)], startPoint: .top, endPoint: .bottom))
                    )
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                
                // Axis Labels
                HStack {
                    Text("START").font(.system(size: 9, weight: .bold)).foregroundColor(.white.opacity(0.3))
                    Spacer()
                    Text("SPEED").font(.system(size: 9, weight: .bold)).foregroundColor(.white.opacity(0.3))
                    Spacer()
                    Text("END").font(.system(size: 9, weight: .bold)).foregroundColor(.white.opacity(0.3))
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
                
                // Bottom Stats
                HStack {
                    VStack(spacing: 4) {
                        Text("\(session.runCount)")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white)
                        Text("RUNS")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(2)
                            .foregroundColor(.white.opacity(0.5))
                            .textCase(.uppercase)
                    }
                    
                    Spacer()
                    
                    Rectangle()
                         .fill(LinearGradient(colors: [.clear, .white.opacity(0.2), .clear], startPoint: .top, endPoint: .bottom))
                        .frame(width: 1, height: 40)
                    
                    Spacer()
                    
                    VStack(spacing: 4) {
                        Text("\(Int(session.verticalDrop))")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white)
                        Text("VERTICAL M")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(2)
                            .foregroundColor(.white.opacity(0.5))
                            .textCase(.uppercase)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(30)
            .background(.thinMaterial) // Frost effect
            .background(Color.white.opacity(0.05))
            .cornerRadius(40)
            .overlay(
                RoundedRectangle(cornerRadius: 40)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 40) // Adjust for consistent placement
            
            Spacer()
        }
    }
    
    // Simple mock sparkline shape
    struct FrostSparkline: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: rect.height * 0.8))
            // Bezier curve mock
            path.addCurve(to: CGPoint(x: rect.width * 0.4, y: rect.height * 0.5), control1: CGPoint(x: rect.width * 0.1, y: rect.height * 0.8), control2: CGPoint(x: rect.width * 0.2, y: rect.height * 0.6))
             path.addCurve(to: CGPoint(x: rect.width * 0.7, y: rect.height * 0.3), control1: CGPoint(x: rect.width * 0.5, y: rect.height * 0.4), control2: CGPoint(x: rect.width * 0.6, y: rect.height * 0.8))
             path.addCurve(to: CGPoint(x: rect.width, y: rect.height * 0.1), control1: CGPoint(x: rect.width * 0.8, y: rect.height * 0.0), control2: CGPoint(x: rect.width * 0.9, y: rect.height * 0.2))
            return path
        }
    }
    
    // [Rewind Layout] - Retro VHS
    var previewStatsRewind: some View {
        ZStack {
            // Scanlines Overlay
            VStack(spacing: 0) {
                ForEach(0..<100) { _ in
                    Rectangle()
                        .fill(Color.black.opacity(0.1))
                        .frame(height: 2)
                    Spacer().frame(height: 2)
                }
            }
            .drawingGroup() // Performance
            .ignoresSafeArea()
            .allowsHitTesting(false)
            
            VStack {
                // Top Bar: REC & SP MODE
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("REC")
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .shadow(color: .red.opacity(0.8), radius: 2)
                            .overlay(
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 10, height: 10)
                                    .offset(x: -16)
                                    .opacity(Int(Date().timeIntervalSince1970) % 2 == 0 ? 1.0 : 0.3) // Blinking-ish
                                    // Note: Real blinking needs State/Timer, for static view just solid or keyframe
                            , alignment: .leading)
                            .padding(.leading, 16)
                        
                         Text("SP MODE")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.leading, 16)
                    }
                    Spacer()
                }
                .padding(.top, 40)
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Central Stats (Pixel look)
                VStack(spacing: 12) {
                    // Distance
                    VStack(spacing: 0) {
                        Text(String(format: "%.1f", session.distance / 1000.0))
                            .font(.system(size: 100, weight: .bold, design: .monospaced)) // Closest to VCR
                            .foregroundColor(Color(red: 1, green: 1, blue: 0)) // Cyan-Yellow
                            .shadow(color: .red, radius: 0, x: 2, y: 1) // RGB Split
                            .shadow(color: .cyan, radius: 0, x: -2, y: -1)
                        
                        Text("KM TRAVELED")
                            .font(.system(size: 32, weight: .black, design: .monospaced))
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 0)
                            .background(Color.black.opacity(0.4))
                            .shadow(color: .red, radius: 0, x: 2, y: 0)
                    }
                    
                    Spacer().frame(height: 20)
                    
                    // List
                    VStack(spacing: 8) {
                        HStack {
                            Text("RUNS")
                                .font(.system(size: 20, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.9))
                            Spacer()
                            Text("\(session.runCount)")
                                .font(.system(size: 24, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(red: 1, green: 1, blue: 0))
                        }
                        .padding(.bottom, 4)
                        .overlay(Rectangle().fill(Color.white.opacity(0.3)).frame(height: 1), alignment: .bottom)
                        
                        HStack {
                            Text("VERTICAL")
                                .font(.system(size: 20, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.9))
                            Spacer()
                            Text("\(Int(session.verticalDrop)) M")
                                .font(.system(size: 24, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(red: 1, green: 1, blue: 0))
                        }
                        .padding(.bottom, 4)
                        .overlay(Rectangle().fill(Color.white.opacity(0.3)).frame(height: 1), alignment: .bottom)
                    }
                    .frame(width: 280)
                }
                .offset(y: -40)
                
                Spacer()
                
                // Bottom Date Stamp
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading) {
                        Text(session.startTime.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)).replacingOccurrences(of: "/", with: " ")) // 2024 01 30
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 1)
                        Text(session.startTime.formatted(.dateTime.hour().minute().second()))
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    Spacer()
                    
                    Text("SNOW RECORD")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                        .padding(.bottom, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 140)
            }
        }
    }
    
    // [The Cover Layout] - Magazine Style
    var previewStatsCover: some View {
        ZStack {
            // Top Date Tag
            VStack {
                Text("\(session.startTime.formatted(.dateTime.month(.abbreviated).day())) • VOL. 09")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.6).blur(radius: 2))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.top, 40)
                
                // Massive Headlines
                VStack(spacing: 8) {
                    Text("SNOW RECORD")
                        .font(.system(size: 48, weight: .black))
                        .italic()
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.6), radius: 5, x: 0, y: 4)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    
                    ZStack {
                        // Shadow/Glow Background
                        Text("POWDER\nDAY")
                            .font(.system(size: 90, weight: .black)) // Slightly smaller to fit phone
                            .italic()
                            .multilineTextAlignment(.center)
                            .lineSpacing(-20) // Tight leading
                            .foregroundColor(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.5), radius: 10)
                            .minimumScaleFactor(0.5)
                        
                        // Stroke Effect (Front)
                         Text("POWDER\nDAY")
                            .font(.system(size: 90, weight: .black))
                            .italic()
                            .multilineTextAlignment(.center)
                            .lineSpacing(-20)
                            .foregroundColor(.clear)
                            .overlay(
                                Text("POWDER\nDAY")
                                    .font(.system(size: 90, weight: .black))
                                    .italic()
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(-20)
                                    .foregroundColor(.white.opacity(0.3))
                                    .minimumScaleFactor(0.5)
                            )
                            .minimumScaleFactor(0.5)
                            // Simulate stroke via shadow if needed, but opacity overlay works for "Ghost" effect
                    }
                }
                .padding(.top, 20)
                
                Spacer()
                
                // Bottom Ticket Sticker (Rotated)
                HStack {
                    Spacer()
                    
                    ZStack(alignment: .topTrailing) {
                        // Pin / Dot
                        Circle()
                            .fill(primaryColor)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1))
                            .offset(x: 4, y: -4)
                            .zIndex(10)
                        
                        VStack(spacing: 0) {
                            // stats
                            VStack(spacing: 8) {
                                HStack(alignment: .lastTextBaseline) {
                                    Text("DIST")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundColor(.black)
                                    Spacer()
                                    HStack(alignment: .top, spacing: 1) {
                                        Text(String(format: "%.1f", session.distance / 1000.0))
                                            .font(.system(size: 24, weight: .black))
                                            .italic()
                                            .foregroundColor(.black)
                                        Text("KM")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(.black)
                                            .offset(y: 4)
                                    }
                                }
                                .padding(.bottom, 4)
                                .overlay(Rectangle().fill(Color.black).frame(height: 2), alignment: .bottom)
                                
                                HStack(alignment: .lastTextBaseline) {
                                    Text("MAX")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundColor(.black)
                                    Spacer()
                                    Text(String(format: "%.1f", session.maxSpeed))
                                        .font(.system(size: 24, weight: .black))
                                        .italic()
                                        .foregroundColor(.black)
                                }
                            }
                            .padding(12)
                            .padding(.bottom, 4)
                            
                            // Barcode Visual
                            HStack(alignment: .bottom, spacing: 2) {
                                ForEach(0..<15) { i in
                                    Rectangle()
                                        .fill(Color.black.opacity(0.9))
                                        .frame(width: CGFloat([2, 1, 4, 1, 3, 1, 2, 5, 2, 1, 3, 1, 4, 2, 3][i]), height: CGFloat([20, 15, 24, 12, 22, 18, 24, 20, 16, 24, 20, 14, 22, 18, 24][i]))
                                }
                            }
                            .frame(height: 24)
                            .padding(.bottom, 8)
                            
                            // Footer Codes
                            HStack {
                                Text("USER-01")
                                Text("#SNOWREC")
                            }
                            .font(.system(size: 6, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.bottom, 8)
                        }
                        .frame(width: 140)
                        .background(Color.white)
                        .border(Color.black, width: 2)
                        .shadow(color: .black.opacity(0.4), radius: 10, x: 5, y: 10)
                        .rotationEffect(.degrees(-6))
                    }
                    .padding(.bottom, 120) // Space for button
                    .padding(.trailing, 20)
                }
            }
        }
    }
    
    // [Tech-Spec Layout] - Futuristic HUD
    var previewStatsTechSpec: some View {
        ZStack {
            // 1. Grid & Overlay (Background Layer)
            // Ideally we would add a grid pattern here, but for simplicity we rely on the clean overlay.
            // Corner Brackets
            VStack {
                HStack {
                    cornerBracket(topLeft: true)
                    Spacer()
                    cornerBracket(topLeft: false, topRight: true)
                }
                Spacer()
                HStack {
                    cornerBracket(bottomLeft: true)
                    Spacer()
                    cornerBracket(bottomLeft: false, bottomRight: true)
                }
            }
            .padding(20)
            
            VStack {
                // Top Bar
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: "snowflake")
                                .foregroundColor(primaryColor)
                                .font(.system(size: 14))
                            Text("SNOW RECORD")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .tracking(2)
                                .foregroundColor(.white)
                        }
                        Text("SYSTEM ONLINE // V.2.4")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(primaryColor.opacity(0.8))
                            .tracking(1)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                                .shadow(color: .red, radius: 4)
                            Text("REC: ACTIVE")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .tracking(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.6))
                        .border(primaryColor.opacity(0.5), width: 0.5)
                        
                        Text("T-MINUS 00:42:12")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(primaryColor.opacity(0.6))
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 40)
                
                Spacer()
                
                // Central HUD
                ZStack {
                    // Crosshairs
                    Rectangle()
                        .fill(primaryColor.opacity(0.3))
                        .frame(width: 1, height: 300)
                    Rectangle()
                        .fill(primaryColor.opacity(0.3))
                        .frame(width: 300, height: 1)
                    
                    // Circles
                    Circle()
                        .stroke(primaryColor.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .frame(width: 260, height: 260)
                     Circle()
                        .stroke(primaryColor, lineWidth: 1)
                        .frame(width: 220, height: 220)
                        
                    // Data
                    VStack(spacing: 4) {
                        Text("SPEED")
                            .font(.system(size: 10, design: .monospaced))
                            .tracking(4)
                            .foregroundColor(primaryColor.opacity(0.7))
                            .padding(.bottom, 4)
                        
                        Text(String(format: "%.1f", session.maxSpeed))
                            .font(.system(size: 64, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .shadow(color: primaryColor.opacity(0.6), radius: 10)
                        
                        Text("KM/H")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(primaryColor)
                        
                        Rectangle()
                            .fill(primaryColor.opacity(0.5))
                            .frame(width: 140, height: 1)
                            .padding(.vertical, 8)
                        
                        VStack(spacing: 0) {
                            Text(String(format: "%.1f", session.maxGForce > 0 ? session.maxGForce : 1.2)) // Mock G if 0
                                .font(.system(size: 24, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                            Text("G-FORCE")
                                .font(.system(size: 8, design: .monospaced))
                                .tracking(2)
                                .foregroundColor(primaryColor.opacity(0.6))
                        }
                    }
                    .background(Color.black.opacity(0.4).blur(radius: 20)) // Legibility
                }
                .offset(y: -40)
                
                Spacer()
                
                // Bottom Status
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ALTITUDE")
                            .font(.system(size: 10, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(primaryColor.opacity(0.6))
                        
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("3,100") // Mock or session.maxAltitude if available, currently using mockup value
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                            Text("M")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(primaryColor)
                        }
                        
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8))
                            Text("LOCKED")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(primaryColor)
                        .padding(4)
                        .background(primaryColor.opacity(0.1))
                        .cornerRadius(2)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("ENV. STATUS")
                            .font(.system(size: 10, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(primaryColor.opacity(0.6))
                        
                        Text("POWDER")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .tracking(2)
                        
                        Text("-12°C // WIND 15KT")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(primaryColor.opacity(0.8))
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 140) // Space for Share Button
            }
        }
    }
    
    // Helper: Corner Bracket
    func cornerBracket(topLeft: Bool = false, topRight: Bool = false, bottomLeft: Bool = false, bottomRight: Bool = false) -> some View {
        let size: CGFloat = 20
        let thickness: CGFloat = 2
        return ZStack {
             if topLeft {
                VStack(spacing: 0) {
                    Rectangle().frame(width: size, height: thickness)
                    HStack { Rectangle().frame(width: thickness, height: size); Spacer() }
                }
            } else if topRight {
                VStack(spacing: 0) {
                    Rectangle().frame(width: size, height: thickness)
                    HStack { Spacer(); Rectangle().frame(width: thickness, height: size) }
                }
            } else if bottomLeft {
                VStack(spacing: 0) {
                    HStack { Rectangle().frame(width: thickness, height: size); Spacer() }
                    Rectangle().frame(width: size, height: thickness)
                }
            } else if bottomRight {
                VStack(spacing: 0) {
                     HStack { Spacer(); Rectangle().frame(width: thickness, height: size) }
                    Rectangle().frame(width: size, height: thickness)
                }
            }
        }
        .foregroundColor(primaryColor.opacity(0.8))
        .frame(width: size, height: size)
    }
    
    // [Explorer Layout] - Outlined Distance Text
    var previewStatsExplorer: some View {
        VStack {
            Spacer()
            
            // Brand Top Left (Custom for Explorer)
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "snowflake")
                        .font(.system(size: 24))
                        .foregroundColor(primaryColor)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                    Text("SNOW RECORD")
                        .font(.system(size: 20, weight: .black))
                        .italic()
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            
            Spacer()
            
            // Main Stat: Distance (Stroked Text Effect)
            VStack(spacing: 0) {
                let distText = String(format: "%.1f", session.distance / 1000.0)
                ZStack {
                    // 1. Solid Shadow (Offset)
                    Text(distText)
                        .font(.system(size: 100, weight: .black))
                        .italic()
                        .foregroundColor(primaryColor)
                        .offset(x: 4, y: 4)
                        .opacity(0.8)
                    
                    // 2. Main Text (White)
                    Text(distText)
                        .font(.system(size: 100, weight: .black))
                        .italic()
                        .foregroundColor(.white)
                }
                
                Text("KILOMETERS")
                    .font(.system(size: 24, weight: .heavy))
                    .italic()
                    .foregroundColor(.white)
                    .padding(.leading, 10)
            }
            .padding(.leading, 20)
            .padding(.bottom, 40)

            
            // Sub Stats: Runs | Vertical
            HStack(spacing: 40) {
                // Runs
                VStack(spacing: 2) {
                    Text("\(session.runCount)")
                        .font(.system(size: 24, weight: .black))
                        .italic()
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                    Text("RUNS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(primaryColor)
                        .tracking(2)
                }
                
                // Divider
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 2, height: 24)
                    .rotationEffect(.degrees(12))
                
                // Vertical
                VStack(spacing: 2) {
                    Text("\(Int(session.verticalDrop)) M")
                        .font(.system(size: 24, weight: .black))
                        .italic()
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                    Text("VERTICAL")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(primaryColor)
                        .tracking(2)
                }
            }
            .padding(.bottom, 120) // Space for button
        }
    }
    
    // [Speed Demon Layout] - Massive Center Speed
    var previewStatsSpeedDemon: some View {
        VStack {
            Spacer()
            
            // Hero Metric (Center)
            VStack(spacing: 0) {
                // Label Chip
                HStack(spacing: 4) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 10, weight: .bold))
                    Text("MAX SPEED")
                        .font(.system(size: 10, weight: .black))
                        .tracking(1)
                }
                .foregroundColor(primaryColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(primaryColor.opacity(0.1))
                .overlay(
                    Capsule().stroke(primaryColor.opacity(0.3), lineWidth: 1)
                )
                .clipShape(Capsule())
                .padding(.bottom, 4)
                
                // Value
                Text(String(format: "%.1f", session.maxSpeed))
                    .font(.system(size: 100, weight: .black))
                    .italic()
                    .foregroundColor(primaryColor)
                    .shadow(color: primaryColor.opacity(0.5), radius: 20)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                
                // Unit
                Text("KM/H")
                    .font(.system(size: 24, weight: .bold))
                    .italic() // font-speed
                    .tracking(4) // tracking-widest
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.top, -10)
            }
            
            Spacer()
                .frame(height: 50)
            
            // Secondary Stats Glass Panel
            HStack(spacing: 0) {
                // Runs
                VStack(spacing: 2) {
                    Image(systemName: "figure.skiing.downhill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                    
                    Text("\(session.runCount)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("RUNS")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.6))
                        .textCase(.uppercase)
                }
                .frame(maxWidth: .infinity)
                
                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 1, height: 40)
                
                // Distance
                VStack(spacing: 2) {
                    Image(systemName: "map")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                    
                    Text(String(format: "%.1f", session.distance / 1000.0))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("KM DIST")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.6))
                        .textCase(.uppercase)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 20)
            .background(Color(red: 23/255, green: 35/255, blue: 15/255).opacity(0.6)) // #17230f 60%
            .background(.thinMaterial)
            .cornerRadius(24)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 40)
            
            Spacer()
        }
    }
    
    // [Standard Layout] - Original design
    var previewStatsStandard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Runs
            Text("\(session.runCount) RUNS")
                .font(.system(size: 12, weight: .black))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white)
                .foregroundColor(.black)
                .rotationEffect(.degrees(2))
                .padding(.bottom, 8)
            
            // Distance
            VStack(alignment: .leading, spacing: 0) {
                Text("TOTAL DISTANCE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.7))
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", session.distance / 1000.0))
                        .font(.system(size: 72, weight: .black))
                        .foregroundColor(primaryColor)
                        .shadow(color: primaryColor.opacity(0.5), radius: 8)
                    Text("KM")
                        .font(.system(size: 28, weight: .black))
                        .italic()
                        .foregroundColor(.white)
                }
            }
            .padding(.bottom, 12)
            
            // Speed
            VStack(alignment: .leading, spacing: 2) {
                Text("TOP VELOCITY")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                Text("MAX SPEED \(String(format: "%.1f", session.maxSpeed)) KM/H")
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(.white)
            }
            .padding(10)
            .background(Color.black.opacity(0.5))
            .cornerRadius(4)
            .padding(.bottom, 20)
            
            // Divider
            Rectangle().fill(Color.white.opacity(0.3)).frame(height: 1).padding(.bottom, 16)
            
            // Footer
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("KOREA").font(.system(size: 28, weight: .bold)).foregroundColor(.white)
                    Text(session.locationName).font(.system(size: 16)).foregroundColor(.white.opacity(0.7))
                    HStack(spacing: 4) {
                        Image(systemName: "calendar").font(.system(size: 12)).foregroundColor(primaryColor)
                        Text(session.startTime.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(primaryColor)
                    }
                    .padding(.top, 4)
                }
                Spacer()
                decoBar(height: 32)
            }
        }
    }
    
    // [Photo Layout] - Bottom focused, clear center
    var previewStatsPhoto: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(session.runCount) RUNS")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundColor(primaryColor)
                    
                    Text(String(format: "%.1f KM", session.distance / 1000.0))
                        .font(.system(size: 36, weight: .black))
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 2)
                    
                    Text(session.locationName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .shadow(color: .black, radius: 2)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 0) {
                     Text("MAX SPEED")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                    Text("\(String(format: "%.0f", session.maxSpeed))")
                        .font(.system(size: 48, weight: .black)) // Space Grotesk
                        .italic()
                        .foregroundColor(.white)
                        .shadow(color: primaryColor.opacity(0.5), radius: 10)
                    Text("KM/H")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(primaryColor)
                }
            }
            .padding(20)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
            )
        }
    }
    
    // [Minimal Layout] - Clean side stack
    var previewStatsMinimal: some View {
        HStack {
            VStack(alignment: .leading, spacing: 16) {
                Rectangle()
                    .fill(primaryColor)
                    .frame(width: 40, height: 4)
                
                VStack(alignment: .leading, spacing: 0) {
                    Text("DISTANCE")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.6))
                    Text(String(format: "%.1f KM", session.distance / 1000.0))
                        .font(.system(size: 32, weight: .light)) // Thin font
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    Text("RUNS")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.6))
                    Text("\(session.runCount)")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    Text("MAX SPEED")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.6))
                    Text("\(Int(session.maxSpeed))")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(.white)
                    + Text(" KM/H").font(.system(size: 12)).foregroundColor(.gray)
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.locationName.uppercased())
                        .font(.system(size: 14, weight: .bold))
                        .tracking(1)
                        .foregroundColor(.white)
                    Text(session.startTime.formatted(date: .numeric, time: .omitted))
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 20)
            .background(Color.black.opacity(0.4).blur(radius: 10))
            .cornerRadius(0)
            
            Spacer()
        }
    }
    
    // Shared Deco Bar
    func decoBar(height: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: 2) {
            Rectangle().fill(Color.white).frame(width: 3, height: height)
            Rectangle().fill(Color.white).frame(width: 2, height: height * 0.6)
            Rectangle().fill(Color.white).frame(width: 5, height: height * 0.9)
            Rectangle().fill(Color.white).frame(width: 2, height: height * 0.4)
            Rectangle().fill(Color.white).frame(width: 6, height: height)
            Rectangle().fill(Color.white).frame(width: 2, height: height * 0.5)
            Rectangle().fill(primaryColor).frame(width: 3, height: height)
        }
    }
    
    // MARK: - Export Stats (large, for 1080x1920)
    @ViewBuilder
    func exportStatsView() -> some View {
        switch selectedLayout {
        case .standard:
            exportStatsStandard()
        case .photo:
            exportStatsPhoto()
        case .minimal:
            exportStatsMinimal()
        case .speedDemon:
            exportStatsSpeedDemon()
        case .explorer:
            exportStatsExplorer()
        case .techSpec:
            exportStatsTechSpec()
        case .cover:
            exportStatsCover()
        case .rewind:
            exportStatsRewind()
        case .frostGlass:
            exportStatsFrostGlass()
        }
    }
    
    // Frost Glass Export (Scaled x3)
    func exportStatsFrostGlass() -> some View {
        let s: CGFloat = 3.0
        return VStack {
            Spacer()
            
            // Glass Card centered
            VStack(spacing: 0) {
                // Branding
                HStack(spacing: 6 * s) {
                    Image(systemName: "snowflake")
                        .font(.system(size: 22 * s))
                        .foregroundColor(primaryColor)
                    Text("SNOW RECORD")
                        .font(.system(size: 10 * s, weight: .bold))
                        .textCase(.uppercase)
                         .tracking(2 * s)
                        .foregroundColor(.white)
                }
                .opacity(0.9)
                .padding(.bottom, 20 * s)
                
                // Main Metric
                Text(String(format: "%.1f", session.distance / 1000.0))
                    .font(.system(size: 72 * s, weight: .light))
                    .foregroundColor(.white)
                    .tracking(-2 * s)
                    .padding(.bottom, 4 * s)
                
                Text("KILOMETERS")
                    .font(.system(size: 12 * s, weight: .semibold))
                    .tracking(2 * s)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.bottom, 30 * s)
                
                // Sparkline Graph
                FrostSparkline()
                    .stroke(
                        LinearGradient(colors: [primaryColor, Color.blue], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 3 * s, lineCap: .round, lineJoin: .round)
                    )
                    .frame(height: 60 * s)
                    .background(
                        FrostSparkline()
                            .fill(LinearGradient(colors: [primaryColor.opacity(0.2), Color.blue.opacity(0)], startPoint: .top, endPoint: .bottom))
                    )
                    .padding(.horizontal, 10 * s)
                    .padding(.bottom, 8 * s)
                
                // Axis Labels
                HStack {
                    Text("START").font(.system(size: 9 * s, weight: .bold)).foregroundColor(.white.opacity(0.3))
                    Spacer()
                    Text("SPEED").font(.system(size: 9 * s, weight: .bold)).foregroundColor(.white.opacity(0.3))
                    Spacer()
                    Text("END").font(.system(size: 9 * s, weight: .bold)).foregroundColor(.white.opacity(0.3))
                }
                .padding(.horizontal, 12 * s)
                .padding(.bottom, 20 * s)
                
                // Bottom Stats
                HStack {
                    VStack(spacing: 4 * s) {
                        Text("\(session.runCount)")
                            .font(.system(size: 24 * s, weight: .medium))
                            .foregroundColor(.white)
                        Text("RUNS")
                            .font(.system(size: 9 * s, weight: .bold))
                            .tracking(2 * s)
                            .foregroundColor(.white.opacity(0.5))
                            .textCase(.uppercase)
                    }
                    
                    Spacer()
                    
                    Rectangle()
                         .fill(LinearGradient(colors: [.clear, .white.opacity(0.2), .clear], startPoint: .top, endPoint: .bottom))
                        .frame(width: 1 * s, height: 40 * s)
                    
                    Spacer()
                    
                    VStack(spacing: 4 * s) {
                        Text("\(Int(session.verticalDrop))")
                            .font(.system(size: 24 * s, weight: .medium))
                            .foregroundColor(.white)
                        Text("VERTICAL M")
                            .font(.system(size: 9 * s, weight: .bold))
                            .tracking(2 * s)
                            .foregroundColor(.white.opacity(0.5))
                            .textCase(.uppercase)
                    }
                }
                .padding(.horizontal, 20 * s)
            }
            .padding(30 * s)
            .background(.thinMaterial) // Frost effect check
            .background(Color.white.opacity(0.05))
            .cornerRadius(40 * s)
            .overlay(
                RoundedRectangle(cornerRadius: 40 * s)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1 * s)
            )
            .padding(.horizontal, 20 * s)
            .padding(.bottom, 40 * s)
            
            Spacer()
        }
    }
    
    // Rewind Export (Scaled x3)
    func exportStatsRewind() -> some View {
        let s: CGFloat = 3.0
        return ZStack {
             // Scanlines Overlay (Scaled)
            VStack(spacing: 0) {
                ForEach(0..<Int(100 * s), id: \.self) { _ in
                    Rectangle()
                        .fill(Color.black.opacity(0.1))
                        .frame(height: 2 * 1.5) // Slightly thicker relative to scale? No just keeping it fine or scaling
                        // Let's just standard scale
                    Spacer().frame(height: 2 * 1.5)
                }
            }
            .drawingGroup()
            .ignoresSafeArea()
            .allowsHitTesting(false)
            
            VStack {
                // Top Bar: REC & SP MODE
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2 * s) {
                        Text("REC")
                            .font(.system(size: 24 * s, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .shadow(color: .red.opacity(0.8), radius: 2 * s)
                            .overlay(
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 10 * s, height: 10 * s)
                                    .offset(x: -16 * s)
                                    // No animation in export static image
                            , alignment: .leading)
                            .padding(.leading, 16 * s)
                        
                         Text("SP MODE")
                            .font(.system(size: 14 * s, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.leading, 16 * s)
                    }
                    Spacer()
                }
                .padding(.top, 40 * s)
                .padding(.horizontal, 20 * s)
                
                Spacer()
                
                // Central Stats (Pixel look)
                VStack(spacing: 12 * s) {
                    // Distance
                    VStack(spacing: 0) {
                        Text(String(format: "%.1f", session.distance / 1000.0))
                            .font(.system(size: 100 * s, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 1, green: 1, blue: 0))
                            .shadow(color: .red, radius: 0, x: 2 * s, y: 1 * s)
                            .shadow(color: .cyan, radius: 0, x: -2 * s, y: -1 * s)
                        
                        Text("KM TRAVELED")
                            .font(.system(size: 32 * s, weight: .black, design: .monospaced))
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 10 * s)
                            .padding(.vertical, 0)
                            .background(Color.black.opacity(0.4))
                            .shadow(color: .red, radius: 0, x: 2 * s, y: 0)
                    }
                    
                    Spacer().frame(height: 20 * s)
                    
                    // List
                    VStack(spacing: 8 * s) {
                        HStack {
                            Text("RUNS")
                                .font(.system(size: 20 * s, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.9))
                            Spacer()
                            Text("\(session.runCount)")
                                .font(.system(size: 24 * s, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(red: 1, green: 1, blue: 0))
                        }
                        .padding(.bottom, 4 * s)
                        .overlay(Rectangle().fill(Color.white.opacity(0.3)).frame(height: 1 * s), alignment: .bottom)
                        
                        HStack {
                            Text("VERTICAL")
                                .font(.system(size: 20 * s, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.9))
                            Spacer()
                            Text("\(Int(session.verticalDrop)) M")
                                .font(.system(size: 24 * s, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(red: 1, green: 1, blue: 0))
                        }
                        .padding(.bottom, 4 * s)
                        .overlay(Rectangle().fill(Color.white.opacity(0.3)).frame(height: 1 * s), alignment: .bottom)
                    }
                    .frame(width: 280 * s)
                }
                .offset(y: -40 * s)
                
                Spacer()
                
                // Bottom Date Stamp
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading) {
                        Text(session.startTime.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)).replacingOccurrences(of: "/", with: " "))
                            .font(.system(size: 24 * s, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 1 * s)
                        Text(session.startTime.formatted(.dateTime.hour().minute().second()))
                            .font(.system(size: 18 * s, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    Spacer()
                    
                    Text("SNOW RECORD")
                        .font(.system(size: 14 * s, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                        .padding(.bottom, 4 * s)
                }
                .padding(.horizontal, 24 * s)
                .padding(.bottom, 140 * s)
            }
        }
    }
    
    // The Cover Export (Scaled x3)
    func exportStatsCover() -> some View {
        let s: CGFloat = 3.0
        return ZStack {
             // Top Date Tag
            VStack {
                Text("\(session.startTime.formatted(.dateTime.month(.abbreviated).day())) • VOL. 09")
                    .font(.system(size: 10 * s, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12 * s)
                    .padding(.vertical, 6 * s)
                    .background(Color.black.opacity(0.6).blur(radius: 2 * s))
                    .cornerRadius(4 * s)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4 * s)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1 * s)
                    )
                    .padding(.top, 40 * s)
                
                // Massive Headlines
                VStack(spacing: 8 * s) {
                    Text("SNOW RECORD")
                        .font(.system(size: 48 * s, weight: .black))
                        .italic()
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.6), radius: 5 * s, x: 0, y: 4 * s)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    
                    ZStack {
                        // Shadow/Glow Background
                        Text("POWDER\nDAY")
                            .font(.system(size: 90 * s, weight: .black))
                            .italic()
                            .multilineTextAlignment(.center)
                            .lineSpacing(-20 * s)
                            .foregroundColor(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.5), radius: 10 * s)
                            .minimumScaleFactor(0.5)
                        
                        // Stroke Effect
                         Text("POWDER\nDAY")
                            .font(.system(size: 90 * s, weight: .black))
                            .italic()
                            .multilineTextAlignment(.center)
                            .lineSpacing(-20 * s)
                            .foregroundColor(.clear)
                            .overlay(
                                Text("POWDER\nDAY")
                                    .font(.system(size: 90 * s, weight: .black))
                                    .italic()
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(-20 * s)
                                    .foregroundColor(.white.opacity(0.3))
                                    .minimumScaleFactor(0.5)
                            )
                            .minimumScaleFactor(0.5)
                    }
                }
                .padding(.top, 20 * s)
                
                Spacer()
                
                // Bottom Ticket Sticker (Rotated)
                HStack {
                    Spacer()
                    
                    ZStack(alignment: .topTrailing) {
                        // Pin / Dot
                        Circle()
                            .fill(primaryColor)
                            .frame(width: 8 * s, height: 8 * s)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1 * s))
                            .offset(x: 4 * s, y: -4 * s)
                            .zIndex(10)
                        
                        VStack(spacing: 0) {
                            // stats
                            VStack(spacing: 8 * s) {
                                HStack(alignment: .lastTextBaseline) {
                                    Text("DIST")
                                        .font(.system(size: 8 * s, weight: .bold, design: .monospaced))
                                        .foregroundColor(.black)
                                    Spacer()
                                    HStack(alignment: .top, spacing: 1 * s) {
                                        Text(String(format: "%.1f", session.distance / 1000.0))
                                            .font(.system(size: 24 * s, weight: .black))
                                            .italic()
                                            .foregroundColor(.black)
                                        Text("KM")
                                            .font(.system(size: 8 * s, weight: .bold))
                                            .foregroundColor(.black)
                                            .offset(y: 4 * s)
                                    }
                                }
                                .padding(.bottom, 4 * s)
                                .overlay(Rectangle().fill(Color.black).frame(height: 2 * s), alignment: .bottom)
                                
                                HStack(alignment: .lastTextBaseline) {
                                    Text("MAX")
                                        .font(.system(size: 8 * s, weight: .bold, design: .monospaced))
                                        .foregroundColor(.black)
                                    Spacer()
                                    Text(String(format: "%.1f", session.maxSpeed))
                                        .font(.system(size: 24 * s, weight: .black))
                                        .italic()
                                        .foregroundColor(.black)
                                }
                            }
                            .padding(12 * s)
                            .padding(.bottom, 4 * s)
                            
                            // Barcode Visual
                            HStack(alignment: .bottom, spacing: 2 * s) {
                                ForEach(0..<15) { i in
                                    Rectangle()
                                        .fill(Color.black.opacity(0.9))
                                        .frame(width: CGFloat([2, 1, 4, 1, 3, 1, 2, 5, 2, 1, 3, 1, 4, 2, 3][i]) * s, height: CGFloat([20, 15, 24, 12, 22, 18, 24, 20, 16, 24, 20, 14, 22, 18, 24][i]) * s)
                                }
                            }
                            .frame(height: 24 * s)
                            .padding(.bottom, 8 * s)
                            
                            // Footer Codes
                            HStack {
                                Text("USER-01")
                                Text("#SNOWREC")
                            }
                            .font(.system(size: 6 * s, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.bottom, 8 * s)
                        }
                        .frame(width: 140 * s)
                        .background(Color.white)
                        .border(Color.black, width: 2 * s)
                        .shadow(color: .black.opacity(0.4), radius: 10 * s, x: 5 * s, y: 10 * s)
                        .rotationEffect(.degrees(-6))
                    }
                    .padding(.bottom, 120 * s) // Space for button
                    .padding(.trailing, 20 * s)
                }
            }
        }
    }
    
    // Tech-Spec Export (Scaled x3)
    func exportStatsTechSpec() -> some View {
        let s: CGFloat = 3.0
        return ZStack {
            // Corner Brackets
            VStack {
                HStack {
                    cornerBracket(topLeft: true).scaleEffect(s)
                    Spacer()
                    cornerBracket(topLeft: false, topRight: true).scaleEffect(s)
                }
                Spacer()
                HStack {
                    cornerBracket(bottomLeft: true).scaleEffect(s)
                    Spacer()
                    cornerBracket(bottomLeft: false, bottomRight: true).scaleEffect(s)
                }
            }
            .padding(20 * s)
            
            VStack {
                // Top Bar
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2 * s) {
                        HStack(spacing: 6 * s) {
                            Image(systemName: "snowflake")
                                .foregroundColor(primaryColor)
                                .font(.system(size: 14 * s))
                            Text("SNOW RECORD")
                                .font(.system(size: 14 * s, weight: .bold, design: .monospaced))
                                .tracking(2 * s)
                                .foregroundColor(.white)
                        }
                        Text("SYSTEM ONLINE // V.2.4")
                            .font(.system(size: 8 * s, design: .monospaced))
                            .foregroundColor(primaryColor.opacity(0.8))
                            .tracking(1 * s)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4 * s) {
                        HStack(spacing: 4 * s) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6 * s, height: 6 * s)
                                .shadow(color: .red, radius: 4 * s)
                            Text("REC: ACTIVE")
                                .font(.system(size: 10 * s, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .tracking(1 * s)
                        }
                        .padding(.horizontal, 6 * s)
                        .padding(.vertical, 2 * s)
                        .background(Color.black.opacity(0.6))
                        .border(primaryColor.opacity(0.5), width: 0.5 * s)
                        
                        Text("T-MINUS 00:42:12")
                            .font(.system(size: 8 * s, design: .monospaced))
                            .foregroundColor(primaryColor.opacity(0.6))
                    }
                }
                .padding(.horizontal, 30 * s)
                .padding(.top, 40 * s)
                
                Spacer()
                
                // Central HUD
                ZStack {
                    // Crosshairs
                    Rectangle()
                        .fill(primaryColor.opacity(0.3))
                        .frame(width: 1 * s, height: 300 * s)
                    Rectangle()
                        .fill(primaryColor.opacity(0.3))
                        .frame(width: 300 * s, height: 1 * s)
                    
                    // Circles
                    Circle()
                        .stroke(primaryColor.opacity(0.3), style: StrokeStyle(lineWidth: 1 * s, dash: [4 * s, 4 * s]))
                        .frame(width: 260 * s, height: 260 * s)
                     Circle()
                        .stroke(primaryColor, lineWidth: 1 * s)
                        .frame(width: 220 * s, height: 220 * s)
                        
                    // Data
                    VStack(spacing: 4 * s) {
                        Text("SPEED")
                            .font(.system(size: 10 * s, design: .monospaced))
                            .tracking(4 * s)
                            .foregroundColor(primaryColor.opacity(0.7))
                            .padding(.bottom, 4 * s)
                        
                        Text(String(format: "%.1f", session.maxSpeed))
                            .font(.system(size: 64 * s, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .shadow(color: primaryColor.opacity(0.6), radius: 10 * s)
                        
                        Text("KM/H")
                            .font(.system(size: 14 * s, weight: .bold, design: .monospaced))
                            .foregroundColor(primaryColor)
                        
                        Rectangle()
                            .fill(primaryColor.opacity(0.5))
                            .frame(width: 140 * s, height: 1 * s)
                            .padding(.vertical, 8 * s)
                        
                        VStack(spacing: 0) {
                            Text(String(format: "%.1f", session.maxGForce > 0 ? session.maxGForce : 1.2))
                                .font(.system(size: 24 * s, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                            Text("G-FORCE")
                                .font(.system(size: 8 * s, design: .monospaced))
                                .tracking(2 * s)
                                .foregroundColor(primaryColor.opacity(0.6))
                        }
                    }
                }
                .offset(y: -40 * s)
                
                Spacer()
                
                // Bottom Status
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4 * s) {
                        Text("ALTITUDE")
                            .font(.system(size: 10 * s, design: .monospaced))
                            .tracking(2 * s)
                            .foregroundColor(primaryColor.opacity(0.6))
                        
                        HStack(alignment: .firstTextBaseline, spacing: 2 * s) {
                            Text("3,100")
                                .font(.system(size: 20 * s, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                            Text("M")
                                .font(.system(size: 12 * s, weight: .bold, design: .monospaced))
                                .foregroundColor(primaryColor)
                        }
                        
                        HStack(spacing: 4 * s) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8 * s))
                            Text("LOCKED")
                                .font(.system(size: 8 * s, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(primaryColor)
                        .padding(4 * s)
                        .background(primaryColor.opacity(0.1))
                        .cornerRadius(2 * s)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4 * s) {
                        Text("ENV. STATUS")
                            .font(.system(size: 10 * s, design: .monospaced))
                            .tracking(2 * s)
                            .foregroundColor(primaryColor.opacity(0.6))
                        
                        Text("POWDER")
                            .font(.system(size: 18 * s, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .tracking(2 * s)
                        
                        Text("-12°C // WIND 15KT")
                            .font(.system(size: 10 * s, design: .monospaced))
                            .foregroundColor(primaryColor.opacity(0.8))
                    }
                }
                .padding(.horizontal, 30 * s)
                .padding(.bottom, 140 * s)
            }
        }
    }
    
    // Explorer Export
    @ViewBuilder
    func exportStatsExplorer() -> some View {
        let s: CGFloat = 3.0
        VStack {
            Spacer()
            
            // Brand Top Left
            HStack {
                HStack(spacing: 8 * s) {
                    Image(systemName: "snowflake")
                        .font(.system(size: 24 * s))
                        .foregroundColor(primaryColor)
                        .shadow(color: .black.opacity(0.5), radius: 2 * s, x: 0, y: 1 * s)
                    Text("SNOW RECORD")
                        .font(.system(size: 20 * s, weight: .black))
                        .italic()
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2 * s, x: 0, y: 1 * s)
                }
                Spacer()
            }
            .padding(.horizontal, 24 * s)
            .padding(.bottom, 40 * s)
            
            Spacer()
            
            // Main Stat: Distance (Stroked Text Effect)
            // Main Stat: Distance (Solid Shadow Effect)
            VStack(spacing: 0) {
                let distText = String(format: "%.1f", session.distance / 1000.0)
                ZStack {
                    // 1. Solid Shadow
                    Text(distText)
                        .font(.system(size: 100 * s, weight: .black))
                        .italic()
                        .foregroundColor(primaryColor)
                        .offset(x: 4 * s, y: 4 * s)
                        .opacity(0.8)
                    
                    // 2. Main Text
                    Text(distText)
                        .font(.system(size: 100 * s, weight: .black))
                        .italic()
                        .foregroundColor(.white)
                }
                
                Text("KILOMETERS")
                    .font(.system(size: 24 * s, weight: .heavy))
                    .italic()
                    .foregroundColor(.white)
                    .padding(.leading, 10 * s)
            }
            .padding(.leading, 20 * s)
            .padding(.bottom, 40 * s)
            
            // Sub Stats
            HStack(spacing: 40 * s) {
                // Runs
                VStack(spacing: 2 * s) {
                    Text("\(session.runCount)")
                        .font(.system(size: 24 * s, weight: .black))
                        .italic()
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2 * s)
                    Text("RUNS")
                        .font(.system(size: 10 * s, weight: .bold))
                        .foregroundColor(primaryColor)
                        .tracking(2 * s)
                }
                
                // Divider
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 2 * s, height: 24 * s)
                    .rotationEffect(.degrees(12))
                
                // Vertical
                VStack(spacing: 2 * s) {
                    Text("\(Int(session.verticalDrop)) M")
                        .font(.system(size: 24 * s, weight: .black))
                        .italic()
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2 * s)
                    Text("VERTICAL")
                        .font(.system(size: 10 * s, weight: .bold))
                        .foregroundColor(primaryColor)
                        .tracking(2 * s)
                }
            }
            .padding(.bottom, 120 * s)
        }
    }
    
    // Speed Demon Export
    func exportStatsSpeedDemon() -> some View {
        let s: CGFloat = 3.0
        return VStack {
            Spacer()
            
            // Hero Metric (Center)
            VStack(spacing: 0) {
                // Label Chip
                HStack(spacing: 4 * s) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 10 * s, weight: .bold))
                    Text("MAX SPEED")
                        .font(.system(size: 10 * s, weight: .black))
                        .tracking(1 * s)
                }
                .foregroundColor(primaryColor)
                .padding(.horizontal, 12 * s)
                .padding(.vertical, 6 * s)
                .background(primaryColor.opacity(0.1))
                .overlay(
                    Capsule().stroke(primaryColor.opacity(0.3), lineWidth: 1 * s)
                )
                .clipShape(Capsule())
                .padding(.bottom, 4 * s)
                
                // Value
                Text(String(format: "%.1f", session.maxSpeed))
                    .font(.system(size: 100 * s, weight: .black))
                    .italic()
                    .foregroundColor(primaryColor)
                    .shadow(color: primaryColor.opacity(0.5), radius: 20 * s)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                
                // Unit
                Text("KM/H")
                    .font(.system(size: 24 * s, weight: .bold))
                    .italic()
                    .tracking(4 * s)
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.top, -10 * s)
            }
            
            Spacer()
                .frame(height: 50 * s)
            
            // Secondary Stats Glass Panel
            HStack(spacing: 0) {
                // Runs
                VStack(spacing: 2 * s) {
                    Image(systemName: "figure.skiing.downhill")
                        .font(.system(size: 24 * s))
                        .foregroundColor(.white)
                    
                    Text("\(session.runCount)")
                        .font(.system(size: 20 * s, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("RUNS")
                        .font(.system(size: 9 * s, weight: .bold))
                        .tracking(2 * s)
                        .foregroundColor(.white.opacity(0.6))
                        .textCase(.uppercase)
                }
                .frame(maxWidth: .infinity)
                
                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 1 * s, height: 40 * s)
                
                // Distance
                VStack(spacing: 2 * s) {
                    Image(systemName: "map")
                        .font(.system(size: 24 * s))
                        .foregroundColor(.white)
                    
                    Text(String(format: "%.1f", session.distance / 1000.0))
                        .font(.system(size: 20 * s, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("KM DIST")
                        .font(.system(size: 9 * s, weight: .bold))
                        .tracking(2 * s)
                        .foregroundColor(.white.opacity(0.6))
                        .textCase(.uppercase)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 20 * s)
            .background(Color(red: 23/255, green: 35/255, blue: 15/255).opacity(0.6))
            .background(.thinMaterial)
            .cornerRadius(24 * s)
            .overlay(
                RoundedRectangle(cornerRadius: 24 * s)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1 * s)
            )
            .padding(.horizontal, 40 * s)
            
            Spacer()
        }
    }
    
    // Standard Export
    func exportStatsStandard() -> some View {
        let s: CGFloat = 3.0 // Scale factor for export
        
        return VStack(alignment: .leading, spacing: 0) {
            // Runs
            Text("\(session.runCount) RUNS")
                .font(.system(size: 12 * s, weight: .black))
                .padding(.horizontal, 10 * s)
                .padding(.vertical, 4 * s)
                .background(Color.white)
                .foregroundColor(.black)
                .rotationEffect(.degrees(2))
                .padding(.bottom, 8 * s)
            
            // Distance
            VStack(alignment: .leading, spacing: 0) {
                Text("TOTAL DISTANCE")
                    .font(.system(size: 10 * s, weight: .bold))
                    .tracking(2 * s)
                    .foregroundColor(.white.opacity(0.7))
                HStack(alignment: .lastTextBaseline, spacing: 4 * s) {
                    Text(String(format: "%.1f", session.distance / 1000.0))
                        .font(.system(size: 72 * s, weight: .black))
                        .foregroundColor(primaryColor)
                        .shadow(color: primaryColor.opacity(0.5), radius: 8 * s)
                    Text("KM")
                        .font(.system(size: 28 * s, weight: .black))
                        .italic()
                        .foregroundColor(.white)
                }
            }
            .padding(.bottom, 12 * s)
            
            // Speed
            VStack(alignment: .leading, spacing: 2 * s) {
                Text("TOP VELOCITY")
                    .font(.system(size: 9 * s, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                Text("MAX SPEED \(String(format: "%.1f", session.maxSpeed)) KM/H")
                    .font(.system(size: 16 * s, weight: .black))
                    .foregroundColor(.white)
            }
            .padding(10 * s)
            .background(Color.black.opacity(0.5))
            .cornerRadius(4 * s)
            .padding(.bottom, 20 * s)
            
            // Divider
            Rectangle().fill(Color.white.opacity(0.3)).frame(height: 1 * s).padding(.bottom, 16 * s)
            
            // Footer
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4 * s) {
                    Text("KOREA").font(.system(size: 28 * s, weight: .bold)).foregroundColor(.white)
                    Text(session.locationName).font(.system(size: 16 * s)).foregroundColor(.white.opacity(0.7))
                    HStack(spacing: 4 * s) {
                        Image(systemName: "calendar").font(.system(size: 12 * s)).foregroundColor(primaryColor)
                        Text(session.startTime.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 11 * s, weight: .bold))
                            .foregroundColor(primaryColor)
                    }
                    .padding(.top, 4 * s)
                }
                Spacer()
                decoBar(height: 32 * s)
            }
        }
    }
    
    // Photo Export
    func exportStatsPhoto() -> some View {
        let s: CGFloat = 3.0
        return VStack(spacing: 0) {
            Spacer()
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4 * s) {
                    Text("\(session.runCount) RUNS")
                        .font(.system(size: 16 * s, weight: .heavy))
                        .foregroundColor(primaryColor)
                    
                    Text(String(format: "%.1f KM", session.distance / 1000.0))
                        .font(.system(size: 36 * s, weight: .black))
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 2 * s)
                    
                    Text(session.locationName)
                        .font(.system(size: 14 * s, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .shadow(color: .black, radius: 2 * s)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 0) {
                     Text("MAX SPEED")
                        .font(.system(size: 10 * s, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                    Text("\(String(format: "%.0f", session.maxSpeed))")
                        .font(.system(size: 48 * s, weight: .black))
                        .italic()
                        .foregroundColor(.white)
                        .shadow(color: primaryColor.opacity(0.5), radius: 10 * s)
                    Text("KM/H")
                        .font(.system(size: 12 * s, weight: .bold))
                        .foregroundColor(primaryColor)
                }
            }
            .padding(20 * s)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
            )
        }
    }
    
    // Minimal Export
    func exportStatsMinimal() -> some View {
        let s: CGFloat = 3.0
        return HStack {
            VStack(alignment: .leading, spacing: 16 * s) {
                Rectangle()
                    .fill(primaryColor)
                    .frame(width: 40 * s, height: 4 * s)
                
                VStack(alignment: .leading, spacing: 0) {
                    Text("DISTANCE")
                        .font(.system(size: 10 * s, weight: .medium))
                        .tracking(2 * s)
                        .foregroundColor(.white.opacity(0.6))
                    Text(String(format: "%.1f KM", session.distance / 1000.0))
                        .font(.system(size: 32 * s, weight: .light))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    Text("RUNS")
                        .font(.system(size: 10 * s, weight: .medium))
                        .tracking(2 * s)
                        .foregroundColor(.white.opacity(0.6))
                    Text("\(session.runCount)")
                        .font(.system(size: 32 * s, weight: .light))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    Text("MAX SPEED")
                        .font(.system(size: 10 * s, weight: .medium))
                        .tracking(2 * s)
                        .foregroundColor(.white.opacity(0.6))
                    Text("\(Int(session.maxSpeed))")
                        .font(.system(size: 32 * s, weight: .light))
                        .foregroundColor(.white)
                    + Text(" KM/H").font(.system(size: 12 * s)).foregroundColor(.gray)
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 4 * s) {
                    Text(session.locationName.uppercased())
                        .font(.system(size: 14 * s, weight: .bold))
                        .tracking(1 * s)
                        .foregroundColor(.white)
                    Text(session.startTime.formatted(date: .numeric, time: .omitted))
                        .font(.system(size: 10 * s))
                        .foregroundColor(.gray)
                }
            }
            .padding(.vertical, 20 * s)
            .padding(.horizontal, 20 * s)
            .background(Color.black.opacity(0.4).blur(radius: 10 * s))
            .cornerRadius(0)
            
            Spacer()
        }
    }
    
    // MARK: - Export View (1080x1920)
    // MARK: - Export View (1080x1920)
    func exportView() -> some View {
        return ZStack {
            Color.black
            
            if let uiImage = backgroundUIImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(currentScale)
                    .offset(x: currentOffset.width * 3, y: currentOffset.height * 3)
                    .frame(width: 1080, height: 1920)
                    .clipped()
            } else {
                LinearGradient(colors: [Color(white: 0.15), .black], startPoint: .top, endPoint: .bottom)
            }
            
            LinearGradient(colors: [.black.opacity(0.3), .clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
            
            VStack {
                Spacer()
                exportStatsView()
                    .padding(.horizontal, 60)
                    .padding(.bottom, 120)
            }
            
            // Brand Watermark (설정 기반)
            if selectedLayout.getWatermarkConfig().show {
                watermarkOverlay(config: selectedLayout.getWatermarkConfig(), scaled: true)
            }
        }
        .frame(width: 1080, height: 1920)
    }
    
    func exportBrandView() -> some View {
        let s: CGFloat = 3.0
        return HStack(spacing: 8 * s) {
            Image(systemName: "snowflake")
                .font(.system(size: 22 * s))
                .foregroundColor(primaryColor)
            Text("SNOW RECORD")
                .font(.system(size: 18 * s, weight: .black))
                .italic()
                .foregroundColor(.white)
        }
        .padding(10 * s)
        .background(Color.black.opacity(0.5))
        .cornerRadius(4 * s)
    }
    
    // MARK: - Actions
    @MainActor
    func shareToStory() {
        let renderer = ImageRenderer(content: exportView())
        renderer.scale = 1.0
        guard let image = renderer.uiImage, let imageData = image.pngData() else { return }

        let bundleId = Bundle.main.bundleIdentifier ?? ""
        let urlString = "instagram-stories://share?source_application=\(bundleId)"

        if let url = URL(string: urlString),
           UIApplication.shared.canOpenURL(url) {
            let pasteboardItems: [[String: Any]] = [[
                "com.instagram.sharedSticker.backgroundImage": imageData
            ]]
            UIPasteboard.general.setItems(
                pasteboardItems,
                options: [.expirationDate: Date().addingTimeInterval(300)]
            )
            UIApplication.shared.open(url)
        } else {
            imageToShare = image
            showShareSheet = true
        }
    }
    
    @MainActor
    func saveToPhotos() {
        let renderer = ImageRenderer(content: exportView())
        renderer.scale = 1.0
        if let image = renderer.uiImage {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            withAnimation(.spring()) {
                showSaveToast = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showSaveToast = false
                }
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: RunSession.self, configurations: config)
    
    // Create Dummy Session
    let session = RunSession(
        startTime: Date(),
        endTime: Date().addingTimeInterval(3600),
        duration: 3600,
        distance: 12500, // 12.5km
        maxSpeed: 64.8,
        avgSpeed: 35.0,
        verticalDrop: 2150,
        runCount: 12,
        locationName: "YongPyong Resort"
    )

    SharePreviewView(session: session)
        .modelContainer(container)
        .onAppear {
            container.mainContext.insert(session)
        }
}
