import SwiftUI
import MapKit
import SwiftData
import Charts

struct RunDetailView: View {
    @Environment(\.dismiss) var dismiss
    let session: RunSession
    
    // State for Share Preview
    @State private var showSharePreview = false
    
    // State for GPX Export
    @State private var gpxFileURL: IdentifiableURL?
    @State private var showNoDataAlert = false
    @State private var showFullScreenMap = false
    @State private var isTimelineExpanded = false
    
    // Theme Colors
    let primaryColor = Color(hex: "6bf906")
    let backgroundDark = Color.black
    let surfaceDark = Color(hex: "0a0a0a")
    let surfaceCard = Color(hex: "111111")
    
    // Score Info
    enum ScoreInfoType: Identifiable {
        case edge
        case flow
        
        var id: Self { self }
        
        var title: String {
            switch self {
            case .edge: return "EDGE SCORE"
            case .flow: return "FLOW SCORE"
            }
        }
        
        var description: String {
            switch self {
            case .edge: return "\"얼마나 날카롭게 베고 나갔는가?\"\n\n당신의 턴이 설면을 얼마나 견고하게 파고들었는지 분석한 '카빙(Carving) 완성도' 지표입니다.\n\n분석 기준: 턴의 깊이, 엣징 각도(G-Force), 슬립(미끄러짐) 최소화\n\nTip: 데크가 눈에 박히는 느낌에 집중하고, 과감하게 엣지를 세울수록 점수가 올라갑니다."
            case .flow: return "\"얼마나 물 흐르듯 내려왔는가?\"\n\n주행의 리듬과 속도 유지를 분석한 '주행 안정성(Smoothness)' 지표입니다.\n\n분석 기준: 속도 유지력, 턴 연결의 부드러움, 불필요한 급제동 여부\n\nTip: 턴과 턴 사이가 끊기지 않게 연결하고, 일정한 리듬을 유지할수록 점수가 올라갑니다."
            }
        }
    }
    
    @State private var selectedScoreInfo: ScoreInfoType?
    
