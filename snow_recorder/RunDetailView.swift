import SwiftUI
import MapKit
import SwiftData
import Charts

struct RunDetailView: View {
    @Environment(\.dismiss) var dismiss
    let session: RunSession
    
    // State for Share Preview
    @State private var showSharePreview = false
    
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
                        
                        // Metrics Grid
                        metricsGrid
                        
                        // Performance Profile (Chart)
                        chartSection
                    }
                    .padding(.bottom, 100)
                }
            }
            
            // Floating Share Button
            VStack {
                Spacer()
                shareButton
            }
        }
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showSharePreview) {
            SharePreviewView(session: session)
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
            
            Button(action: { /* Share Action */ }) {
                Image(systemName: "square.and.arrow.up")
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
    
    private var mapSection: some View {
        ZStack {
            // Map with Route
            Map(coordinateRegion: .constant(mapRegion))
            .overlay(
                MapRouteOverlay(coordinates: routeCoordinates, color: primaryColor)
            )
            .disabled(true)
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

