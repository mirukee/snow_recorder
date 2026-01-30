import SwiftUI
import Charts
import SwiftData
import CoreLocation

struct RunAnalysisView: View {
    @Environment(\.dismiss) var dismiss
    let runMetric: RunSession.RunMetric
    let locationName: String
    let telemetryPoints: [CLLocation]
    let speedChartPoints: [Point]
    let gForceChartPoints: [Point]
    let maxGPoint: Point?
    let avgGForce: Double
    let maxBankAngle: Double // New property
    
    init(runMetric: RunSession.RunMetric, locationName: String, telemetryPoints: [CLLocation]? = nil, gForcePoints: [Point]? = nil) {
        self.runMetric = runMetric
        self.locationName = locationName
        self.telemetryPoints = telemetryPoints ?? []
        
        // 1. Process Speed Points (Sorted & Stable)
        let rawSpeedPoints = (telemetryPoints ?? [])
            .map { Point(x: $0.timestamp, y: $0.speed < 0 ? 0 : $0.speed * 3.6) }
            .sorted { $0.x < $1.x }
        
        var uniqueSpeed: [Date: Double] = [:]
        for p in rawSpeedPoints { uniqueSpeed[p.x] = p.y }
        self.speedChartPoints = uniqueSpeed.keys.sorted().map { Point(x: $0, y: uniqueSpeed[$0]!) }
        
        // 2. Process G-Force Points (Downsampled for density)
        let minInterval: TimeInterval = 0.2
        var processedGPoints: [Point] = []
        var absoluteMaxPoint: Point? = nil
        
        if let gPoints = gForcePoints, !gPoints.isEmpty {
            let sortedG = gPoints.sorted { $0.x < $1.x }
            var uniqueG: [Date: Double] = [:]
            for p in sortedG { uniqueG[p.x] = p.y }
            let deduplicated = uniqueG.keys.sorted().map { Point(x: $0, y: uniqueG[$0]!) }
            
            // Find absolute max before downsampling
            absoluteMaxPoint = deduplicated.max(by: { $0.y < $1.y })
            
            if let first = deduplicated.first {
                processedGPoints.append(first)
                var lastTime = first.x
                for p in deduplicated.dropFirst() {
                    // Always include the absolute max point if we encounter it? 
                    // Simpler: Check at the end.
                    if p.x.timeIntervalSince(lastTime) >= minInterval {
                        processedGPoints.append(p)
                        lastTime = p.x
                    }
                }
            }
        } else {
            // Fallback (simulated)
            var lastTime: Date? = nil
            let noisyPoints = self.speedChartPoints.compactMap { sp -> Point? in
                if let last = lastTime, sp.x.timeIntervalSince(last) < minInterval { return nil }
                lastTime = sp.x
                
                let seed = sp.x.timeIntervalSince1970
                let noise = 0.85 + (abs(sin(seed)) * 0.15)
                return Point(x: sp.x, y: ((sp.y / 50.0) * runMetric.maxGForce) * noise)
            }
            processedGPoints = noisyPoints
            absoluteMaxPoint = processedGPoints.max(by: { $0.y < $1.y })
        }
        
        // Ensure absolute max is included (if exists and was skipped by downsampling)
        if let maxP = absoluteMaxPoint, !processedGPoints.contains(where: { $0.x == maxP.x }) {
            processedGPoints.append(maxP)
            processedGPoints.sort { $0.x < $1.x }
        }
        
        // 3. Normalize/Scale to match runMetric.maxGForce
        // Ensure the graph peak matches the reported metric EXACTLY to avoid user confusion
        if let currentMax = processedGPoints.max(by: { $0.y < $1.y })?.y, currentMax > 0 {
             if runMetric.maxGForce > currentMax {
                 let scaleFactor = runMetric.maxGForce / currentMax
                 processedGPoints = processedGPoints.map { Point(x: $0.x, y: $0.y * scaleFactor) }
             }
        }
        
        self.gForceChartPoints = processedGPoints
        self.maxGPoint = processedGPoints.max(by: { $0.y < $1.y })

        // Calculate Avg G-Force
        if !processedGPoints.isEmpty {
            let total = processedGPoints.reduce(0) { $0 + $1.y }
            self.avgGForce = total / Double(processedGPoints.count)
            
            // Calculate Bank Angle (Top 10% Sustained G)
            let sortedG = processedGPoints.map { $0.y }.sorted(by: >)
            let top10Count = max(1, Int(Double(sortedG.count) * 0.1))
            let top10Values = sortedG.prefix(top10Count)
            let sustainedMaxG = top10Values.reduce(0, +) / Double(top10Values.count)
            
            // Physics: angle = acos(1 / G)
            let clampedG = max(1.0, sustainedMaxG)
            let radians = acos(1.0 / clampedG)
            var degrees = radians * 180.0 / .pi
            
            // Safety Clamp (e.g. max 80 degrees)
            if degrees > 80 { degrees = 80 }
            self.maxBankAngle = degrees
        } else {
            self.avgGForce = 0.0
            self.maxBankAngle = 0.0
        }
    }
    
