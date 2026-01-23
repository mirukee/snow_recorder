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
    @State private var showFullScreenMap = false // Full Screen Map Overlay

    
    // Theme Colors
    let primaryColor = Color(hex: "6bf906")
    let backgroundDark = Color(hex: "121212")
    let surfaceDark = Color(hex: "1e1e1e")
    
    var body: some View {
        ZStack {
            backgroundDark.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Title & Date
                        titleSection
                        
                        // Map / Hero Section
                        mapSection
                        
                        // Slopes Ridden
                        if !session.riddenSlopes.isEmpty {
                            slopesRiddenSection
                        }
                        
                        // Timeline
                        if !session.timelineEvents.isEmpty {
                            timelineSection
                        }
                        
                        // Metrics Grid
                        metricsGrid
                        
                        // Performance Profile (Chart)
                        chartSection
                        
                        // Bottom Share Button
                        shareButton
                    }
                    .padding(.bottom, 40) // End of content padding
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
        // GPX Export Sheet (item 기반으로 URL이 확실히 전달되도록)
        .sheet(item: $gpxFileURL) { identifiableURL in
            ShareSheet(activityItems: [identifiableURL.url])
        }
        // 좌표 데이터 없을 때 알림
        .alert("GPX Export 불가", isPresented: $showNoDataAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("이 세션에는 GPS 경로 데이터가 없습니다.")
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
                .foregroundColor(primaryColor)
            
            Spacer()
            
            // GPX Export 버튼
            Button(action: { exportGPX() }) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
        }
        .padding()
        .background(backgroundDark.opacity(0.8))
    }
    
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(session.locationName)
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundColor(.white)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                
                Circle()
                    .fill(primaryColor)
                    .frame(width: 8, height: 8)
                    .padding(4)
                    .shadow(color: primaryColor.opacity(0.5), radius: 5)
            }
            .padding(.horizontal)
            
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(primaryColor)
                Text(session.startTime.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray)
                    .tracking(1)
            }
            .padding(.horizontal)
        }
        }

    
    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TIMELINE")
                .font(.system(size: 14, weight: .bold))
                .tracking(2)
                .foregroundColor(primaryColor)
                .padding(.horizontal)
            
            VStack(spacing: 0) {
                ForEach(Array(session.timelineEvents.enumerated()), id: \.element.id) { index, event in
                    TimelineRow(event: event, isLast: index == session.timelineEvents.count - 1, primaryColor: primaryColor)
                }
            }
            .padding(.horizontal)
            .background(Color.white.opacity(0.05))
            .cornerRadius(16)
            .padding(.horizontal)
        }
    }
    
    private var mapSection: some View {
        ZStack {
            // Map with Route
            Map(coordinateRegion: .constant(mapRegion))
            .overlay(
                // 히트맵 오버레이 (속도 데이터가 있을 경우 그라데이션, 없으면 단색)
                Group {
                    if !session.routeSpeeds.isEmpty {
                        GradientRouteOverlay(coordinates: routeCoordinates, speeds: session.routeSpeeds, maxSpeed: session.maxSpeed)
                    } else {
                        MapRouteOverlay(coordinates: routeCoordinates, color: primaryColor)
                    }
                }
            )
            .disabled(true)
            .onTapGesture {
                // 전체 화면 지도 보기
                showFullScreenMap = true
            }
            .grayscale(0.8)
            .colorMultiply(Color(white: 0.7))
            
            // Gradient Overlay
            LinearGradient(
                colors: [backgroundDark, .clear],
                startPoint: .bottom,
                endPoint: .center
            )
            
            // Overlay Badge
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "mountain.2")
                            .foregroundColor(primaryColor)
                        Text("HIGH1 RESORT")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                }
                Spacer()
            }
            .padding()
        }
        .frame(height: 300)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal)
        .shadow(color: .black.opacity(0.5), radius: 20)
        .onTapGesture {
            // 전체 화면 지도 보기
            showFullScreenMap = true
        }
    }
    
    // Convert stored coordinates to CLLocationCoordinate2D
    private var routeCoordinates: [CLLocationCoordinate2D] {
        session.routeCoordinates.compactMap { coords in
            guard coords.count == 2 else { return nil }
            return CLLocationCoordinate2D(latitude: coords[0], longitude: coords[1])
        }
    }
    
    // Calculate map region from route or use default
    private var mapRegion: MKCoordinateRegion {
        guard !routeCoordinates.isEmpty else {
            // Default to High1 Resort center
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.198, longitude: 128.825),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }
        
        // Calculate bounding box of route
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

    
    private var slopesRiddenSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(primaryColor)
                    .frame(width: 6, height: 6)
                Text("SLOPES RIDDEN")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .tracking(1)
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
            // Vertical Drop (Highlighted)
            VStack(alignment: .leading) {
                HStack {
                    Image(systemName: "arrow.down.to.line")
                        .foregroundColor(primaryColor)
                    Text("VERTICAL DROP")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(primaryColor)
                        .tracking(1)
                }
                Spacer()
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(Int(session.verticalDrop))")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: primaryColor.opacity(0.3), radius: 10)
                    Text("M")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(primaryColor)
                }
            }
            .padding(20)
            .frame(height: 130)
            .background(surfaceDark)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(primaryColor.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: primaryColor.opacity(0.1), radius: 10)
            
            // Max Speed
            metricCard(title: "MAX SPEED", value: String(format: "%.1f", session.maxSpeed), unit: "KM/H", icon: "speedometer")
            
            // Avg Speed
            smallMetricCard(title: "AVG SPEED", value: String(format: "%.1f", session.avgSpeed), unit: "KM/H", icon: "timer")
            
            // Distance
            smallMetricCard(title: "DISTANCE", value: String(format: "%.1f", session.distance / 1000.0), unit: "KM", icon: "ruler")
            
            // Duration
            smallMetricCard(title: "DURATION", value: formatDuration(session.duration), unit: "", icon: "clock")
            
            // Run Count
            smallMetricCard(title: "RUN COUNT", value: "\(session.runCount)", unit: "LAPS", icon: "figure.skiing.downhill")
        }
        .padding(.horizontal)
    }
    
    private var chartSection: some View {
        VStack {
            HStack {
                HStack {
                    Circle()
                        .fill(primaryColor)
                        .frame(width: 6, height: 6)
                    Text("PERFORMANCE PROFILE")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .tracking(1)
                }
                Spacer()
                HStack(spacing: 8) {
                    Text("ALTITUDE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(primaryColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(primaryColor.opacity(0.1))
                        .cornerRadius(4)
                    
                    Text("SPEED")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                }
            }
            .padding(.bottom, 20)
            
            // Dummy Chart Visualization (Since we don't store full history in session yet for chart)
            // In a real app, we would use session.altitudeHistory or similar logs.
            ZStack(alignment: .bottom) {
                // Approximate visual
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(0..<20) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(LinearGradient(colors: [primaryColor.opacity(0.8), primaryColor.opacity(0.1)], startPoint: .top, endPoint: .bottom))
                            .frame(height: CGFloat.random(in: 30...120))
                    }
                }
                .frame(maxWidth: .infinity)
                
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 80))
                    path.addCurve(to: CGPoint(x: 350, y: 80), control1: CGPoint(x: 100, y: 0), control2: CGPoint(x: 250, y: 150))
                }
                .stroke(primaryColor, lineWidth: 2)
                .shadow(color: primaryColor, radius: 5)
            }
            .frame(height: 150)
            .clipped()
            
            HStack {
                Text(session.startTime.formatted(date: .omitted, time: .shortened))
                Spacer()
                Text(session.endTime.formatted(date: .omitted, time: .shortened))
            }
            .font(.caption2)
            .foregroundColor(.gray)
            .padding(.top, 8)
        }
        .padding(24)
        .background(surfaceDark.opacity(0.4))
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal)
    }
    
    private var shareButton: some View {
        Button(action: { showSharePreview = true }) {
            HStack {
                Image(systemName: "square.and.arrow.up")
                Text("SHARE SESSION")
            }
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(primaryColor)
            .cornerRadius(28)
            .shadow(color: primaryColor.opacity(0.4), radius: 20)
        }
        .padding(.horizontal)
        .padding(.bottom, 110)
    }
    
    // MARK: - Helper Views & Methods
    
    private func metricCard(title: String, value: String, unit: String, icon: String) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.gray)
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.gray)
                    .tracking(1)
            }
            Spacer()
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                Text(unit)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .frame(height: 130)
        .background(surfaceDark.opacity(0.5))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func smallMetricCard(title: String, value: String, unit: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.gray)
                    .tracking(1)
                Spacer()
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                }
            }
        }
        .padding()
        .frame(height: 80)
        .background(Color.white.opacity(0.05))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "00:00"
    }
    
    /// GPX 파일 생성 및 공유 시트 표시
    private func exportGPX() {
        // 좌표 데이터가 없으면 알림
        guard !session.routeCoordinates.isEmpty else {
            showNoDataAlert = true
            return
        }
        
        // GPX 파일 생성
        if let url = GPXExporter.saveToFile(session: session) {
            gpxFileURL = IdentifiableURL(url: url)
        }
    }
}