    var body: some View {
        ZStack {
            backgroundDark.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        
                        // 1. Hero Section (Scores)
                        scoresSection
                            .padding(.top, 20)
                        
                        // 2. Map Section
                        mapSection
                        
                        // 3. Slopes Ridden (Compact)
                        if !session.riddenSlopes.isEmpty {
                            slopesRiddenSection
                        }
                        
                        // 4. Metrics Grid (Bento)
                        metricsGrid
                        
                        // 5. Timeline
                        if !session.timelineEvents.isEmpty {
                            timelineSection
                        }
                        
                        // 6. Bottom Share Button
                        shareBuoon
                            .padding(.vertical, 30)
                    }
                    .padding(.bottom, 100)
                }
            }
        }
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showSharePreview) {
            SharePreviewView(session: session)
        }
        .fullScreenCover(isPresented: $showFullScreenMap) {
            FullScreenMapView(coordinates: routeCoordinates, speeds: session.routeSpeeds, maxSpeed: session.maxSpeed, runStartIndices: session.runStartIndices, region: mapRegion)
        }
        .sheet(item: $gpxFileURL) { identifiableURL in
            ShareSheet(activityItems: [identifiableURL.url])
        }
        .alert("GPX Export 불가", isPresented: $showNoDataAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("이 세션에는 GPS 경로 데이터가 없습니다.")
        }
        .alert(item: $selectedScoreInfo) { info in
            Alert(
                title: Text(info.title),
                message: Text(info.description),
                dismissButton: .default(Text("확인"))
            )
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            
            Text("RUN DETAILS")
                .font(.system(size: 14, weight: .bold))
                .tracking(2)
                .foregroundColor(.white)
                .shadow(color: primaryColor.opacity(0.5), radius: 5)
            
            Button(action: { exportGPX() }) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(primaryColor)
                    .frame(width: 40, height: 40)
                    .background(primaryColor.opacity(0.1))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(primaryColor.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: primaryColor.opacity(0.2), radius: 5)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(surfaceDark.opacity(0.8))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.white.opacity(0.08)),
            alignment: .bottom
        )
    }
    
    private var scoresSection: some View {
        HStack(spacing: 16) {
            // Edge Control
            scoreCard(title: "EDGE SCORE", score: session.edgeScore, infoType: .edge)
            
            // Flow
            scoreCard(title: "FLOW SCORE", score: session.flowScore, infoType: .flow)
        }
        .padding(.horizontal)
    }
    
    private func scoreCard(title: String, score: Int, infoType: ScoreInfoType) -> some View {
        VStack {
            ZStack {
                // Background Track
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 6)
                    .frame(width: 90, height: 90)
                
                // Progress Circle
                RingGaugeView(progress: Double(score) / 100.0, color: primaryColor)
                    .frame(width: 90, height: 90)
                    
                // Score Text
                VStack(spacing: -2) {
                    Text("\(score)")
                        .font(.system(size: 28, weight: .bold)) // Space Grotesk feel
                        .foregroundColor(.white)
                        .shadow(color: primaryColor.opacity(0.5), radius: 8)
                    Text("/100")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }
            .padding(.bottom, 12)
            
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.5)
                .foregroundColor(.gray)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(surfaceCard)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
        .overlay(
            Button(action: { selectedScoreInfo = infoType }) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 14))
                    .foregroundColor(.gray.opacity(0.6))
                    .padding(12)
            },
            alignment: .topTrailing
        )
        .shadow(color: .black.opacity(0.3), radius: 10)
    }
    
    private var mapSection: some View {
        ZStack {
             // Map with Route
            Map(coordinateRegion: .constant(mapRegion))
            .overlay(
                Group {
                    if !session.routeSpeeds.isEmpty {
                        GradientRouteOverlay(coordinates: routeCoordinates, speeds: session.routeSpeeds, maxSpeed: session.maxSpeed)
                    } else {
                        MapRouteOverlay(coordinates: routeCoordinates, color: primaryColor)
                    }
                }
            )
            .disabled(true)
            .colorMultiply(Color(white: 0.6)) // Darken map
            .grayscale(0.8)
            
            // Gradient Overlay
             LinearGradient(
                 colors: [Color.black.opacity(0.8), .clear],
                 startPoint: .bottom,
                 endPoint: .top
             )
            
             // Info Overlay
             VStack {
                 Spacer()
                 HStack(alignment: .bottom) {
                     VStack(alignment: .leading, spacing: 2) {
                         Text("LOCATION")
                             .font(.system(size: 10, weight: .bold))
                             .foregroundColor(primaryColor)
                             .tracking(1)
                         Text(session.locationName)
                             .font(.system(size: 20, weight: .heavy)) // heavy equivalent
                             .foregroundColor(.white)
                     }
                     
                     Spacer()
                     
                     VStack(alignment: .trailing, spacing: 2) {
                         Text("DATE")
                             .font(.system(size: 10, weight: .bold))
                             .foregroundColor(.gray)
                             .tracking(1)
                         Text(session.startTime.formatted(.dateTime.day().month(.abbreviated).year(.defaultDigits)))
                             .font(.system(size: 16, weight: .bold))
                             .foregroundColor(.white)
                     }
                 }
                 .padding(16)
                 .background(.ultraThinMaterial)
                 .cornerRadius(12)
                 .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                 )
             }
             .padding(12)
        }
        .frame(height: 200)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal)
        .shadow(color: .black.opacity(0.5), radius: 15)
        .onTapGesture {
            showFullScreenMap = true
        }
    }
    
    private var slopesRiddenSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(primaryColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: primaryColor, radius: 4)
                Text("SLOPES RIDDEN")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .tracking(2)
            }
            .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(session.riddenSlopes.sorted(by: { $0.value > $1.value }), id: \.key) { name, count in
                        SlopeCard(name: name, count: count)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            // Vertical Drop (Span 2)
            verticalDropCard
                .gridCellColumns(2)
            
            // Small Metrics
            metricCardBento(title: "MAX SPEED", value: String(format: "%.1f", session.maxSpeed), unit: "KM/H", icon: "speedometer")
            metricCardBento(title: "AVG SPEED", value: String(format: "%.1f", session.avgSpeed), unit: "KM/H", icon: "timer")
            metricCardBento(title: "DISTANCE", value: String(format: "%.1f", session.distance / 1000.0), unit: "KM", icon: "ruler")
            metricCardBento(title: "RUN COUNT", value: "\(session.runCount)", unit: "LAPS", icon: "arrow.triangle.2.circlepath")
            
            // Duration (Span 2)
            metricCardBento(title: "DURATION", value: formatSessionDuration(session.duration), unit: "TIME", icon: "clock")
                .gridCellColumns(2)
        }
        .padding(.horizontal)
    }
    
    private func formatSessionDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "00:00"
    }
    
    private var verticalDropCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "arrow.down.to.line")
                        .font(.caption)
                        .foregroundColor(primaryColor)
                    Text("VERTICAL DROP")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(primaryColor)
                        .tracking(2)
                }
                
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(Int(session.verticalDrop))")
                        .font(.system(size: 36, weight: .bold)) // Space Grotesk
                        .foregroundColor(.white)
                        .shadow(color: primaryColor.opacity(0.3), radius: 8)
                    Text("M")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            // Visual Bars Decoration
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<5) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i == 3 ? primaryColor : primaryColor.opacity(Double(i+2)/10.0))
                        .frame(width: 6, height: CGFloat([20, 35, 50, 65, 40][i]))
                        .shadow(color: i == 3 ? primaryColor.opacity(0.8) : .clear, radius: 5)
                }
            }
            .opacity(0.8)
        }
        .padding(20)
        .background(surfaceCard)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(primaryColor.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: primaryColor.opacity(0.05), radius: 10)
    }
    
    private func metricCardBento(title: String, value: String, unit: String, icon: String) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.gray)
                    .tracking(1)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.gray.opacity(0.7))
            }
            
            Spacer()
            
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text(unit)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.gray)
            }
        }
        .padding(16)
        .frame(height: 100)
        .background(surfaceCard)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
        .hoverEffect(.highlight)
    }
    
    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Circle()
                    .fill(primaryColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: primaryColor, radius: 4)
                Text("TIMELINE")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .tracking(2)
                
                Spacer()
                
                Button(action: { withAnimation { isTimelineExpanded.toggle() } }) {
                    HStack(spacing: 4) {
                        Text(isTimelineExpanded ? "COLLAPSE" : "VIEW ALL")
                            .font(.system(size: 10, weight: .bold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .rotationEffect(.degrees(isTimelineExpanded ? 90 : 0))
                    }
                    .foregroundColor(primaryColor)
                }
            }
            .padding(.horizontal)
            
            // Summary Bar
            HStack(spacing: 0) {
                let counts = Dictionary(grouping: session.timelineEvents, by: { $0.type }).mapValues { $0.count }
                let total = Double(session.timelineEvents.count)
                let rideP = Double(counts[.riding] ?? 0) / total
                let liftP = Double(counts[.lift] ?? 0) / total
                // Rest remains
                
                Rectangle().fill(primaryColor).frame(width: UIScreen.main.bounds.width * 0.6 * rideP)
                Rectangle().fill(Color.white.opacity(0.2)).frame(width: UIScreen.main.bounds.width * 0.6 * liftP)
                Rectangle().fill(surfaceCard).frame(maxWidth: .infinity)
            }
            .frame(height: 6)
            .cornerRadius(3)
            .overlay(
                RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .padding(.horizontal)
            
            // Legend
            HStack(spacing: 12) {
                legendItem(color: primaryColor, label: "RIDE")
                legendItem(color: Color.white.opacity(0.2), label: "LIFT")
                legendItem(color: surfaceCard, isBorder: true, label: "REST")
            }
            .padding(.horizontal)
            
            // Timeline List (Subway Style)
            VStack(spacing: 0) {
                let eventsToShow = isTimelineExpanded ? session.timelineEvents : Array(session.timelineEvents.prefix(3))
                
                ForEach(Array(eventsToShow.enumerated()), id: \.element.id) { index, event in
                    TimelineRowModern(event: event, isLast: index == eventsToShow.count - 1 && isTimelineExpanded, primaryColor: primaryColor)
                }
                
                if !isTimelineExpanded && session.timelineEvents.count > 3 {
                    // Fade out cue
                    Text("...")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal)
        }
    }
    
    private func legendItem(color: Color, isBorder: Bool = false, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .overlay(
                    Circle().stroke(Color.white.opacity(0.2), lineWidth: isBorder ? 1 : 0)
                )
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.gray)
        }
    }
    
    private var shareBuoon: some View {
        Button(action: { showSharePreview = true }) {
            HStack {
                Image(systemName: "square.and.arrow.up")
                Text("SHARE THIS SESSION")
            }
            .font(.system(size: 14, weight: .bold))
            .tracking(1)
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(primaryColor)
            .cornerRadius(16)
            .shadow(color: primaryColor.opacity(0.4), radius: 15)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
            )
        }
        .padding(.horizontal)
    }
    
    // MARK: - Helper Methods
    
    private func exportGPX() {
        guard !session.routeCoordinates.isEmpty else {
            showNoDataAlert = true
            return
        }
        
        if let url = GPXExporter.saveToFile(session: session) {
            gpxFileURL = IdentifiableURL(url: url)
        }
    }
    
    // Coordinates Helper
    private var routeCoordinates: [CLLocationCoordinate2D] {
        session.routeCoordinates.compactMap {
            CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1])
        }
    }
    
    private var mapRegion: MKCoordinateRegion {
        guard !routeCoordinates.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.198, longitude: 128.825),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }
        
        let lats = routeCoordinates.map { $0.latitude }
        let lons = routeCoordinates.map { $0.longitude }
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.5, 0.005),
            longitudeDelta: max((lons.max()! - lons.min()!) * 1.5, 0.005)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