    // Theme Colors
    let primaryColor = Color(hex: "6bf906")
    let cyanColor = Color(hex: "06b6d4") // Cyan-500
    let purpleColor = Color(hex: "a855f7") // Purple-500
    let redColor = Color(hex: "ef4444")   // Red-500
    let backgroundDark = Color.black
    let surfaceCard = Color(hex: "111111") // Zinc-900 equivalent
    
    // State
    @State private var selectedTab: AnalysisTab = .edge
    @State private var selectedTime: Date?
    
    enum AnalysisTab {
        case flow, edge
    }
    
    var body: some View {
        ZStack {
            backgroundDark.ignoresSafeArea()
            
            // Background Effects
            VStack {
                HStack {
                    Spacer()
                    Circle()
                        .fill(primaryColor.opacity(0.05))
                        .frame(width: 300, height: 300)
                        .blur(radius: 100)
                        .offset(x: 100, y: -100)
                }
                Spacer()
                HStack {
                    Circle()
                        .fill(Color.blue.opacity(0.05))
                        .frame(width: 300, height: 300)
                        .blur(radius: 120)
                        .offset(x: -100, y: 100)
                    Spacer()
                }
            }
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // 1. Dual Gauges
                        gaugesSection
                            .padding(.top, 20)
                        
                        // 2. Tab Control
                        menuControl
                        
                        // 3. Tab Content
                        if selectedTab == .edge {
                            edgeContent
                        } else {
                            flowContent
                        }
                        
                        // 4. Telemetry Graph (Moved to Edge Tab as G-Force only)
                        // telemetryGraphSection removed from here
                        
                        // 5. Share Button (Footer)
                        shareButton
                            .padding(.top, 40)
                            .padding(.bottom, 60)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
    }
    
    // MARK: - Components
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("RUN \(runMetric.runNumber)")
                        .font(.system(size: 20, weight: .bold)) // Space Grotesk style
                        .foregroundColor(.white)
                    Text("/")
                        .font(.system(size: 20, weight: .light))
                        .foregroundColor(.gray)
                    Text(locationName.uppercased())
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(primaryColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: primaryColor, radius: 5)
                    Text("PRO ANALYSIS")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundColor(primaryColor)
                }
            }
            
            Spacer()
            
            // Time Capsule
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 12))
                    .foregroundColor(primaryColor)
                Text(formatRunTimeRange(runMetric.startTime, runMetric.endTime))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(primaryColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(primaryColor.opacity(0.1))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(primaryColor.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: primaryColor.opacity(0.2), radius: 8)
            
            // Close Button
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .padding(.leading, 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.black.opacity(0.8))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.white.opacity(0.1)),
            alignment: .bottom
        )
    }
    
    private var gaugesSection: some View {
        HStack(spacing: 20) {
            // Edge Gauge
            GaugeView(
                score: runMetric.edgeScore,
                label: "EDGE",
                color: primaryColor,
                icon: "waveform.path.ecg"
            )
            
            // Flow Gauge
            GaugeView(
                score: runMetric.flowScore,
                label: "FLOW",
                color: primaryColor,
                icon: "wind"
            )
        }
        .padding(.horizontal, 20)
    }
    
    private var menuControl: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let selectedWidth = totalWidth * 0.7
            let unselectedWidth = totalWidth * 0.3
            
            HStack(spacing: 0) {
                Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedTab = .edge }}) {
                    ZStack {
                        if selectedTab == .edge {
                            Capsule()
                                .fill(primaryColor)
                                .shadow(color: primaryColor.opacity(0.5), radius: 10)
                                .matchedGeometryEffect(id: "TabBg", in: namespace)
                        }
                        Text("EDGE")
                            .font(.system(size: 14, weight: .black))
                            .tracking(2)
                            .foregroundColor(selectedTab == .edge ? .black : .white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(width: selectedTab == .edge ? selectedWidth : unselectedWidth, height: 48)
                }
                
                Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedTab = .flow }}) {
                    ZStack {
                        if selectedTab == .flow {
                            Capsule()
                                .fill(primaryColor)
                                .shadow(color: primaryColor.opacity(0.5), radius: 10)
                                .matchedGeometryEffect(id: "TabBg", in: namespace)
                        }
                        Text("FLOW")
                            .font(.system(size: 14, weight: .black))
                            .tracking(2)
                            .foregroundColor(selectedTab == .flow ? .black : .white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(width: selectedTab == .flow ? selectedWidth : unselectedWidth, height: 48)
                }
            }
        }
        .frame(height: 48) // Fix height for GeometryReader
        .padding(4)
        .background(Color.white.opacity(0.05))
        .cornerRadius(30)
        .overlay(
            Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal, 24)
    }
    @Namespace private var namespace
    
    // MARK: - Tab Contents
    
    private var flowContent: some View {
        VStack(spacing: 24) {
            // Stability Meter
            VStack(spacing: 12) {
                HStack {
                    Label("STABILITY", systemImage: "equalizer")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.gray)
                    Spacer()
                    Text(String(format: "%.0f%% STABLE", (runMetric.flowBreakdown?.avgStability ?? 0) * 100))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(primaryColor)
                }
                
                StabilityBar(stablePercentage: runMetric.flowBreakdown?.avgStability ?? 0.8)
                    .frame(height: 32)
            }
            .padding(.horizontal, 20)
            
            // Penalty Log (If any penalties exist)
            let hardBrakes = runMetric.flowBreakdown?.hardBrakeCount ?? 0
            let chatterEvents = runMetric.flowBreakdown?.chatterEventCount ?? 0
            
            if hardBrakes > 0 || chatterEvents > 0 {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(redColor)
                        Text("PENALTY LOG")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 20)
                    
                    VStack(spacing: 12) {
                        if hardBrakes > 0 {
                            PenaltyRow(
                                title: "HARD BRAKE",
                                time: "Detected", // We could pass specific events if available
                                points: Int(runMetric.flowBreakdown?.brakePenalty ?? 0),
                                icon: "exclamationmark.circle.fill",
                                color: redColor
                            )
                        }
                        
                        if chatterEvents > 0 {
                            PenaltyRow(
                                title: "CHATTER / VIBRATION",
                                time: "Detected",
                                points: Int(runMetric.flowBreakdown?.chatterPenalty ?? 0),
                                icon: "skis.fill",
                                color: Color.gray
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                }
            } else {
                 VStack(spacing: 12) {
                     Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(primaryColor)
                     Text("NO PENALTIES")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.gray)
                 }
                 .frame(maxWidth: .infinity)
                 .padding(20)
            }
        }
    }
    
    private var edgeContent: some View {
        VStack(spacing: 24) {
            // 1. Carving Precision (Large Card)
            CarvingPrecisionCard(
                tier2Percentage: runMetric.edgeBreakdown?.tier2Ratio ?? 0.0,
                tier2Time: "Tier 2",
                primaryColor: primaryColor
            )
            .padding(.horizontal, 20)
            
            // 2. Grid Layout (Max G & Avg G)
            HStack(spacing: 16) {
                // Max G-Force (Square, Radar Animation)
                MaxGForceCard(maxG: runMetric.maxGForce, primaryColor: primaryColor)
                
                // Avg G-Force (Square, matching height)
                AvgGForceCard(avgG: avgGForce, primaryColor: primaryColor)
            }
            .padding(.horizontal, 20)
            
            // 3. Bank Angle (Full Width)
            BankAngleCard(angle: maxBankAngle, primaryColor: primaryColor)
                .padding(.horizontal, 20)
            
            // 4. Turn Symmetry (Full Width)
            let turnRatio = normalizedTurnRatio(left: runMetric.leftTurnRatio, right: runMetric.rightTurnRatio)
            TurnSymmetryCard(
                leftRatio: turnRatio.left,
                rightRatio: turnRatio.right,
                primaryColor: primaryColor,
                purpleColor: purpleColor,
                cyanColor: cyanColor
            )
                .padding(.horizontal, 20)
            
            // 4. G-Force Graph
            gForceGraphSection
        }
    }
    
    @State private var selectedDate: Date?
    @State private var selectedGValue: Double?
    
    // ... (existing properties)

    // ... (inside body or gForceGraphSection header)
    
    private var gForceGraphSection: some View {
        let gForceGap = telemetryGapThreshold(for: gForceChartPoints)
        let gForceSegments = splitTelemetrySegments(gForceChartPoints, gap: gForceGap)
        
        return VStack(spacing: 16) {
            // Header
            HStack {
                if let selectedG = selectedGValue {
                    Text("G-FORCE: \(String(format: "%.2f G", selectedG))")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(2)
                        .foregroundColor(purpleColor)
                } else {
                    Text("G-FORCE ANALYSIS")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(2)
                        .foregroundColor(.gray)
                }
                Spacer()
                
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Circle().fill(purpleColor).frame(width: 6, height: 6)
                        Text("G-FORCE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(purpleColor)
                    }
                }
            }
            .padding(.horizontal, 20)
            
            // Graph Container
            VStack {
                 if gForceChartPoints.isEmpty {
                     Text("No G-Force Data")
                        .foregroundColor(.gray)
                        .padding(40)
                 } else {
                     gForceChartView(segments: gForceSegments)
                 }
            }
        }
        .padding(.vertical, 20)
        .background(Color(hex: "050505"))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.white.opacity(0.1)),
            alignment: .top
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.white.opacity(0.1)),
            alignment: .bottom
        )
    }

    private func gForceChartView(segments: [[Point]]) -> some View {
        Chart {
            // G-Force Line (Dashed Purple, slightly offset in scaling for clarity)
            ForEach(Array(segments.enumerated()), id: \.offset) { segmentIndex, segment in
                ForEach(segment) { point in
                    LineMark(
                        x: .value("Time", point.x),
                        y: .value("G-Force", (point.y * 25) + 5),
                        series: .value("GForceSegment", segmentIndex)
                    )
                    .foregroundStyle(purpleColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                    .interpolationMethod(.monotone)
                }
            }
            
            // Max G Indicator (Persistent)
            if let maxP = maxGPoint {
                PointMark(
                    x: .value("Max Time", maxP.x),
                    y: .value("Max G", (maxP.y * 25) + 5)
                )
                .foregroundStyle(primaryColor) // Use Green for Max/Best
                .symbolSize(40)
                .annotation(position: .top) {
                    Text(String(format: "MAX %.2fG", maxP.y))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(primaryColor)
                        .padding(2)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                }
            }
            
            // Selection Indicator
            if let selDate = selectedDate, let selG = selectedGValue {
                RuleMark(x: .value("Selected Time", selDate))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                
                PointMark(
                    x: .value("Selected Time", selDate),
                    y: .value("Selected G", (selG * 25) + 5)
                )
                .foregroundStyle(Color.white)
                .symbolSize(50)
            }
        }
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) {
                AxisValueLabel(format: .dateTime.minute().second())
                    .foregroundStyle(Color.gray)
            }
        }
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let location = value.location
                                if let date: Date = proxy.value(atX: location.x) {
                                    // Find nearest point
                                    if let nearest = gForceChartPoints.min(by: { abs($0.x.timeIntervalSince(date)) < abs($1.x.timeIntervalSince(date)) }) {
                                        
                                        // Haptic only on change (simple check)
                                        if self.selectedDate != nearest.x {
                                            let impact = UISelectionFeedbackGenerator()
                                            impact.selectionChanged()
                                        }
                                        
                                        self.selectedDate = nearest.x
                                        self.selectedGValue = nearest.y
                                    }
                                }
                            }
                            .onEnded { _ in
                                self.selectedDate = nil
                                self.selectedGValue = nil
                            }
                    )
            }
        }
        .frame(height: 200)
        .padding(.horizontal, 10)
    }
    
    private func splitTelemetrySegments(_ points: [Point], gap: TimeInterval) -> [[Point]] {
        guard points.count > 1 else { return points.isEmpty ? [] : [points] }
        
        var segments: [[Point]] = []
        var current: [Point] = [points[0]]
        
        for index in 1..<points.count {
            let previous = points[index - 1]
            let currentPoint = points[index]
            if currentPoint.x.timeIntervalSince(previous.x) > gap {
                segments.append(current)
                current = [currentPoint]
            } else {
                current.append(currentPoint)
            }
        }
        
        if !current.isEmpty {
            segments.append(current)
        }
        
        return segments
    }
    
    private func telemetryGapThreshold(for points: [Point], minGap: TimeInterval = 6.0, multiplier: Double = 3.0) -> TimeInterval {
        guard points.count > 2 else { return minGap }
        
        var deltas: [TimeInterval] = []
        deltas.reserveCapacity(points.count - 1)
        for index in 1..<points.count {
            let delta = points[index].x.timeIntervalSince(points[index - 1].x)
            if delta > 0 {
                deltas.append(delta)
            }
        }
        
        guard !deltas.isEmpty else { return minGap }
        
        deltas.sort()
        let median: TimeInterval
        if deltas.count % 2 == 0 {
            let mid = deltas.count / 2
            median = (deltas[mid - 1] + deltas[mid]) / 2
        } else {
            median = deltas[deltas.count / 2]
        }
        
        return max(minGap, median * multiplier)
    }
    
    private var shareButton: some View {
        Button(action: {
            // Share Action
        }) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .bold))
                Text("SHARE REPORT")
                    .font(.system(size: 14, weight: .bold))
                    .tracking(2)
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(colors: [.white, .gray], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .cornerRadius(28)
            .shadow(color: .white.opacity(0.2), radius: 10)
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - Helpers
    private func formatRunTimeRange(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
    
    private func normalizedTurnRatio(left: Double, right: Double) -> (left: Double, right: Double) {
        let safeLeft = max(0.0, min(1.0, left))
        let safeRight = max(0.0, min(1.0, right))
        let total = safeLeft + safeRight
        guard total > 0 else {
            return (0.5, 0.5)
        }
        return (safeLeft / total, safeRight / total)
    }

    // Data Models
    struct Point: Identifiable {
        let id = UUID()
        let x: Date
        let y: Double
    }
}

// MARK: - Subcomponents

struct GaugeView: View {
    let score: Int
    let label: String
    let color: Color
    let icon: String
    
    var body: some View {
        ZStack {
            // Background Ring
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 8)
            
            // Progress Ring
            Circle()
                .trim(from: 0, to: CGFloat(score) / 1000.0)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.6), radius: 8)
            
            // Content
            VStack(spacing: 4) {
                Text("\(score)")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.gray)
            }
            
            // Decorative Inner
            Circle()
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                .padding(12)
        }
        .frame(height: 140)
    }
}