/// URL을 Identifiable로 래핑 (sheet(item:) 사용을 위해)
struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Slope Card View
struct SlopeCard: View {
    let name: String
    let count: Int
    
    // Computed difficulty info
    var difficultyInfo: (color: Color, label: String) {
        if let slope = SlopeDatabase.shared.findSlope(byName: name) {
            let colorHex = slope.difficulty.colorHex
            return (Color(hex: colorHex), slope.difficulty.rawValue) // Using rawValue as label (Ex: "초급")
        }
        return (.gray, "Unknown")
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Circle()
                    .fill(difficultyInfo.color)
                    .frame(width: 8, height: 8)
                    .shadow(color: difficultyInfo.color.opacity(0.5), radius: 5)
                
                Spacer()
                
                Text(difficultyInfo.label)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(difficultyInfo.color.opacity(0.1))
                    .foregroundColor(difficultyInfo.color)
                    .cornerRadius(4)
            }
            
            Spacer()
            
            Text(name)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
            
            Text("x\(count) RUNS")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.gray)
        }
        .padding(16)
        .frame(width: 140, height: 120)
        .background(Color(hex: "1e1e1e"))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        // Hover effect simulation with shadow
        .shadow(color: .black.opacity(0.3), radius: 10)
    }
}

// MARK: - Extensions

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