// MARK: - Ring Gauge View
struct RingGaugeView: View {
    let progress: Double
    let color: Color
    
    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.6), radius: 8)
        }
    }
}

// MARK: - Modern Timeline Row
struct TimelineRowModern: View {
    let event: RunSession.TimelineEvent
    let isLast: Bool
    let primaryColor: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Line & Dot
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 10, height: 10)
                        .shadow(color: dotColor.opacity(0.5), radius: 5)
                    
                    if event.type == .riding {
                        Circle()
                            .stroke(Color.black, lineWidth: 2)
                            .frame(width: 10, height: 10)
                    }
                }
                
                if !isLast {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, 4)
                }
            }
            .frame(width: 20)
            
            // Content Card
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.type.rawValue.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(titleColor)
                        .tracking(1)
                    Spacer()
                    Text(event.startTime.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)
                }
                
                HStack {
                    Text(event.detail)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    if event.duration > 0 {
                        Text(formatDuration(event.duration))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(12)
            .background(Color(hex: "111111"))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 1)
            )
            .padding(.bottom, 16)
        }
    }
    
    var dotColor: Color {
        switch event.type {
        case .riding: return primaryColor
        case .lift: return .white.opacity(0.3)
        case .rest, .pause, .unknown: return .gray.opacity(0.3)
        }
    }
    
    var titleColor: Color {
        switch event.type {
        case .riding: return primaryColor
        default: return .gray
        }
    }
    
    var borderColor: Color {
        switch event.type {
        case .riding: return primaryColor.opacity(0.2)
        default: return .white.opacity(0.05)
        }
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? ""
    }
}