struct StabilityBar: View {
    let stablePercentage: CGFloat
    let stableColor = Color(hex: "6bf906")
    let chatterColor = Color(hex: "7f1d1d") // Red-900ish
    
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                // Stable Part
                ZStack(alignment: .trailing) {
                    Rectangle()
                        .fill(
                            LinearGradient(colors: [stableColor.opacity(0.8), stableColor], startPoint: .leading, endPoint: .trailing)
                        )
                    // Dot Pattern
                    Image(systemName: "circle.grid.2x2.fill")
                        .resizable(resizingMode: .tile)
                        .foregroundColor(.white.opacity(0.2))
                        .frame(width: 40)
                }
                .frame(width: geo.size.width * stablePercentage)
                
                // Chatter Part
                ZStack {
                    Rectangle()
                        .fill(chatterColor.opacity(0.4))
                    // Hatch Pattern (Simulated with Path or Image)
                    HStack(spacing: 4) {
                        ForEach(0..<10) { _ in
                             Rectangle()
                                .fill(Color.red.opacity(0.3))
                                .frame(width: 1)
                                .rotationEffect(.degrees(45))
                        }
                    }
                    .clipped()
                }
                .frame(width: geo.size.width * (1 - stablePercentage))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct PenaltyRow: View {
    let title: String
    let time: String
    let points: Int
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(color.opacity(0.1))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(color)
                }
                .shadow(color: color.opacity(0.3), radius: 4)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold)) // Space Grotesk
                        .foregroundColor(points < -30 ? color : .gray)
                    Text(time)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.6))
                }
            }
            
            Spacer()
            
            Text("\(points)pts")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(points < -30 ? color.opacity(0.8) : .gray)
        }
        .padding(12)
        .background(points < -30 ? color.opacity(0.05) : Color.white.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(points < -30 ? color.opacity(0.2) : Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}


// MARK: - Edge Analysis Components

struct CarvingPrecisionCard: View {
    let tier2Percentage: Double
    let tier2Time: String
    let primaryColor: Color
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            Text("CARVING PRECISION")
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundColor(.gray)
                .padding(.top, 24)
            
            // Main Content
            ZStack {
                // Background Circle
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 24)
                    .frame(width: 180, height: 180)
                
                // Progress Circle
                Circle()
                    .trim(from: 0, to: tier2Percentage)
                    .stroke(
                        primaryColor,
                        style: StrokeStyle(lineWidth: 24, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 180, height: 180)
                    .shadow(color: primaryColor.opacity(0.4), radius: 10)
                
                // Center Text
                VStack(spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(Int(tier2Percentage * 100))")
                            .font(.system(size: 48, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        Text("%")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text("TIER 2")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1)
                        .foregroundColor(primaryColor)
                }
            }
            .padding(.bottom, 12)
            
            // Legend
            HStack(spacing: 40) {
                HStack(spacing: 8) {
                    Circle().fill(primaryColor).frame(width: 8, height: 8)
                        .shadow(color: primaryColor.opacity(0.8), radius: 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CARVING")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                        Text("Tier 2 Precision")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                }
                
                HStack(spacing: 8) {
                    Circle().fill(Color(hex: "333333")).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SKIDDING")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.gray)
                        Text("Tier 1 Correction")
                            .font(.system(size: 10))
                            .foregroundColor(.gray.opacity(0.6))
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color(hex: "0a0a0a"))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .overlay(
             // Top Gradient Line
            GeometryReader { geo in
                LinearGradient(
                    colors: [.clear, primaryColor.opacity(0.3), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 1)
                .frame(width: geo.size.width)
            }
            , alignment: .top
        )
    }
}

struct MaxGForceCard: View {
    let maxG: Double
    let primaryColor: Color
    @State private var isScanning = false
    
    var body: some View {
        VStack {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "speedometer")
                    .font(.system(size: 14))
                    .foregroundColor(primaryColor)
                Text("MAX G-FORCE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundColor(.gray)
                Spacer()
            }
            .zIndex(1)
            
            Spacer()
            
            // Background Radar Animation
            ZStack {
                // Concentric Circles
                ForEach(1...3, id: \.self) { i in
                    Circle()
                        .stroke(primaryColor.opacity(0.2), lineWidth: 1)
                        .frame(width: CGFloat(i * 40))
                }
                // Crosshairs
                Rectangle().fill(primaryColor.opacity(0.1)).frame(width: 1, height: 140)
                Rectangle().fill(primaryColor.opacity(0.1)).frame(width: 140, height: 1)
                
                // Scanning Line
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [primaryColor.opacity(0), primaryColor.opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 2, height: 70)
                    .offset(y: -35)
                    .rotationEffect(.degrees(isScanning ? 360 : 0))
                    .onAppear {
                         withAnimation(Animation.linear(duration: 3).repeatForever(autoreverses: false)) {
                             isScanning = true
                         }
                    }
            }
            .frame(height: 120)
            .opacity(0.5)
            
            Spacer()
            
            // Value
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.1f", maxG))
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .shadow(color: primaryColor.opacity(0.5), radius: 8)
                Text("G")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.gray)
                Spacer()
            }
            .zIndex(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(Color(hex: "0a0a0a"))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .clipped()
    }
}

struct AvgGForceCard: View {
    let avgG: Double
    let primaryColor: Color
    
    var body: some View {
        VStack {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 14))
                    .foregroundColor(primaryColor)
                Text("AVG G-FORCE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundColor(.gray)
                Spacer()
            }
            .zIndex(1)
            
            Spacer()
            
            // Background Waveform Animation
            HStack(spacing: 4) {
                ForEach(0..<7) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(primaryColor.opacity(0.2))
                        .frame(width: 6, height: 40 + CGFloat(sin(Double(index) * 0.8) * 20))
                }
            }
            .frame(height: 120)
            .opacity(0.5)
            
            Spacer()
            
            // Value
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.2f", avgG))
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .shadow(color: primaryColor.opacity(0.5), radius: 8)
                Text("G")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.gray)
                Spacer()
            }
            .zIndex(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(Color(hex: "0a0a0a"))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .clipped()
    }
}

struct BankAngleCard: View {
    let angle: Double
    let primaryColor: Color
    
    var body: some View {
        HStack(spacing: 24) {
             // Icon & Visual
             ZStack {
                 // Background Arc
                 Circle()
                    .trim(from: 0.5, to: 1.0)
                    .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(90)) // Make it look like a slope or horizon
                    .offset(y: 10)
                 
                 // Skier Icon
                 Image(systemName: "figure.skiing.downhill")
                    .font(.system(size: 32))
                    .foregroundColor(primaryColor)
                    .shadow(color: primaryColor.opacity(0.5), radius: 10)
                    .mask(
                        // Mask to keep it inside the "card" area if needed, but visually open is fine
                        Rectangle().frame(width: 100, height: 100)
                    )
             }
             .frame(width: 80, height: 80)
             
             // Text Content
             VStack(alignment: .leading, spacing: 4) {
                 HStack(spacing: 6) {
                     Image(systemName: "compass.drawing")
                         .font(.system(size: 14))
                         .foregroundColor(.gray)
                     Text("EST. BANK ANGLE")
                         .font(.system(size: 10, weight: .bold))
                         .tracking(1)
                         .foregroundColor(.gray)
                 }
                 
                 HStack(alignment: .firstTextBaseline, spacing: 2) {
                     Text("\(Int(angle))")
                         .font(.system(size: 36, weight: .heavy, design: .rounded))
                         .foregroundColor(.white)
                     Text("°")
                         .font(.system(size: 24, weight: .light))
                         .foregroundColor(.gray)
                 }
                 
                 Text("Calculated from sustained G-Force")
                     .font(.system(size: 10))
                     .foregroundColor(.gray.opacity(0.5))
             }
             
             Spacer()
        }
        .padding(20)
        .background(Color(hex: "0a0a0a"))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct TurnSymmetryCard: View {
    let leftRatio: Double
    let rightRatio: Double
    let primaryColor: Color
    let purpleColor: Color
    let cyanColor: Color
    
    var body: some View {
        let delta = abs(leftRatio - rightRatio)
        let balanceLabel = delta < 0.1 ? "BALANCED" : (leftRatio > rightRatio ? "LEFT" : "RIGHT")
        
        VStack(spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                    Text("TURN SYMMETRY")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundColor(.gray)
                }
                Spacer()
                Text(balanceLabel)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(primaryColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(primaryColor.opacity(0.1))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(primaryColor.opacity(0.2), lineWidth: 1)
                    )
            }
            
            // Bars
            VStack(spacing: 8) {
                // Left
                HStack(spacing: 12) {
                    Text("L")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                        .frame(width: 12)
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.black)
                            
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [cyanColor.opacity(0.4), cyanColor],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * leftRatio)
                            
                            Text("\(Int(leftRatio * 100))%")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.leading, 4)
                                .frame(width: geo.size.width * leftRatio, alignment: .trailing)
                                .padding(.trailing, 4)
                        }
                    }
                    .frame(height: 24)
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.1), lineWidth: 1))
                }
                
                // Right
                HStack(spacing: 12) {
                    Text("R")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                        .frame(width: 12)
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.black)
                            
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [purpleColor.opacity(0.4), purpleColor],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * rightRatio)
                                
                            Text("\(Int(rightRatio * 100))%")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.leading, 4)
                                .frame(width: geo.size.width * rightRatio, alignment: .trailing)
                                .padding(.trailing, 4)
                        }
                    }
                    .frame(height: 24)
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.1), lineWidth: 1))
                }
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.05))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}