// MARK: - Map Route Overlay (Polyline)

struct MapRouteOverlay: View {
    let coordinates: [CLLocationCoordinate2D]
    let color: Color
    
    var body: some View {
        GeometryReader { geometry in
            if coordinates.count >= 2 {
                Path { path in
                    let points = coordinates.map { coord -> CGPoint in
                        projectToView(coord, in: geometry.size)
                    }
                    path.move(to: points[0])
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .shadow(color: color.opacity(0.5), radius: 4)
            }
        }
    }
    
    // Project geographic coordinates to view coordinates
    private func projectToView(_ coord: CLLocationCoordinate2D, in size: CGSize) -> CGPoint {
        guard coordinates.count >= 2 else { return .zero }
        
        let lats = coordinates.map { $0.latitude }
        let lons = coordinates.map { $0.longitude }
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        
        // Add padding
        let latRange = max(maxLat - minLat, 0.001)
        let lonRange = max(maxLon - minLon, 0.001)
        let padding: CGFloat = 0.15
        
        // Normalize to 0-1 range with padding
        let normalizedX = CGFloat((coord.longitude - minLon) / lonRange) * (1 - 2 * padding) + padding
        let normalizedY = 1 - (CGFloat((coord.latitude - minLat) / latRange) * (1 - 2 * padding) + padding)
        
        return CGPoint(x: normalizedX * size.width, y: normalizedY * size.height)
    }
}

// MARK: - Gradient Route Overlay (Heatmap)

struct GradientRouteOverlay: View {
    let coordinates: [CLLocationCoordinate2D]
    let speeds: [Double]
    let maxSpeed: Double
    
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard coordinates.count >= 2 else { return }
                
                // Project all points once
                let points = projectCoordinates(coordinates, to: size)
                
                // Draw segments
                for i in 0..<(points.count - 1) {
                    let startPoint = points[i]
                    let endPoint = points[i+1]
                    
                    // Determine color based on speed at this segment
                    // Use index i if runs 1:1, or ratio mapping if counts differ
                    let speed = getSpeed(at: i, totalPoints: points.count)
                    let color = speedToColor(speed)
                    
                    var path = Path()
                    path.move(to: startPoint)
                    path.addLine(to: endPoint)
                    
                    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }
    
    // Safely get speed for a segment index
    private func getSpeed(at index: Int, totalPoints: Int) -> Double {
        if speeds.isEmpty { return 0 }
        if speeds.count == totalPoints {
            // Ideal 1:1 case (excluding last point speed if count matches point count)
            return speeds[min(index, speeds.count - 1)]
        } else {
            // Ratio mapping if arrays differ (e.g. filtered coordinates vs raw speeds)
            // Ideally they should match from RunSession logic, but safety first.
            let ratio = Double(index) / Double(totalPoints - 1)
            let speedIndex = Int(ratio * Double(speeds.count - 1))
            return speeds[min(speedIndex, speeds.count - 1)]
        }
    }
    