// MARK: - Slope Card (Compact)
struct SlopeCard: View {
    let name: String
    let count: Int
    
    var difficultyInfo: (color: Color, label: String) {
        if let slope = SlopeDatabase.shared.findSlope(byName: name) {
            let colorHex = slope.difficulty.colorHex
            return (Color(hex: colorHex), slope.difficulty.rawValue)
        }
        return (.gray, "Unknown")
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            // Top Row: Dot and Badge
            HStack {
                Circle()
                    .fill(difficultyInfo.color)
                    .frame(width: 8, height: 8)
                    .shadow(color: difficultyInfo.color.opacity(0.5), radius: 5)
                
                Spacer()
                
                // Difficulty Badge
                Text(difficultyInfo.label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(difficultyInfo.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(difficultyInfo.color.opacity(0.1))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(difficultyInfo.color.opacity(0.3), lineWidth: 0.5)
                    )
            }
            
            Spacer()
            
            // Slope Name
            Text(name)
                .font(.system(size: 16, weight: .bold)) // Larger font
                .foregroundColor(.white)
                .lineLimit(1)
            
            // Run Count
            Text("x\(count) RUNS")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.gray)
        }
        .padding(14)
        .frame(width: 140, height: 110) // Larger square-ish frame
        .background(Color(hex: "111111"))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

// IdentifiableURL
struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Extensions (Hex Color)
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}





// MARK: - Full Screen Map (Wrapper)
struct FullScreenMapView: View {
    @Environment(\.dismiss) var dismiss
    let coordinates: [CLLocationCoordinate2D]
    let speeds: [Double]
    let maxSpeed: Double
    let runStartIndices: [Int]
    @State var region: MKCoordinateRegion
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MapViewRepresentable(
                region: region,
                coordinates: coordinates,
                lineColor: UIColor(red: 107/255, green: 249/255, blue: 6/255, alpha: 1.0),
                runStartIndices: runStartIndices,
                speeds: speeds,
                maxSpeed: maxSpeed
            )
            .ignoresSafeArea()
            
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .shadow(radius: 5)
                    }
                    Spacer()
                }
                .padding()
                .padding(.top, 40)
                Spacer()
            }
        }
    }
}

// MARK: - Helper Structs (Restored)



struct MapViewRepresentable: UIViewRepresentable {
    let region: MKCoordinateRegion
    let coordinates: [CLLocationCoordinate2D]
    let lineColor: UIColor
    let runStartIndices: [Int]
    let speeds: [Double]
    let maxSpeed: Double
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true
        mapView.isZoomEnabled = true
        mapView.mapType = .standard
        mapView.overrideUserInterfaceStyle = .dark
        return mapView
    }
    
    func updateUIView(_ view: MKMapView, context: Context) {
        view.setRegion(region, animated: false)
        
        // Remove existing overlays
        let overlays = view.overlays
        view.removeOverlays(overlays)
        
        // Add Polylines
        
        var startIdx = 0
        let sortedIndices = runStartIndices.sorted()
        
        for (i, startIndex) in sortedIndices.enumerated() {
            let endIndex = (i + 1 < sortedIndices.count) ? sortedIndices[i+1] : coordinates.count
            
            if endIndex > startIndex {
                let segmentCoords = Array(coordinates[startIndex..<endIndex])
                if segmentCoords.count > 1 {
                    let polyline = MKPolyline(coordinates: segmentCoords, count: segmentCoords.count)
                    polyline.title = "Run" 
                    view.addOverlay(polyline)
                }
            }
            
            // Add Lift Line (Dashed)
            if i > 0 {
                let prevLastIdx = startIndex - 1
                if prevLastIdx >= 0 && prevLastIdx < coordinates.count && startIndex < coordinates.count {
                    let p1 = coordinates[prevLastIdx]
                    let p2 = coordinates[startIndex]
                    let liftPolyline = MKPolyline(coordinates: [p1, p2], count: 2)
                    liftPolyline.title = "Lift"
                    view.addOverlay(liftPolyline)
                }
            }
        }
        
        // Add Start/End annotations
        if let first = coordinates.first {
             let startAnnotation = MKPointAnnotation()
             startAnnotation.coordinate = first
             startAnnotation.title = "START"
             view.addAnnotation(startAnnotation)
        }
        
        if let last = coordinates.last {
             let endAnnotation = MKPointAnnotation()
             endAnnotation.coordinate = last
             endAnnotation.title = "FINISH"
             view.addAnnotation(endAnnotation)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewRepresentable
        
        init(_ parent: MapViewRepresentable) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                if polyline.title == "Lift" {
                    renderer.strokeColor = .white.withAlphaComponent(0.3)
                    renderer.lineWidth = 2
                    renderer.lineDashPattern = [2, 4]
                } else {
                    renderer.strokeColor = parent.lineColor
                    renderer.lineWidth = 4
                }
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            return nil
        }
    }
}