    private func speedToColor(_ speed: Double) -> Color {
        // 0 ~ MAX -> Green(Slow) ~ Yellow ~ Red(Fast)
        // Adjust threshold: Green (<33%), Yellow (33-66%), Red (>66%) or Gradient
        let ratio = maxSpeed > 0 ? speed / maxSpeed : 0
        
        // Custom HSB Interpolation for smoother gradient
        // Hue: 0.33 (Green) -> 0.0 (Red)
        // Saturation: 1.0
        // Brightness: 1.0
        let hue = 0.33 - (0.33 * min(max(ratio, 0), 1))
        return Color(hue: hue, saturation: 1.0, brightness: 1.0)
    }
    
    private func projectCoordinates(_ coords: [CLLocationCoordinate2D], to size: CGSize) -> [CGPoint] {
        guard !coords.isEmpty else { return [] }
        
        let lats = coords.map { $0.latitude }
        let lons = coords.map { $0.longitude }
        let minLat = lats.min()!
        let maxLat = lats.max()!
        let minLon = lons.min()!
        let maxLon = lons.max()!
        
        let latRange = max(maxLat - minLat, 0.001)
        let lonRange = max(maxLon - minLon, 0.001)
        
        // Map padding
        let padding: CGFloat = 0.1
        let availableWidth = size.width * (1 - 2 * padding)
        let availableHeight = size.height * (1 - 2 * padding)
        
        return coords.map { coord in
            let normalizedX = CGFloat((coord.longitude - minLon) / lonRange)
            let normalizedY = CGFloat((coord.latitude - minLat) / latRange)
            
            let x = padding * size.width + normalizedX * availableWidth
            // Latitude increases upwards, screen Y increases downwards
            let y = size.height - (padding * size.height + normalizedY * availableHeight)
            
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - Full Screen Map View

// MARK: - Full Screen Map View (MKMapView Wrapper)

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
            
            // MKMapView Wrapper
            MapViewRepresentable(
                region: region,
                coordinates: coordinates,
                lineColor: UIColor(red: 107/255, green: 249/255, blue: 6/255, alpha: 1.0), // Neon Green
                runStartIndices: runStartIndices,
                speeds: speeds,
                maxSpeed: maxSpeed
            )
            .ignoresSafeArea()
            
            // Controls
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

// SwiftUI Wrapper for MKMapView
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
        mapView.region = region
        mapView.showsUserLocation = false
        mapView.mapType = .standard // Simplified Map View
        mapView.isPitchEnabled = true
        
        if coordinates.count >= 2 {
            // Segmented Rendering Logic
            let indices = runStartIndices + [coordinates.count] // Add end index sentinel
            
            for i in 0..<(indices.count - 1) {
                let startIdx = indices[i]
                let endIdx = indices[i+1]
                
                // 1. Solid Run Line (startIdx ~ endIdx)
                let runSegment = Array(coordinates[startIdx..<endIdx])
                if runSegment.count >= 2 {
                    let runPolyline = RunPolyline(coordinates: runSegment, count: runSegment.count)
                    
                    // Safety: Extract speeds for this segment if available
                    if speeds.count == coordinates.count {
                         let paramStartIndex = max(0, min(startIdx, speeds.count - 1))
                         let paramEndIndex = max(0, min(endIdx, speeds.count))
                         if paramStartIndex < paramEndIndex {
                            runPolyline.speeds = Array(speeds[paramStartIndex..<paramEndIndex])
                         }
                    } else if !speeds.isEmpty {
                        // Fallback ratio-based mapping if counts differ
                        let totalPoints = coordinates.count
                        let segmentSpeeds = (startIdx..<endIdx).map { idx -> Double in
                             let ratio = Double(idx) / Double(totalPoints - 1)
                             let speedIndex = Int(ratio * Double(speeds.count - 1))
                             return speeds[min(speedIndex, speeds.count - 1)]
                        }
                        runPolyline.speeds = segmentSpeeds
                    }
                    
                    runPolyline.maxSpeed = maxSpeed
                    mapView.addOverlay(runPolyline)
                }
                
                // 2. Dotted Lift Line (Connect previous run's end to current run's start)
                // Skip for the first run (i=0) as there's no previous run to connect from
                if i > 0 {
                    let prevEndIdx = indices[i] - 1 // End of previous run
                    let currStartIdx = indices[i]   // Start of current run
                    
                    // Safety check
                    if prevEndIdx >= 0 && currStartIdx < coordinates.count {
                         let liftSegment = [coordinates[prevEndIdx], coordinates[currStartIdx]]
                         let liftPolyline = LiftPolyline(coordinates: liftSegment, count: liftSegment.count)
                         mapView.addOverlay(liftPolyline)
                    }
                }
            }
            
            // Fallback for simple case (if only 1 run, indices might be just [0, count])
            // The loop above handles it (i=0, loop runs once for solid line).
        }
        
        // Add Start/End Pins (Annotate even if just 1 point)
        if let start = coordinates.first {
            let startAnnotation = MKPointAnnotation()
            startAnnotation.coordinate = start
            startAnnotation.title = "Start"
            mapView.addAnnotation(startAnnotation)
        }
        
        if let end = coordinates.last, coordinates.count > 1 {
            let endAnnotation = MKPointAnnotation()
            endAnnotation.coordinate = end
            endAnnotation.title = "Finish"
            mapView.addAnnotation(endAnnotation)
        }
        
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        // View updates if needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewRepresentable
        
        init(parent: MapViewRepresentable) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let runPolyline = overlay as? RunPolyline {
                // If speeds are available, use Gradient Renderer
                if let speeds = runPolyline.speeds, !speeds.isEmpty, runPolyline.maxSpeed > 0 {
                    let renderer = MKGradientPolylineRenderer(polyline: runPolyline)
                    renderer.lineWidth = 4
                    
                    // Generate colors for each point
                    let colors = speeds.map { speed -> UIColor in
                        let ratio = speed / runPolyline.maxSpeed
                        // Green(0.33) -> Red(0.0)
                        let hue = 0.33 - (0.33 * min(max(ratio, 0), 1.0))
                        return UIColor(hue: hue, saturation: 1.0, brightness: 1.0, alpha: 1.0)
                    }
                    
                    // Locations (0.0 to 1.0)
                    let locations = speeds.indices.map { index -> CGFloat in
                        // Safe division
                        return CGFloat(Double(index) / Double(max(speeds.count - 1, 1)))
                    }
                    
                    renderer.setColors(colors, locations: locations)
                    return renderer
                } else {
                    // Fallback to solid color
                    let renderer = MKPolylineRenderer(polyline: runPolyline)
                    renderer.strokeColor = parent.lineColor
                    renderer.lineWidth = 4
                    return renderer
                }
            } else if let liftPolyline = overlay as? LiftPolyline {
                let renderer = MKPolylineRenderer(polyline: liftPolyline)
                renderer.strokeColor = .white
                renderer.lineWidth = 2
                renderer.lineDashPattern = [2, 4] // [Line, Gap]
                renderer.alpha = 0.7
                return renderer
            }
            return MKOverlayRenderer()
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let identifier = "Pin"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
            
            if annotationView == nil {
                annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = true
            } else {
                annotationView?.annotation = annotation
            }
            
            if annotation.title == "Start" {
                annotationView?.markerTintColor = .green
                annotationView?.glyphImage = UIImage(systemName: "flag.fill")
            } else if annotation.title == "Finish" {
                annotationView?.markerTintColor = .red
                annotationView?.glyphImage = UIImage(systemName: "flag.checkered")
            }
            
            return annotationView
        }
    }
}

// Custom Polyline Classes to distinguish types
class RunPolyline: MKPolyline {
    var speeds: [Double]?
    var maxSpeed: Double = 0.0
}
class LiftPolyline: MKPolyline {}
// MARK: - Helper Views for Timeline

struct TimelineRow: View {
    let event: RunSession.TimelineEvent
    let isLast: Bool
    let primaryColor: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Time Column
            VStack(alignment: .trailing) {
                Text(event.startTime.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            .frame(width: 60, alignment: .trailing)
            .padding(.top, 6)
            
            // Icon & Line Column
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "1e1e1e"))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: iconName)
                                .font(.system(size: 14))
                                .foregroundColor(iconColor)
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }
                
                if !isLast {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 2)
                        .frame(minHeight: 30) // Minimum height for connector
                }
            }
            
            // Content Column
            VStack(alignment: .leading, spacing: 4) {
                Text(event.detail)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(formatDuration(event.duration))
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Spacer().frame(height: 20)
            }
            .padding(.top, 4)
            
            Spacer()
        }
    }
    
    var iconName: String {
        switch event.type {
        case .riding: return "figure.skiing.downhill"
        case .lift: return "cablecar"
        case .rest: return "cup.and.saucer.fill"
        case .pause: return "pause.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
    
    var iconColor: Color {
        switch event.type {
        case .riding: return primaryColor
        case .lift: return .orange
        case .rest: return .blue
        case .pause: return .gray
        case .unknown: return .gray
        }
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        return minutes > 0 ? "\(minutes) min" : "< 1 min"
    }
}
