import SwiftUI
import MapKit
import SwiftData
import Charts
import CoreLocation

struct RunDetailView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var storeManager: StoreManager
    let session: RunSession
    
    // State for Share Preview
    @State private var showSharePreview = false
    
    // State for GPX Export
    @State private var gpxFileURL: IdentifiableURL?
    @State private var showNoDataAlert = false
    @State private var analysisFileURL: IdentifiableURL?
    @State private var showNoAnalysisAlert = false
    @State private var showAnalysisExportError = false
    @State private var analysisExportErrorMessage: String = ""
    @State private var baroLogFileURL: IdentifiableURL?
    @State private var showNoBaroLogAlert = false
    @State private var showFullScreenMap = false
    @State private var isTimelineExpanded = false
    @State private var selectedRunMetric: RunSession.RunMetric?
    @State private var selectedRunAnalysis: RunSession.RunMetric?
    @State private var showPaywall = false
    @State private var showAnalysisPaywall = false
    @State private var showComingSoonAlert = false
    @State private var showComparePicker = false
    
    private let timelineNoiseThreshold: TimeInterval = 40.0
    private let timelineNoiseVerticalDrop: Double = 30.0
#if DEBUG
    @State private var showDebugSheet = false
#endif
    
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
            case .edge:
                return localizedString("run_detail.edge_title", fallback: "EDGE SCORE")
            case .flow:
                return localizedString("run_detail.flow_title", fallback: "FLOW SCORE")
            }
        }
        
        var description: String {
            switch self {
            case .edge:
                return localizedString(
                    "run_detail.edge_desc",
                    fallback: ""
                )
            case .flow:
                return localizedString(
                    "run_detail.flow_desc",
                    fallback: ""
                )
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
                        
                        // 5. Run Metrics (Per Run)
                        if !session.runMetrics.isEmpty {
                            runMetricsSection
                        }
                        
                        compareRunsCard
                            .padding(.horizontal)
                        
                        // 6. Timeline
                        if !session.timelineEvents.isEmpty {
                            timelineSection
                        }
                        
                        // 6. Bottom Share Button
                        shareButton
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
            FullScreenMapView(
                coordinates: routeCoordinates,
                speeds: session.routeSpeeds,
                maxSpeed: session.maxSpeed,
                gForceSamples: session.gForceSamples ?? [],
                maxGForce: session.maxGForce,
                runStartIndices: session.runStartIndices,
                timelineEvents: session.timelineEvents,
                routeTimestamps: session.routeTimestamps,
                routeAltitudes: session.routeAltitudes,
                routeDistances: session.routeDistances,
                routeStates: session.routeStates,
                locationName: session.locationName,
                startTime: session.startTime,
                sessionDuration: session.duration,
                region: mapRegion
            )
        }
        .fullScreenCover(item: $selectedRunMetric) { metric in
            RunMetricDetailSheet(
                metric: metric,
                accentColor: primaryColor,
                speedSeries: runSpeedSeries(for: metric),
                locationName: session.locationName
            )
        }
        .fullScreenCover(item: $selectedRunAnalysis) { metric in
            // Filter points for this run
            let indices = session.routeTimestamps.indices.filter {
                let t = session.routeTimestamps[$0]
                return t >= metric.startTime.timeIntervalSince1970 && t <= metric.endTime.timeIntervalSince1970
            }
            
            let points = indices.compactMap { i -> CLLocation? in
                guard i < session.routeCoordinates.count,
                      i < session.routeSpeeds.count,
                      session.routeCoordinates[i].count >= 2 else { return nil }
                
                let coord = CLLocationCoordinate2D(latitude: session.routeCoordinates[i][0], longitude: session.routeCoordinates[i][1])
                let speed = session.routeSpeeds[i] / 3.6 // km/h to m/s
                let timestamp = Date(timeIntervalSince1970: session.routeTimestamps[i])
                
                return CLLocation(
                    coordinate: coord,
                    altitude: 0,
                    horizontalAccuracy: 0,
                    verticalAccuracy: 0,
                    course: 0,
                    speed: speed,
                    timestamp: timestamp
                )
            }.sorted { $0.timestamp < $1.timestamp }
            
            let gPoints = (session.gForceSamples ?? []).compactMap { sample -> RunAnalysisView.Point? in
                let absoluteDate = session.startTime.addingTimeInterval(sample.t)
                guard absoluteDate >= metric.startTime && absoluteDate <= metric.endTime else { return nil }
                return RunAnalysisView.Point(x: absoluteDate, y: sample.gMax)
            }
            
            let lateralPoints = session.analysisSamples.compactMap { sample -> RunAnalysisView.Point? in
                guard let latAvg = sample.latAvg else { return nil }
                let absoluteDate = session.startTime.addingTimeInterval(sample.t)
                guard absoluteDate >= metric.startTime && absoluteDate <= metric.endTime else { return nil }
                return RunAnalysisView.Point(x: absoluteDate, y: latAvg)
            }
            
            let stabilityPoints = session.analysisSamples.compactMap { sample -> RunAnalysisView.Point? in
                let absoluteDate = session.startTime.addingTimeInterval(sample.t)
                guard absoluteDate >= metric.startTime && absoluteDate <= metric.endTime else { return nil }
                let stdDevMS = sample.speedStdDev / 3.6
                let stability = 1.0 / (1.0 + (stdDevMS / 3.5))
                return RunAnalysisView.Point(x: absoluteDate, y: stability)
            }
            
            ZStack {
                RunAnalysisView(
                    runMetric: metric, 
                    locationName: session.locationName, 
                    telemetryPoints: points,
                    gForcePoints: gPoints,
                    lateralGPoints: lateralPoints,
                    stabilityPoints: stabilityPoints
                )
                .blur(radius: storeManager.isPro ? 0 : 6)
                
                if !storeManager.isPro {
                    AnalysisLockOverlay(
                        accent: primaryColor,
                        onClose: { selectedRunAnalysis = nil },
                        onUnlock: { showAnalysisPaywall = true }
                    )
                }
            }
            .sheet(isPresented: $showAnalysisPaywall) {
                PaywallView()
            }
        }
        .fullScreenCover(item: $selectedRunMetric) { metric in
            RunMetricDetailSheet(
                metric: metric,
                accentColor: primaryColor,
                speedSeries: runSpeedSeries(for: metric),
                locationName: session.locationName
            )
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showComparePicker) {
            CompareRunPickerView(session: session)
        }
        .sheet(item: $gpxFileURL) { identifiableURL in
            ShareSheet(activityItems: [identifiableURL.url])
        }
        #if DEBUG
        .sheet(item: $analysisFileURL) { identifiableURL in
            ShareSheet(activityItems: [identifiableURL.url])
        }
        .sheet(item: $baroLogFileURL) { identifiableURL in
            ShareSheet(activityItems: [identifiableURL.url])
        }
        #endif
        .alert("GPX Export 불가", isPresented: $showNoDataAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("이 세션에는 GPS 경로 데이터가 없습니다.")
        }
        #if DEBUG
        .alert("분석 데이터 없음", isPresented: $showNoAnalysisAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("분석 리포트 내보내기에 필요한 데이터가 없습니다.")
        }
        .alert("분석 내보내기 실패", isPresented: $showAnalysisExportError) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(analysisExportErrorMessage)
        }
        .alert("바리오 로그 없음", isPresented: $showNoBaroLogAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("해당 세션에 저장된 바리오 로그 파일이 없습니다.")
        }
        #endif
#if DEBUG
        .sheet(isPresented: $showDebugSheet) {
            AnalysisDebugView(session: session)
        }
#endif
        .alert(item: $selectedScoreInfo) { info in
            Alert(
                title: Text(info.title),
                message: Text(info.description),
                dismissButton: .default(Text("ranking.tech_guide_ok"))
            )
        }
        .alert("common.coming_soon_title", isPresented: $showComingSoonAlert) {
            Button("common.coming_soon_ok", role: .cancel) { }
        } message: {
            Text("common.coming_soon_body")
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        ZStack {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                
                Spacer()
                
                HStack(spacing: 10) {
                    #if DEBUG
                    Button(action: { showDebugSheet = true }) {
                        Image(systemName: "ladybug")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    #endif
                    #if DEBUG
                    Button(action: { exportAnalysis() }) {
                        Image(systemName: "chart.bar.doc.horizontal")
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
                    
                    Button(action: { exportBarometerLog() }) {
                        Image(systemName: "waveform.path.ecg")
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
                    #endif
                    
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
            }
            
            Text("RUN DETAILS")
                .font(.system(size: 14, weight: .bold))
                .tracking(2)
                .foregroundColor(.white)
                .shadow(color: primaryColor.opacity(0.5), radius: 5)
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
            scoreCard(
                title: localizedString("run_detail.edge_title", fallback: "EDGE SCORE"),
                score: session.edgeScore,
                infoType: .edge
            )
            
            // Flow
            scoreCard(
                title: localizedString("run_detail.flow_title", fallback: "FLOW SCORE"),
                score: session.flowScore,
                infoType: .flow
            )
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
                RingGaugeView(progress: Double(score) / 1000.0, color: primaryColor)
                    .frame(width: 90, height: 90)
                    
                // Score Text
                VStack(spacing: -2) {
                    Text("\(score)")
                        .font(.system(size: 28, weight: .bold)) // Space Grotesk feel
                        .foregroundColor(.white)
                        .shadow(color: primaryColor.opacity(0.5), radius: 8)
                    Text("/1000")
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
            .disabled(true)
            .colorMultiply(Color(white: 0.6)) // Darken map
            .grayscale(0.8)
            .overlay(
                Group {
                    // if !session.routeSpeeds.isEmpty {
                    //    GradientRouteOverlay(coordinates: routeCoordinates, speeds: session.routeSpeeds, maxSpeed: session.maxSpeed)
                    // } else {
                        MapRouteOverlay(
                            coordinates: routeCoordinates,
                            color: primaryColor,
                            routeStates: session.routeStates
                        )
                    // }
                }
            )
            
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
                .stroke(primaryColor.opacity(0.5), lineWidth: 1.5)
        )
        .padding(.horizontal)
        .shadow(color: primaryColor.opacity(0.1), radius: 15)
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
            // 버티컬 드롭
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

    private var sortedRunMetrics: [RunSession.RunMetric] {
        session.runMetrics.sorted { $0.runNumber < $1.runNumber }
    }

    private var runMetricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(primaryColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: primaryColor, radius: 4)
                Text("RUN STATS")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .tracking(2)
            }
            .padding(.horizontal)
            
            VStack(spacing: 10) {
                ForEach(sortedRunMetrics) { metric in
                    runMetricCard(metric)
                }
            }
            .padding(.horizontal)
        }
    }

    private func runMetricCard(_ metric: RunSession.RunMetric) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(formatRunTimeRange(metric.startTime, metric.endTime))
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(.white)
                
                Spacer()
                
                Text(formatRunDuration(metric.duration))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.gray)
            }
            
            HStack(spacing: 8) {
                runMetricChip(label: "EDGE", value: "\(metric.edgeScore)")
                runMetricChip(label: "FLOW", value: "\(metric.flowScore)")
                
                Spacer()
                
                Button(action: {
                    selectedRunAnalysis = metric
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: storeManager.isPro ? "waveform.path.ecg" : "lock.fill")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(storeManager.isPro ? primaryColor : .yellow)
                    .padding(6)
                    .background((storeManager.isPro ? primaryColor.opacity(0.12) : Color.yellow.opacity(0.14)))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke((storeManager.isPro ? primaryColor.opacity(0.3) : Color.yellow.opacity(0.5)), lineWidth: 1)
                    )
                }
            }
            
            Text("VIEW DETAILS")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundColor(.gray)
        }
        .padding(14)
        .background(surfaceCard)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(primaryColor.opacity(0.4), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedRunMetric = metric
        }
    }

    private func runMetricChip(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(primaryColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.04))
        .cornerRadius(8)
    }
    
    private func formatSessionDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "00:00"
    }

    private func formatRunDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "00:00"
    }

    private func formatSpeedOneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func runSpeedSeries(for metric: RunSession.RunMetric) -> [Double] {
        let speeds = session.routeSpeeds
        let indices = session.runStartIndices
        guard !speeds.isEmpty else { return [] }
        let runNumber = max(1, metric.runNumber)
        let index = runNumber - 1
        // runStartIndices는 초기값 0을 포함하므로, 실제 런 시작 인덱스는 index+1 우선
        let startIndex: Int
        if index + 1 < indices.count {
            startIndex = indices[index + 1]
        } else if index < indices.count {
            startIndex = indices[index]
        } else {
            startIndex = 0
        }
        // 히스토리 데이터에는 런 종료 인덱스가 없으므로 다음 런 시작 인덱스로 구간을 나눔
        let endIndex: Int
        if index + 2 < indices.count {
            endIndex = indices[index + 2]
        } else {
            endIndex = speeds.count
        }
        let safeStart = max(0, min(startIndex, speeds.count))
        let safeEnd = max(safeStart, min(endIndex, speeds.count))
        guard safeEnd > safeStart else { return [] }
        return Array(speeds[safeStart..<safeEnd])
    }
    
    // MARK: - Timeline Post-Processing (UI Only)
    
    private var displayTimelineEvents: [RunSession.TimelineEvent] {
        normalizeTimelineEvents(
            session.timelineEvents.map { event in
                var normalized = event
                if normalized.type == .pause {
                    normalized.type = .rest
                }
                let trimmedDetail = normalized.detail.trimmingCharacters(in: .whitespacesAndNewlines)
                let lowerDetail = trimmedDetail.lowercased()
                if normalized.type == .rest {
                    let restDefaults = ["휴식", "대기 중", "rest", "resting"]
                    let shouldLocalize = trimmedDetail.isEmpty
                        || restDefaults.contains(trimmedDetail)
                        || lowerDetail == "rest"
                        || lowerDetail == "resting"
                    if shouldLocalize {
                        normalized.detail = localizedString("timeline.rest", fallback: "휴식")
                    }
                }
                if normalized.type == .lift {
                    let liftDefaults = ["리프트 이동", "리프트", "리프트 탑승", "on lift", "lift", "lift ride"]
                    let shouldLocalize = trimmedDetail.isEmpty
                        || liftDefaults.contains(trimmedDetail)
                        || lowerDetail == "lift"
                        || lowerDetail == "on lift"
                        || lowerDetail == "lift ride"
                        || trimmedDetail.contains("리프트")
                    if shouldLocalize {
                        normalized.detail = localizedString("timeline.lift", fallback: "리프트 탑승")
                    }
                }
                return normalized
            },
            minRidingDuration: timelineNoiseThreshold,
            maxVerticalDrop: timelineNoiseVerticalDrop,
            runMetrics: session.runMetrics
        )
    }
    
    private func normalizeTimelineEvents(
        _ events: [RunSession.TimelineEvent],
        minRidingDuration: TimeInterval,
        maxVerticalDrop: Double,
        runMetrics: [RunSession.RunMetric]
    ) -> [RunSession.TimelineEvent] {
        let sorted = events.sorted { $0.startTime < $1.startTime }
        guard sorted.count > 1 else { return sorted }
        
        let metricsByStartTime = Dictionary(uniqueKeysWithValues: runMetrics.map { ($0.startTime, $0) })
        
        var result: [RunSession.TimelineEvent] = []
        var i = 0
        var pendingStartTime: Date?
        
        while i < sorted.count {
            var current = sorted[i]
            if let pending = pendingStartTime {
                current.startTime = pending
                pendingStartTime = nil
            }
            
            let duration = current.duration
            let metric = metricsByStartTime[current.startTime]
            let verticalDrop = metric?.verticalDrop ?? .infinity
            let isShortRiding = current.type == .riding
                && duration > 0
                && duration <= minRidingDuration
                && verticalDrop <= maxVerticalDrop
            
            if isShortRiding {
                let prevIndex = result.count - 1
                let next = (i + 1 < sorted.count) ? sorted[i + 1] : nil
                
                if let next {
                    if prevIndex >= 0 {
                        let prev = result[prevIndex]
                        if prev.type == next.type {
                            // 이전/다음이 같은 타입이면 하나로 합침
                            var merged = prev
                            merged.endTime = next.endTime ?? next.startTime
                            result[prevIndex] = merged
                            i += 2
                            continue
                        }
                        // lift 우선 흡수
                        if prev.type == .lift || next.type == .lift {
                            if next.type == .lift {
                                pendingStartTime = current.startTime
                                i += 1
                                continue
                            } else {
                                var merged = prev
                                merged.endTime = current.endTime ?? current.startTime
                                result[prevIndex] = merged
                                i += 1
                                continue
                            }
                        }
                    }
                    // 기본: 다음 이벤트로 흡수
                    pendingStartTime = current.startTime
                    i += 1
                    continue
                } else if prevIndex >= 0 {
                    // 마지막에 짧은 riding이면 이전 이벤트로 흡수
                    var merged = result[prevIndex]
                    merged.endTime = current.endTime ?? current.startTime
                    result[prevIndex] = merged
                    i += 1
                    continue
                } else {
                    // 단독 이벤트면 버림
                    i += 1
                    continue
                }
            }
            
            result.append(current)
            i += 1
        }
        
        return result
    }

    private func formatRunTimeRange(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start)) ~ \(formatter.string(from: end))"
    }
    
    private var verticalDropCard: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("VERTICAL DROP")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.gray)
                    .tracking(1)
                Spacer()
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 14))
                    .foregroundColor(.gray.opacity(0.7))
            }
            
            Spacer()
            
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(Int(session.verticalDrop))")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text("M")
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
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 10)
    }
    
    private var compareRunsCard: some View {
        Button(action: {
            if storeManager.isPro {
                showComparePicker = true
            } else {
                showPaywall = true
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(primaryColor)
                    .padding(10)
                    .background(Circle().fill(Color.white.opacity(0.06)))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("run_detail.compare_title")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1)
                        .foregroundColor(.white)
                    Text("run_detail.compare_desc")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Image(systemName: storeManager.isPro ? "chevron.right" : "lock.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(storeManager.isPro ? .white.opacity(0.6) : .yellow)
            }
            .padding(14)
            .background(surfaceCard)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
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
                Text("run_detail.timeline_title")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .tracking(2)
                
                Spacer()
                
                Button(action: { withAnimation { isTimelineExpanded.toggle() } }) {
                    HStack(spacing: 4) {
                        Text(isTimelineExpanded ? "run_detail.timeline_collapse" : "run_detail.timeline_view_all")
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
                let counts = Dictionary(grouping: displayTimelineEvents, by: { $0.type }).mapValues { $0.count }
                let total = max(Double(displayTimelineEvents.count), 1)
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
                legendItem(color: primaryColor, label: localizedString("run_detail.legend_ride", fallback: "RIDE"))
                legendItem(color: Color.white.opacity(0.2), label: localizedString("run_detail.legend_lift", fallback: "LIFT"))
                legendItem(color: surfaceCard, isBorder: true, label: localizedString("run_detail.legend_rest", fallback: "REST"))
            }
            .padding(.horizontal)
            
            // Timeline List (Subway Style)
            VStack(spacing: 0) {
                let eventsToShow = isTimelineExpanded ? displayTimelineEvents : Array(displayTimelineEvents.prefix(3))
                
                ForEach(Array(eventsToShow.enumerated()), id: \.element.id) { index, event in
                    TimelineRowModern(event: event, isLast: index == eventsToShow.count - 1 && isTimelineExpanded, primaryColor: primaryColor)
                }
                
                if !isTimelineExpanded && displayTimelineEvents.count > 3 {
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
    
    private var shareButton: some View {
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
    
    private func exportBarometerLog() {
        let url = BarometerLogExportService.existingURL(startTime: session.startTime)
        if FileManager.default.fileExists(atPath: url.path) {
            baroLogFileURL = IdentifiableURL(url: url)
        } else {
            showNoBaroLogAlert = true
        }
    }
    
    private func exportAnalysis() {
        guard AnalysisExportService.hasAnalysisData(session: session) else {
            showNoAnalysisAlert = true
            return
        }
        
        do {
            let url = try AnalysisExportService.export(session: session)
            analysisFileURL = IdentifiableURL(url: url)
        } catch AnalysisExportError.noData {
            showNoAnalysisAlert = true
        } catch {
            analysisExportErrorMessage = "예기치 못한 오류가 발생했습니다."
            showAnalysisExportError = true
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
                    Text(verbatim: eventTypeLabel)
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

    var eventTypeLabel: String {
        switch event.type {
        case .riding:
            return localizedString("run_detail.event_riding", fallback: "RIDE")
        case .lift:
            return localizedString("run_detail.event_lift", fallback: "LIFT")
        case .rest:
            return localizedString("run_detail.event_rest", fallback: "REST")
        case .pause:
            return localizedString("run_detail.event_pause", fallback: "PAUSE")
        case .unknown:
            return localizedString("run_detail.event_unknown", fallback: "UNKNOWN")
        }
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute]
        formatter.unitsStyle = .abbreviated
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = preferredLocale()
        formatter.calendar = calendar
        return formatter.string(from: duration) ?? ""
    }
}

private func preferredLocale() -> Locale {
    let preferred = UserDefaults.standard.string(forKey: "preferred_language") ?? "system"
    switch preferred {
    case "ko":
        return Locale(identifier: "ko")
    case "en":
        return Locale(identifier: "en")
    default:
        return Locale.autoupdatingCurrent
    }
}

private func localizedString(_ key: String, fallback: String) -> String {
    let preferred = UserDefaults.standard.string(forKey: "preferred_language") ?? "system"
    let bundle: Bundle
    switch preferred {
    case "ko":
        bundle = Bundle(path: Bundle.main.path(forResource: "ko", ofType: "lproj") ?? "") ?? .main
    case "en":
        bundle = Bundle(path: Bundle.main.path(forResource: "en", ofType: "lproj") ?? "") ?? .main
    default:
        bundle = .main
    }
    let value = bundle.localizedString(forKey: key, value: fallback, table: nil)
    return value.isEmpty ? fallback : value
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
            // Top Row: Dot & Badge
            HStack {
                Circle()
                    .fill(difficultyInfo.color)
                    .frame(width: 8, height: 8)
                    .shadow(color: difficultyInfo.color.opacity(0.5), radius: 5)
                
                Spacer()
                
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
            
            // Bottom Row: Name & Count
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text("x\(count) RUNS")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.gray)
            }
        }
        .padding(14)
        .frame(width: 140, height: 110)
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
enum MapControlAction {
    case zoomIn
    case zoomOut
    case center
}

enum MapViewMode {
    case twoD
    case threeD
}

enum HeatmapMode {
    case off
    case speed
    case gForce
    case edgeFlow
}

struct FullScreenMapView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var storeManager: StoreManager
    let coordinates: [CLLocationCoordinate2D]
    let speeds: [Double]
    let maxSpeed: Double
    let gForceSamples: [RunSession.GForceSample]
    let maxGForce: Double
    let runStartIndices: [Int]
    let timelineEvents: [RunSession.TimelineEvent]
    let routeTimestamps: [TimeInterval]
    let routeAltitudes: [Double]
    let routeDistances: [Double]
    let routeStates: [RunSession.TimelineEvent.EventType]
    let locationName: String
    let startTime: Date
    let sessionDuration: TimeInterval
    @State var region: MKCoordinateRegion
    
    @State private var scrubProgress: Double = 0.65
    @State private var showLayersPanel: Bool = false
    @State private var showRoutePath: Bool = true
    @State private var showStatusSegments: Bool = true
    @State private var mapViewMode: MapViewMode = .twoD
    @State private var heatmapMode: HeatmapMode = .off
    @State private var showPaywall: Bool = false
    // Removed local isProUnlocked state
    @State private var mapControlAction: MapControlAction? = nil
    @State private var scrubDragStart: Double? = nil
    private let scrubSensitivity: Double = 0.6 // 스크럽 이동 민감도(낮을수록 타임라인 이동량 감소)
    private let scrubResponseCurve: Double = 0.85 // 드래그 응답 곡선(1에 가까울수록 선형, 낮을수록 초반 반응 증가)
    
    var body: some View {
        let heatmap = activeHeatmap
        ZStack {
            Color.black.ignoresSafeArea()
            MapViewRepresentable(
                region: region,
                coordinates: coordinates,
                lineColor: UIColor(red: 107/255, green: 249/255, blue: 6/255, alpha: 1.0),
                runStartIndices: runStartIndices,
                timelineEvents: timelineEvents,
                routeTimestamps: effectiveRouteTimestamps,
                routeStates: routeStates,
                speeds: speeds,
                maxSpeed: maxSpeed,
                showRoutePath: showRoutePath,
                showStatusSegments: showStatusSegments,
                viewMode: mapViewMode,
                heatmapMode: heatmapMode,
                heatmapValues: heatmap.values,
                maxHeatmapValue: heatmap.maxValue,
                headingDegrees: currentHeading,
                highlightCoordinate: currentCoordinate,
                currentTimestamp: hasTimestamps ? currentTimestamp : nil,
                currentIndex: currentIndex,
                mapControlAction: $mapControlAction
            )
            .ignoresSafeArea()
            // 지도 톤을 살짝 낮춰 라인 대비만 강조 (과도한 암부 방지 - 수정됨)
            .overlay(
                Color.black.opacity(0.05) // 0.12 -> 0.05로 대폭 감소
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            )
            .overlay(
                LinearGradient(
                    colors: [Color.black.opacity(0.3), .clear], // 0.45 -> 0.3
                    startPoint: .top,
                    endPoint: .center
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            )
            .overlay(
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.6)], // 0.7 -> 0.6
                    startPoint: .center,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            )
            .overlay(alignment: .top) {
                GeometryReader { proxy in
                    headerBar
                        .padding(.top, proxy.safeAreaInsets.top + 60) // 사용자가 요청한 60pt
                        .padding(.horizontal, 16)
                }
                .ignoresSafeArea()
            }
            .overlay(alignment: .bottom) {
                bottomHUD
            }
            
            if showLayersPanel {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { showLayersPanel = false }
                layersPanel
            }
            
            mapControls
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
    
    private var neonGreen: Color {
        Color(red: 107/255, green: 249/255, blue: 6/255)
    }

    private var activeHeatmap: (values: [Double], maxValue: Double) {
        switch heatmapMode {
        case .speed:
            return (speeds, maxSpeed)
        case .gForce:
            let values = gForceSeries
            let seriesMax = values.max() ?? 0
            let maxValue = seriesMax > 0 ? seriesMax : maxGForce
            return (values, maxValue)
        case .edgeFlow:
            let values = flowSeries
            return (values, 1.0)
        default:
            return ([], 0)
        }
    }

    private var gForceSeries: [Double] {
        buildGForceSeries()
    }

    private var flowSeries: [Double] {
        buildFlowSeries()
    }

    private func buildGForceSeries() -> [Double] {
        guard !gForceSamples.isEmpty else { return [] }
        let timestamps = effectiveRouteTimestamps
        guard !timestamps.isEmpty else { return [] }

        // G-Force 히트맵은 1초 평균값(gAvg)을 경로 타임스탬프에 보간한다.
        let baseTime = startTime.timeIntervalSince1970
        var sampleTimes: [TimeInterval] = []
        sampleTimes.reserveCapacity(gForceSamples.count)
        for sample in gForceSamples {
            sampleTimes.append(baseTime + sample.t)
        }

        var values: [Double] = []
        values.reserveCapacity(timestamps.count)
        var index = 0

        for timestamp in timestamps {
            while index + 1 < sampleTimes.count && sampleTimes[index + 1] <= timestamp {
                index += 1
            }

            let current = gForceSamples[index]
            if index + 1 < gForceSamples.count {
                let next = gForceSamples[index + 1]
                let t0 = sampleTimes[index]
                let t1 = sampleTimes[index + 1]
                let ratio = t1 > t0 ? min(max((timestamp - t0) / (t1 - t0), 0), 1) : 0
                let interpolated = current.gAvg + (next.gAvg - current.gAvg) * ratio
                values.append(interpolated)
            } else {
                values.append(current.gAvg)
            }
        }

        return values
    }

    private func buildFlowSeries() -> [Double] {
        guard !speeds.isEmpty else { return [] }

        let flowWindowSize = 5
        let flowVarianceDenominator: Double = 3.5
        let flowMinSpeedMS: Double = 2.0

        var window: [Double] = []
        window.reserveCapacity(flowWindowSize)
        var sum: Double = 0.0
        var sumSq: Double = 0.0

        var values: [Double] = []
        values.reserveCapacity(speeds.count)

        for index in 0..<speeds.count {
            let speedMS = max(0.0, speeds[index] / 3.6)
            let isRiding = routeStates.count == speeds.count ? routeStates[index] == .riding : true

            guard isRiding, speedMS >= flowMinSpeedMS else {
                window.removeAll()
                sum = 0.0
                sumSq = 0.0
                values.append(0.0)
                continue
            }

            window.append(speedMS)
            sum += speedMS
            sumSq += speedMS * speedMS

            if window.count > flowWindowSize, let removed = window.first {
                window.removeFirst()
                sum -= removed
                sumSq -= removed * removed
            }

            guard window.count >= 2 else {
                values.append(0.0)
                continue
            }

            let mean = sum / Double(window.count)
            let variance = max(0.0, (sumSq / Double(window.count)) - (mean * mean))
            let stdDev = sqrt(variance)
            let stability = 1.0 / (1.0 + (stdDev / flowVarianceDenominator))
            values.append(stability)
        }

        return values
    }
    
    private var effectiveRouteTimestamps: [TimeInterval] {
        guard !coordinates.isEmpty else { return [] }
        if routeTimestamps.count == coordinates.count && !routeTimestamps.isEmpty {
            return routeTimestamps
        }
        
        let start: TimeInterval
        let end: TimeInterval
        if let eventStart = eventTimelineStart, let eventEnd = eventTimelineEnd, eventEnd > eventStart {
            start = eventStart
            end = eventEnd
        } else if routeTimestamps.count >= 2,
                  let first = routeTimestamps.first,
                  let last = routeTimestamps.last,
                  last > first {
            start = first
            end = last
        } else {
            start = startTime.timeIntervalSince1970
            let safeDuration = max(1, sessionDuration)
            end = start + safeDuration
        }
        
        if coordinates.count == 1 {
            return [start]
        }
        
        let step = (end - start) / Double(coordinates.count - 1)
        return (0..<coordinates.count).map { index in
            start + (Double(index) * step)
        }
    }
    
    private var effectiveRouteDistances: [Double] {
        guard !coordinates.isEmpty else { return [] }
        if routeDistances.count == coordinates.count && !routeDistances.isEmpty {
            return routeDistances
        }
        if coordinates.count == 1 {
            return [0]
        }
        var distances: [Double] = [0]
        distances.reserveCapacity(coordinates.count)
        var total: Double = 0
        for index in 1..<coordinates.count {
            let prev = coordinates[index - 1]
            let current = coordinates[index]
            let prevLocation = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
            let currentLocation = CLLocation(latitude: current.latitude, longitude: current.longitude)
            total += prevLocation.distance(from: currentLocation)
            distances.append(total)
        }
        return distances
    }

    private var effectiveRouteAltitudes: [Double] {
        guard !coordinates.isEmpty else { return [] }
        if routeAltitudes.count == coordinates.count && !routeAltitudes.isEmpty {
            return routeAltitudes
        }
        guard !routeAltitudes.isEmpty else { return [] }
        if routeAltitudes.count == 1 {
            return Array(repeating: routeAltitudes[0], count: coordinates.count)
        }
        let step = Double(routeAltitudes.count - 1) / Double(max(1, coordinates.count - 1))
        return (0..<coordinates.count).map { index in
            let position = Double(index) * step
            let lower = Int(position.rounded(.down))
            let upper = min(routeAltitudes.count - 1, lower + 1)
            let t = position - Double(lower)
            let start = routeAltitudes[lower]
            let end = routeAltitudes[upper]
            return start + (end - start) * t
        }
    }

    private var effectiveRidingDistances: [Double] {
        guard coordinates.count > 1 else { return coordinates.isEmpty ? [] : [0] }
        let timestamps = effectiveRouteTimestamps
        guard timestamps.count == coordinates.count, !timelineEvents.isEmpty else { return [] }

        let sortedEvents = timelineEvents.sorted { $0.startTime < $1.startTime }
        var eventIndex = 0
        var distances: [Double] = [0]
        distances.reserveCapacity(coordinates.count)
        var total: Double = 0

        for index in 1..<coordinates.count {
            let timestamp = timestamps[index]
            while eventIndex < sortedEvents.count {
                let event = sortedEvents[eventIndex]
                let endTime = (event.endTime ?? event.startTime).timeIntervalSince1970
                if timestamp <= endTime {
                    break
                }
                eventIndex += 1
            }

            var isRiding = false
            if eventIndex < sortedEvents.count {
                let event = sortedEvents[eventIndex]
                let startTime = event.startTime.timeIntervalSince1970
                let endTime = (event.endTime ?? event.startTime).timeIntervalSince1970
                isRiding = (event.type == .riding && timestamp >= startTime && timestamp <= endTime)
            }

            if isRiding {
                let prev = coordinates[index - 1]
                let current = coordinates[index]
                let prevLocation = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
                let currentLocation = CLLocation(latitude: current.latitude, longitude: current.longitude)
                total += prevLocation.distance(from: currentLocation)
            }

            distances.append(total)
        }
        return distances
    }
    
    private var hasTimestamps: Bool {
        !effectiveRouteTimestamps.isEmpty
    }
    
    private var eventTimelineStart: TimeInterval? {
        let sortedEvents = timelineEvents.sorted { $0.startTime < $1.startTime }
        return sortedEvents.first?.startTime.timeIntervalSince1970
    }
    
    private var eventTimelineEnd: TimeInterval? {
        let sortedEvents = timelineEvents.sorted { $0.startTime < $1.startTime }
        guard let last = sortedEvents.last else { return nil }
        let endTime = last.endTime ?? last.startTime
        return endTime.timeIntervalSince1970
    }
    
    private var timelineStart: TimeInterval {
        if let eventStart = eventTimelineStart {
            return eventStart
        }
        return hasTimestamps ? (effectiveRouteTimestamps.first ?? 0) : 0
    }
    
    private var timelineEnd: TimeInterval {
        if let eventEnd = eventTimelineEnd {
            return eventEnd
        }
        return hasTimestamps ? (effectiveRouteTimestamps.last ?? timelineStart) : max(1, Double(max(coordinates.count - 1, 1)))
    }
    
    private var timelineDuration: TimeInterval {
        max(0, timelineEnd - timelineStart)
    }
    
    private var scrubTime: TimeInterval {
        timelineDuration * scrubProgress
    }
    
    private var currentTimestamp: TimeInterval {
        timelineStart + scrubTime
    }
    
    private var currentIndex: Int? {
        guard !coordinates.isEmpty else { return nil }
        if hasTimestamps {
            return nearestIndex(for: currentTimestamp)
        }
        let index = Int(Double(coordinates.count - 1) * scrubProgress)
        return max(0, min(coordinates.count - 1, index))
    }

    private var currentInterpolation: (lower: Int, upper: Int, t: Double)? {
        guard hasTimestamps else { return nil }
        let timestamps = effectiveRouteTimestamps
        guard timestamps.count == coordinates.count, timestamps.count >= 2 else { return nil }
        let time = currentTimestamp
        if time <= timestamps.first! {
            return (0, 0, 0)
        }
        if time >= timestamps.last! {
            let lastIndex = timestamps.count - 1
            return (lastIndex, lastIndex, 0)
        }
        var low = 0
        var high = timestamps.count - 1
        while low < high {
            let mid = (low + high) / 2
            if timestamps[mid] < time {
                low = mid + 1
            } else {
                high = mid
            }
        }
        let upper = max(0, min(timestamps.count - 1, low))
        let lower = max(0, upper - 1)
        let start = timestamps[lower]
        let end = timestamps[upper]
        let t = end > start ? (time - start) / (end - start) : 0
        return (lower, upper, min(max(t, 0), 1))
    }
    
    private var currentCoordinate: CLLocationCoordinate2D? {
        if let interpolation = currentInterpolation {
            let lower = coordinates[interpolation.lower]
            let upper = coordinates[interpolation.upper]
            let t = interpolation.t
            let latitude = lower.latitude + (upper.latitude - lower.latitude) * t
            let longitude = lower.longitude + (upper.longitude - lower.longitude) * t
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        guard let index = currentIndex, index < coordinates.count else { return nil }
        return coordinates[index]
    }
    
    private var currentSpeed: Double? {
        if let interpolation = currentInterpolation,
           interpolation.upper < speeds.count,
           interpolation.lower < speeds.count {
            let lower = speeds[interpolation.lower]
            let upper = speeds[interpolation.upper]
            return lower + (upper - lower) * interpolation.t
        }
        guard let index = currentIndex, index < speeds.count else { return nil }
        return speeds[index]
    }

    private var currentHeading: Double? {
        if let interpolation = currentInterpolation {
            let lower = coordinates[interpolation.lower]
            let upper = coordinates[interpolation.upper]
            if interpolation.lower != interpolation.upper {
                return bearing(from: lower, to: upper)
            }
        }
        guard let index = currentIndex, index + 1 < coordinates.count else { return nil }
        return bearing(from: coordinates[index], to: coordinates[index + 1])
    }
    
    private var currentAltitude: Double? {
        let altitudes = effectiveRouteAltitudes
        if let interpolation = currentInterpolation,
           interpolation.upper < altitudes.count,
           interpolation.lower < altitudes.count {
            let lower = altitudes[interpolation.lower]
            let upper = altitudes[interpolation.upper]
            return lower + (upper - lower) * interpolation.t
        }
        guard let index = currentIndex, index < altitudes.count else { return nil }
        return altitudes[index]
    }
    
    private var currentDistance: Double? {
        let distances = effectiveRidingDistances
        if let interpolation = currentInterpolation,
           interpolation.upper < distances.count,
           interpolation.lower < distances.count {
            let lower = distances[interpolation.lower]
            let upper = distances[interpolation.upper]
            return lower + (upper - lower) * interpolation.t
        }
        guard let index = currentIndex, index < distances.count else { return nil }
        return distances[index]
    }
    
    private var currentEvent: RunSession.TimelineEvent? {
        guard !timelineEvents.isEmpty else { return nil }
        let time = Date(timeIntervalSince1970: currentTimestamp)
        return timelineEvents.first { event in
            let end = event.endTime ?? event.startTime
            return time >= event.startTime && time <= end
        }
    }
    
    private func zoomIn() {
        mapControlAction = .zoomIn
    }

    private func zoomOut() {
        mapControlAction = .zoomOut
    }

    private var headerBar: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                
                Spacer()
                
                VStack(spacing: 4) {
                    Text(locationName.uppercased())
                        .font(.system(size: 16, weight: .heavy))
                        .tracking(2)
                        .foregroundColor(.white)
                    Text(startTime.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundColor(neonGreen.opacity(0.9))
                }
                
                Spacer()
                
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showLayersPanel.toggle() } }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 42, height: 42)
                        .background(showLayersPanel ? neonGreen : Color.white.opacity(0.08))
                        .foregroundColor(showLayersPanel ? .black : .white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 8)
        }
    }
    
    private var layersPanel: some View {
        GeometryReader { proxy in
            let availableHeight = proxy.size.height - proxy.safeAreaInsets.top - 220
            let panelHeight = max(240, min(460, availableHeight))
            
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text("LAYERS")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(2)
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "square.stack.3d.up.fill")
                        .foregroundColor(neonGreen)
                        .shadow(color: neonGreen.opacity(0.8), radius: 8)
                }
                .padding(16)
                .padding(.bottom, 4)
                .background(Color.white.opacity(0.05))
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 1),
                    alignment: .bottom
                )
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Basic Section
                        VStack(alignment: .leading, spacing: 10) {
                            Text("BASIC")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1.5)
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.leading, 4)
                            
                            VStack(spacing: 8) {
                                ToggleRow(title: "Route Path", icon: "arrow.triangle.turn.up.right.diamond.fill", isOn: $showRoutePath, accent: neonGreen)
                                ToggleRow(title: "Status", icon: "location.circle.fill", isOn: $showStatusSegments, accent: neonGreen)
                            }
                        }
                        
                        // View Section
                        VStack(alignment: .leading, spacing: 10) {
                            Text("VIEW")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1.5)
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.leading, 4)
                            
                            ViewModeRow(
                                selectedMode: $mapViewMode,
                                isProUnlocked: storeManager.isPro,
                                accent: neonGreen
                            )
                        }
                        
                        // Heatmap Section (Base)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("HEATMAP")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1.5)
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.leading, 4)
                            
                            VStack(spacing: 8) {
                                HeatmapRow(
                                    title: "OFF",
                                    icon: "circle.slash",
                                    mode: .off,
                                    selectedMode: $heatmapMode,
                                    isProUnlocked: true,
                                    accent: neonGreen
                                )
                            }
                        }
                        
                        // Pro Analysis Section
                        VStack(alignment: .leading, spacing: 0) {
                            // Pro Header
                            HStack {
                                HStack(spacing: 6) {
                                    Text("PRO ANALYSIS")
                                        .font(.system(size: 10, weight: .bold))
                                        .tracking(1.5)
                                        .foregroundColor(neonGreen)
                                        .shadow(color: neonGreen.opacity(0.5), radius: 5)
                                    
                                    Text("PLUS")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(neonGreen)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(neonGreen.opacity(0.2))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(neonGreen.opacity(0.5), lineWidth: 0.5)
                                        )
                                        .cornerRadius(4)
                                }
                                
                                Spacer()
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.yellow)
                            }
                            .padding(.bottom, 10)
                            .padding(.leading, 4)
                            
                            VStack(spacing: 8) {
                                HeatmapRow(
                                    title: "SPEED",
                                    icon: "speedometer",
                                    mode: .speed,
                                    selectedMode: $heatmapMode,
                                    isProUnlocked: storeManager.isPro,
                                    accent: neonGreen
                                )
                                HeatmapRow(
                                    title: "G-FORCE",
                                    icon: "waveform.path.ecg",
                                    mode: .gForce,
                                    selectedMode: $heatmapMode,
                                    isProUnlocked: storeManager.isPro,
                                    accent: neonGreen
                                )
                            }
                            .padding(4)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
                            )
                            
                            // Unlock Button
                            Button(action: { showPaywall = true }) {
                                HStack(spacing: 4) {
                                    Text("UNLOCK ALL PRO FEATURES")
                                        .font(.system(size: 10, weight: .black))
                                        .tracking(1)
                                    Image(systemName: "arrow.forward")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    LinearGradient(colors: [neonGreen.opacity(0.9), neonGreen], startPoint: .leading, endPoint: .trailing)
                                )
                                .cornerRadius(8)
                                .shadow(color: neonGreen.opacity(0.3), radius: 10)
                            }
                            .padding(.top, 16)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 8)
                }
            }
            .background(.ultraThinMaterial)
            .background(Color.black.opacity(0.6))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 20)
            .frame(width: 280)
            .frame(maxHeight: panelHeight)
            .padding(.top, proxy.safeAreaInsets.top + 92)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .ignoresSafeArea()
    }
    
    private var mapControls: some View {
        VStack(spacing: 10) {
            MapControlButton(systemName: "plus", accent: neonGreen, action: zoomIn)
            MapControlButton(systemName: "minus", accent: neonGreen, action: zoomOut)
        }
        .position(x: UIScreen.main.bounds.width - 36, y: UIScreen.main.bounds.height * 0.55)
    }
    
    private var bottomHUD: some View {
        VStack(spacing: 20) {
            timelineScrubber

            statusCard
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
        }
        .padding(.top, 30)
        .background(
            LinearGradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
        )
    }
    
    @State private var lastHapticState: RunSession.TimelineEvent.EventType?
    
    private var timelineScrubber: some View {
        VStack(spacing: 8) {
            HStack {
                Text("START")
                Spacer()
                Text(formatTime(scrubTime))
                Spacer()
                Text("FINISH")
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(2)
            .foregroundColor(.white.opacity(0.5))
            .padding(.horizontal, 16)
            
            GeometryReader { proxy in
                let width = proxy.size.width
                let totalDuration = timelineDuration
                
                ZStack(alignment: .leading) {
                    // 1. Background Track (Dimmed)
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 6)
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                    
                    // 2. State Segments (Glowy Style)
                    if totalDuration > 0 {
                        ForEach(timelineEvents) { event in
                            let eventStart = event.startTime.timeIntervalSince1970
                            let eventEnd = (event.endTime ?? event.startTime).timeIntervalSince1970
                            
                            let safeStart = max(timelineStart, eventStart)
                            let safeEnd = min(timelineEnd, eventEnd)
                            
                            if safeEnd > safeStart {
                                let segmentDuration = safeEnd - safeStart
                                let segmentWidth = (segmentDuration / totalDuration) * width
                                let offset = ((safeStart - timelineStart) / totalDuration) * width
                                
                                let color: Color = {
                                    switch event.type {
                                    case .riding: return neonGreen
                                    case .lift: return Color.white.opacity(0.3)
                                    case .rest, .pause: return Color.clear
                                    case .unknown: return Color.red
                                    }
                                }()
                                
                                // Enhanced Segment with Glow
                                Rectangle()
                                    .fill(color)
                                    .frame(width: max(1, segmentWidth), height: 6)
                                    .offset(x: offset)
                                    .shadow(color: event.type == .riding ? neonGreen.opacity(0.6) : .clear, radius: 4)
                            }
                        }
                    }
                    
                    // 3. Knob (Neon Circle) - Reduced size
                    Circle()
                        .fill(Color.black)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle()
                                .stroke(neonGreen, lineWidth: 2)
                        )
                        .shadow(color: neonGreen.opacity(0.8), radius: 8)
                        .offset(x: width * scrubProgress - 8)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if scrubDragStart == nil {
                                        scrubDragStart = scrubProgress
                                    }
                                    let base = scrubDragStart ?? scrubProgress
                                    let raw = value.translation.width / width
                                    let magnitude = min(1, abs(raw))
                                    let eased = pow(magnitude, scrubResponseCurve)
                                    let delta = (raw >= 0 ? 1.0 : -1.0) * eased * scrubSensitivity
                                    let progress = min(max(0, base + delta), 1)
                                    scrubProgress = progress
                                    
                                    // Haptic Feedback Logic
                                    triggerHapticIfNeeded()
                                }
                                .onEnded { value in
                                    if abs(value.translation.width) < 2,
                                       abs(value.translation.height) < 2 {
                                        let progress = min(max(0, value.location.x / width), 1)
                                        scrubProgress = progress
                                        triggerHapticIfNeeded()
                                    }
                                    scrubDragStart = nil
                                    lastHapticState = nil
                                }
                        )
                }
                .mask(Rectangle().frame(height: 60).offset(y: 0)) // Ensure mask is large enough if present, or remove mask if causing clipping.
                // Actually the previous code had .mask(Capsule()) which clips tightly. 
                // We should remove the tight mask or expand it. 
                // Let's remove the .mask(Capsule()) on the ZStack if it was there causing clipping, 
                // or simply rely on the frame increase. The previous code had `.mask(Capsule())`.
                // I will remove `.mask(Capsule())` to allow shadows to spill out.
            }
            .frame(height: 44) // Increased height to avoid clipping
            .padding(.horizontal, 24)
        }
    }
    
    private func triggerHapticIfNeeded() {
        // Find current event type
        guard let currentEvent = activeTimelineEvent(for: currentTimestamp) else { return }
        
        if lastHapticState != currentEvent.type {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            lastHapticState = currentEvent.type
        }
    }
    
    private func activeTimelineEvent(for timestamp: TimeInterval) -> RunSession.TimelineEvent? {
        let time = Date(timeIntervalSince1970: timestamp)
        // Use local timelineEvents
        let events = timelineEvents.sorted { $0.startTime < $1.startTime }
        return events.first { event in
            let end = event.endTime ?? event.startTime
            return time >= event.startTime && time <= end
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(neonGreen)
                    .frame(width: 8, height: 8)
                Text(currentEvent?.type.displayLabel ?? "Riding")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(2)
                    .foregroundColor(neonGreen)
            }
            
            HStack(alignment: .bottom, spacing: 6) {
                Text(formatSpeed(currentSpeed))
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("KM/H")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.bottom, 6)
            }
            
            HStack(spacing: 16) {
                /*
                VStack(alignment: .leading, spacing: 4) {
                    Text("ALT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                    Text(formatAltitude())
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
                */
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("DIST")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                    Text(formatDistance())
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(neonGreen.opacity(0.7), lineWidth: 1)
                )
        )
        .shadow(color: neonGreen.opacity(0.3), radius: 12, x: 0, y: 6)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = time >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: time) ?? "00:00"
    }
    
    private func formatSpeed(_ speed: Double?) -> String {
        guard let speed else { return "0" }
        return String(format: "%.0f", speed)
    }
    
    private func formatAltitude() -> String {
        guard let altitude = currentAltitude else { return "--" }
        return String(format: "%.0f m", altitude)
    }
    
    private func formatDistance() -> String {
        guard let distance = currentDistance else { return "--" }
        if distance >= 1000 {
            return String(format: "%.1f km", distance / 1000)
        }
        return String(format: "%.0f m", distance)
    }
    
    private func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lon1 = start.longitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let lon2 = end.longitude * .pi / 180
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radians = atan2(y, x)
        let degrees = radians * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }
    
    private func nearestIndex(for timestamp: TimeInterval) -> Int? {
        let timestamps = effectiveRouteTimestamps
        guard !timestamps.isEmpty else { return nil }
        var low = 0
        var high = timestamps.count - 1
        
        while low < high {
            let mid = (low + high) / 2
            if timestamps[mid] < timestamp {
                low = mid + 1
            } else {
                high = mid
            }
        }
        
        let clamped = max(0, min(timestamps.count - 1, low))
        if clamped > 0 {
            let prev = clamped - 1
            let prevDiff = abs(timestamps[prev] - timestamp)
            let currDiff = abs(timestamps[clamped] - timestamp)
            return prevDiff < currDiff ? prev : clamped
        }
        return clamped
    }
}

private struct ToggleRow: View {
    let title: String
    let icon: String // Added icon
    @Binding var isOn: Bool
    let accent: Color
    
    var body: some View {
        HStack {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18)) // Slightly larger for clarity
                    .foregroundColor(.white.opacity(0.6))
                
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isOn ? .white : .white.opacity(0.7))
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(accent)
                .scaleEffect(0.8) // Match new design's smaller toggle feel
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(isOn ? 0.1 : 0), lineWidth: 1)
        )
    }
}

private struct ViewModeRow: View {
    @Binding var selectedMode: MapViewMode
    let isProUnlocked: Bool
    let accent: Color
    
    var body: some View {
        HStack(spacing: 8) {
            viewModeButton(title: "2D", mode: .twoD, locked: false)
        }
    }
    
    private func viewModeButton(title: String, mode: MapViewMode, locked: Bool) -> some View {
        Button(action: {
            guard !locked else { return }
            selectedMode = mode
        }) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .foregroundColor(selectedMode == mode ? .black : .white.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selectedMode == mode ? accent : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .disabled(locked)
    }
}

private struct HeatmapRow: View {
    let title: String
    let icon: String
    let mode: HeatmapMode
    @Binding var selectedMode: HeatmapMode
    let isProUnlocked: Bool
    let accent: Color
    
    var body: some View {
        let locked = !isProUnlocked && mode != .off
        Button(action: {
            guard !locked else { return }
            selectedMode = mode
        }) {
            HStack {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.6))
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(selectedMode == mode ? .white : .white.opacity(0.7))
                }
                Spacer()
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.yellow)
                } else {
                    Image(systemName: selectedMode == mode ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(selectedMode == mode ? accent : .white.opacity(0.3))
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(selectedMode == mode ? 0.15 : 0), lineWidth: 1)
            )
        }
        .disabled(locked)
    }
}

private struct ProLayerRow<Content: View>: View {
    let title: String
    let locked: Bool
    let visual: () -> Content
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
            
            Spacer()
            
            // Visual Container
            ZStack {
                visual()
                    .frame(width: 40, height: 20)
                    .blur(radius: 1) // Slight blur for 'locked' effect
                
                Color.black.opacity(0.3)
                
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                }
            }
            .frame(width: 56, height: 32)
            .background(Color.black)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .padding(10)
        .background(Color.black.opacity(0.4))
        .cornerRadius(8)
    }
}

// Removed LockedRow as it is replaced by ProLayerRow for this specific design
// private struct LockedRow ... (Old implementation removed)

private struct MapControlButton: View {
    let systemName: String
    let accent: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Color.black.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: accent.opacity(0.4), radius: 6)
        }
    }
}

private struct AnalysisLockOverlay: View {
    let accent: Color
    let onClose: () -> Void
    let onUnlock: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            
            VStack {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                Spacer()
            }
            
            VStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.yellow)
                Text("PRO ANALYSIS")
                    .font(.system(size: 14, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.white)
                Text("run_detail.analysis_lock_desc")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
                Button(action: onUnlock) {
                    HStack(spacing: 6) {
                        Text("UNLOCK PRO")
                            .font(.system(size: 12, weight: .bold))
                            .tracking(1)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(accent)
                    .cornerRadius(10)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.black.opacity(0.7))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
    }
}

// MARK: - Helper Structs (Restored)



struct MapViewRepresentable: UIViewRepresentable {
    let region: MKCoordinateRegion
    let coordinates: [CLLocationCoordinate2D]
    let lineColor: UIColor
    let runStartIndices: [Int]
    let timelineEvents: [RunSession.TimelineEvent]
    let routeTimestamps: [TimeInterval]
    let routeStates: [RunSession.TimelineEvent.EventType]
    let speeds: [Double]
    let maxSpeed: Double
    let showRoutePath: Bool
    let showStatusSegments: Bool
    let viewMode: MapViewMode
    let heatmapMode: HeatmapMode
    let heatmapValues: [Double]
    let maxHeatmapValue: Double
    let headingDegrees: Double?
    let highlightCoordinate: CLLocationCoordinate2D?
    let currentTimestamp: TimeInterval?
    let currentIndex: Int?
    @Binding var mapControlAction: MapControlAction?
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = true
        mapView.isScrollEnabled = true
        mapView.isZoomEnabled = true
        mapView.setRegion(region, animated: false)
        applyViewMode(
            viewMode,
            to: mapView,
            regionCenter: region.center,
            headingDegrees: headingDegrees,
            anchorCoordinate: highlightCoordinate,
            animated: false
        )
        context.coordinator.hasSetRegion = true
        context.coordinator.lastCoordinatesCount = coordinates.count
        mapView.overrideUserInterfaceStyle = .dark
        return mapView
    }
    
    func updateUIView(_ view: MKMapView, context: Context) {
        let needsRegionReset = context.coordinator.needsRegionReset
            || !context.coordinator.hasSetRegion
            || context.coordinator.lastCoordinatesCount != coordinates.count

        let useHeatmap = heatmapMode != .off
        let activeIndex = resolveActiveIndex()
        let activeStateSegment = activeSegmentByState(activeIndex)
        let activeEvent = activeTimelineEvent(for: currentTimestamp)
        let activeSignature = buildActiveSignature(
            activeStateSegment: activeStateSegment,
            activeEvent: activeEvent,
            activeIndex: activeIndex
        )
        
        if needsRegionReset {
            view.setRegion(region, animated: false)
            context.coordinator.hasSetRegion = true
            context.coordinator.lastCoordinatesCount = coordinates.count
            context.coordinator.needsRegionReset = false
        }
        
        let headingChanged = context.coordinator.lastHeading != headingDegrees
        if context.coordinator.lastViewMode != viewMode || needsRegionReset || (viewMode == .threeD && headingChanged) {
            applyViewMode(
                viewMode,
                to: view,
                regionCenter: region.center,
                headingDegrees: headingDegrees,
                anchorCoordinate: highlightCoordinate,
                animated: true
            )
            context.coordinator.lastViewMode = viewMode
            context.coordinator.lastHeading = headingDegrees
        }
        
        if let action = mapControlAction {
            handleMapControl(action, in: view)
            DispatchQueue.main.async {
                mapControlAction = nil
            }
        }
        
        // Optimize Overlays: Only rebuild if toggles changed or empty
        let shouldRebuildOverlays = 
            view.overlays.isEmpty ||
            context.coordinator.lastShowRoutePath != showRoutePath ||
            context.coordinator.lastShowStatusSegments != showStatusSegments ||
            context.coordinator.lastHeatmapMode != heatmapMode ||
            context.coordinator.lastActiveSignature != activeSignature
        
        if shouldRebuildOverlays {
            view.removeOverlays(view.overlays)
            
            if showRoutePath {
                // Add Polylines
                let canUseTimeline = !timelineEvents.isEmpty && routeTimestamps.count == coordinates.count
                
                func addRidingSegment(_ segmentCoords: [CLLocationCoordinate2D], startIndex: Int, endIndex: Int, isActive: Bool) {
                    let segmentHeatValues: [Double]
                    if useHeatmap, !heatmapValues.isEmpty, heatmapValues.count >= endIndex {
                        segmentHeatValues = Array(heatmapValues[startIndex..<endIndex])
                    } else {
                        segmentHeatValues = []
                    }
                    
                    if isActive, useHeatmap, !segmentHeatValues.isEmpty && segmentHeatValues.count == segmentCoords.count {
                        let colors = segmentHeatValues.map { heatmapToUIColor($0, maxValue: maxHeatmapValue, mode: heatmapMode) }
                        let polyline = GradientPolyline(coordinates: segmentCoords, count: segmentCoords.count)
                        polyline.strokeColors = colors
                        polyline.title = "ActiveHeatmap"
                        view.addOverlay(polyline)
                    } else {
                        let polyline = MKPolyline(coordinates: segmentCoords, count: segmentCoords.count)
                        polyline.title = isActive ? "ActiveRoute" : "DimRoute"
                        view.addOverlay(polyline)
                    }
                }
                
                func addStyledSegment(_ segmentCoords: [CLLocationCoordinate2D], title: String, isActive: Bool) {
                    let polyline = MKPolyline(coordinates: segmentCoords, count: segmentCoords.count)
                    polyline.title = isActive ? "Active\(title)" : "Dim\(title)"
                    view.addOverlay(polyline)
                }
                
                if routeStates.count == coordinates.count {
                    // 샘플별 상태 기반 분할 렌더링
                    var segmentStart = 0
                    var currentType = routeStates.first ?? .unknown
                    
                    func flushSegment(endIndex: Int) {
                        guard endIndex > segmentStart else { return }
                        let segmentCoords = Array(coordinates[segmentStart..<endIndex])
                        guard segmentCoords.count > 1 else { return }
                        let isActive = activeStateSegment?.start == segmentStart && activeStateSegment?.end == endIndex && activeStateSegment?.type == currentType
                        
                        switch currentType {
                        case .riding:
                            addRidingSegment(segmentCoords, startIndex: segmentStart, endIndex: endIndex, isActive: isActive)
                        case .lift:
                            if showStatusSegments {
                                addStyledSegment(segmentCoords, title: "Lift", isActive: isActive)
                            } else {
                                addRidingSegment(segmentCoords, startIndex: segmentStart, endIndex: endIndex, isActive: isActive)
                            }
                        case .rest, .pause:
                            if showStatusSegments {
                                addStyledSegment(segmentCoords, title: "Rest", isActive: isActive)
                            }
                        case .unknown:
                            if showStatusSegments {
                                addStyledSegment(segmentCoords, title: "Unknown", isActive: isActive)
                            } else {
                                addRidingSegment(segmentCoords, startIndex: segmentStart, endIndex: endIndex, isActive: isActive)
                            }
                        }
                    }
                    
                    for index in 1..<routeStates.count {
                        let nextType = routeStates[index]
                        if nextType != currentType {
                            flushSegment(endIndex: index)
                            segmentStart = index
                            currentType = nextType
                        }
                    }
                    flushSegment(endIndex: routeStates.count)
                } else if canUseTimeline {
                    let sortedEvents = timelineEvents.sorted { $0.startTime < $1.startTime }
                    var index = 0
                    
                    for event in sortedEvents {
                        let isActive = isActiveEvent(event, activeEvent: activeEvent)
                        let startTs = event.startTime.timeIntervalSince1970
                        let endTs = (event.endTime ?? event.startTime).timeIntervalSince1970
                        
                        while index < routeTimestamps.count && routeTimestamps[index] < startTs {
                            index += 1
                        }
                        let startIndex = index
                        
                        while index < routeTimestamps.count && routeTimestamps[index] <= endTs {
                            index += 1
                        }
                        let endIndex = index
                        
                        if endIndex > startIndex {
                            let segmentCoords = Array(coordinates[startIndex..<endIndex])
                            guard segmentCoords.count > 1 else { continue }
                            
                            switch event.type {
                            case .riding:
                                addRidingSegment(segmentCoords, startIndex: startIndex, endIndex: endIndex, isActive: isActive)
                            case .lift:
                                if showStatusSegments {
                                    addStyledSegment(segmentCoords, title: "Lift", isActive: isActive)
                                } else {
                                    addRidingSegment(segmentCoords, startIndex: startIndex, endIndex: endIndex, isActive: isActive)
                                }
                            case .rest, .pause:
                                if showStatusSegments {
                                    addStyledSegment(segmentCoords, title: "Rest", isActive: isActive)
                                }
                            case .unknown:
                                if showStatusSegments {
                                    addStyledSegment(segmentCoords, title: "Unknown", isActive: isActive)
                                } else {
                                    addRidingSegment(segmentCoords, startIndex: startIndex, endIndex: endIndex, isActive: isActive)
                                }
                            }
                        }
                    }
                } else {
                    let sortedIndices = runStartIndices.sorted()
                    let activeRun = activeRunRange(activeIndex: activeIndex, runStartIndices: sortedIndices)
                    
                    for (i, startIndex) in sortedIndices.enumerated() {
                        let endIndex = (i + 1 < sortedIndices.count) ? sortedIndices[i+1] : coordinates.count
                        let isActive = activeRun?.start == startIndex && activeRun?.end == endIndex
                        
                        if endIndex > startIndex {
                            let segmentCoords = Array(coordinates[startIndex..<endIndex])
                            if segmentCoords.count > 1 {
                                addRidingSegment(segmentCoords, startIndex: startIndex, endIndex: endIndex, isActive: isActive)
                            }
                        }
                        
                        // Add Lift Line (Dashed)
                        if i > 0 {
                            let prevLastIdx = startIndex - 1
                            if prevLastIdx >= 0 && prevLastIdx < coordinates.count && startIndex < coordinates.count {
                                let p1 = coordinates[prevLastIdx]
                                let p2 = coordinates[startIndex]
                                let liftPolyline = MKPolyline(coordinates: [p1, p2], count: 2)
                                liftPolyline.title = "DimLift"
                                view.addOverlay(liftPolyline)
                            }
                        }
                    }
                }
            } // end if showRoutePath
            
            // Update coordinator state
            context.coordinator.lastShowRoutePath = showRoutePath
            context.coordinator.lastShowStatusSegments = showStatusSegments
            context.coordinator.lastHeatmapMode = heatmapMode
            context.coordinator.lastActiveSignature = activeSignature
        }
        
        // Always update annotations (optimized)
        // Note: we do NOT clear annotations here, preventing flickering
        updateAnnotations(in: view)
    }
    
    // 히트맵 컬러 계산 (공통 팔레트 + 모드별 매핑)
    func heatmapToUIColor(_ value: Double, maxValue: Double, mode: HeatmapMode) -> UIColor {
        switch mode {
        case .gForce:
            return gForceBandColor(for: value)
        default:
            let ratio = maxValue > 0 ? value / maxValue : 0
            return heatmapPaletteColor(ratio)
        }
    }

    private func gForceBandColor(for value: Double) -> UIColor {
        // G-Force 밴딩: 1.2 / 1.4 / 1.7 기준 (팔레트 색상만 공유)
        if value >= 1.7 {
            return heatmapPaletteColor(1.0)
        }
        if value >= 1.4 {
            return heatmapPaletteColor(0.8)
        }
        if value >= 1.2 {
            return heatmapPaletteColor(0.6)
        }
        if value > 1.0 {
            return heatmapPaletteColor(0.4)
        }
        return heatmapPaletteColor(0.15)
    }

    private func heatmapPaletteColor(_ ratio: Double) -> UIColor {
        let colors = heatmapPalette
        let clamped = min(max(ratio, 0), 1)
        guard colors.count >= 2 else {
            return colors.first ?? UIColor.white
        }

        let scaled = clamped * Double(colors.count - 1)
        let index = Int(scaled)
        let nextIndex = min(index + 1, colors.count - 1)
        let t = CGFloat(scaled - Double(index))
        return blend(colors[index], colors[nextIndex], t: t)
    }

    private var heatmapPalette: [UIColor] {
        [
            UIColor(red: 0.10, green: 0.14, blue: 0.25, alpha: 1.0), // Deep Blue
            UIColor(red: 0.00, green: 0.80, blue: 0.95, alpha: 1.0), // Cyan
            UIColor(red: 107/255, green: 249/255, blue: 6/255, alpha: 1.0), // Neon Green
            UIColor(red: 1.0, green: 0.9, blue: 0.2, alpha: 1.0), // Yellow
            UIColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0) // Red
        ]
    }

    private func blend(_ left: UIColor, _ right: UIColor, t: CGFloat) -> UIColor {
        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        var r2: CGFloat = 0
        var g2: CGFloat = 0
        var b2: CGFloat = 0
        var a2: CGFloat = 0
        left.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        right.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)

        let r = r1 + (r2 - r1) * t
        let g = g1 + (g2 - g1) * t
        let b = b1 + (b2 - b1) * t
        let a = a1 + (a2 - a1) * t
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }

    private func resolveActiveIndex() -> Int? {
        if let currentIndex, currentIndex >= 0, currentIndex < coordinates.count {
            return currentIndex
        }
        guard let timestamp = currentTimestamp else { return nil }
        guard routeTimestamps.count == coordinates.count, !routeTimestamps.isEmpty else { return nil }
        return nearestIndex(for: timestamp, in: routeTimestamps)
    }

    private func nearestIndex(for timestamp: TimeInterval, in timestamps: [TimeInterval]) -> Int? {
        guard !timestamps.isEmpty else { return nil }
        var low = 0
        var high = timestamps.count - 1
        
        while low < high {
            let mid = (low + high) / 2
            if timestamps[mid] < timestamp {
                low = mid + 1
            } else {
                high = mid
            }
        }
        
        let clamped = max(0, min(timestamps.count - 1, low))
        if clamped > 0 {
            let prev = clamped - 1
            let prevDiff = abs(timestamps[prev] - timestamp)
            let currDiff = abs(timestamps[clamped] - timestamp)
            return prevDiff < currDiff ? prev : clamped
        }
        return clamped
    }

    private func activeSegmentByState(_ index: Int?) -> (start: Int, end: Int, type: RunSession.TimelineEvent.EventType)? {
        guard let index,
              routeStates.count == coordinates.count,
              index >= 0,
              index < routeStates.count else { return nil }
        let type = routeStates[index]
        var start = index
        var end = index + 1
        while start > 0 && routeStates[start - 1] == type {
            start -= 1
        }
        while end < routeStates.count && routeStates[end] == type {
            end += 1
        }
        return (start, end, type)
    }

    private func activeTimelineEvent(for timestamp: TimeInterval?) -> RunSession.TimelineEvent? {
        guard let timestamp, !timelineEvents.isEmpty else { return nil }
        let time = Date(timeIntervalSince1970: timestamp)
        let sortedEvents = timelineEvents.sorted { $0.startTime < $1.startTime }
        return sortedEvents.first { event in
            let end = event.endTime ?? event.startTime
            return time >= event.startTime && time <= end
        }
    }

    private func isActiveEvent(_ event: RunSession.TimelineEvent, activeEvent: RunSession.TimelineEvent?) -> Bool {
        guard let activeEvent else { return false }
        let end = event.endTime ?? event.startTime
        let activeEnd = activeEvent.endTime ?? activeEvent.startTime
        return event.type == activeEvent.type
            && event.startTime == activeEvent.startTime
            && end == activeEnd
    }

    private func activeRunRange(activeIndex: Int?, runStartIndices: [Int]) -> (start: Int, end: Int)? {
        guard let activeIndex, !runStartIndices.isEmpty else { return nil }
        for (i, startIndex) in runStartIndices.enumerated() {
            let endIndex = (i + 1 < runStartIndices.count) ? runStartIndices[i + 1] : coordinates.count
            if activeIndex >= startIndex && activeIndex < endIndex {
                return (startIndex, endIndex)
            }
        }
        return nil
    }

    private func buildActiveSignature(
        activeStateSegment: (start: Int, end: Int, type: RunSession.TimelineEvent.EventType)?,
        activeEvent: RunSession.TimelineEvent?,
        activeIndex: Int?
    ) -> String {
        if let segment = activeStateSegment {
            return "state-\(segment.type)-\(segment.start)-\(segment.end)"
        }
        if let activeEvent {
            let end = activeEvent.endTime ?? activeEvent.startTime
            return "event-\(activeEvent.type)-\(Int(activeEvent.startTime.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))"
        }
        let sortedIndices = runStartIndices.sorted()
        if let activeRun = activeRunRange(activeIndex: activeIndex, runStartIndices: sortedIndices) {
            return "run-\(activeRun.start)-\(activeRun.end)"
        }
        return "none"
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func applyViewMode(
        _ mode: MapViewMode,
        to mapView: MKMapView,
        regionCenter: CLLocationCoordinate2D,
        headingDegrees: Double?,
        anchorCoordinate: CLLocationCoordinate2D?,
        animated: Bool
    ) {
        let configuration = MKStandardMapConfiguration()
        configuration.elevationStyle = .flat
        configuration.pointOfInterestFilter = .excludingAll
        configuration.emphasisStyle = .muted
        mapView.preferredConfiguration = configuration
        mapView.isPitchEnabled = (mode == .threeD)
        
        var camera = mapView.camera
        if mode == .threeD {
            let span = max(mapView.region.span.latitudeDelta, mapView.region.span.longitudeDelta)
            let spanMeters = max(1, span * 111_000)
            let distance = max(700, min(4200, spanMeters * 0.9))
            let heading = headingDegrees ?? camera.heading
            let target = anchorCoordinate ?? regionCenter
            let biasedCenter = offsetCoordinate(
                from: target,
                distanceMeters: 140,
                bearingDegrees: (heading + 180).truncatingRemainder(dividingBy: 360)
            )
            camera = MKMapCamera(
                lookingAtCenter: biasedCenter,
                fromDistance: distance,
                pitch: 55,
                heading: heading
            )
            mapView.setCamera(camera, animated: animated)
        } else {
            if camera.pitch != 0 {
                camera.pitch = 0
                mapView.setCamera(camera, animated: animated)
            }
        }
    }

    private func offsetCoordinate(
        from coordinate: CLLocationCoordinate2D,
        distanceMeters: Double,
        bearingDegrees: Double
    ) -> CLLocationCoordinate2D {
        let radius = 6_371_000.0
        let bearing = bearingDegrees * .pi / 180
        let lat1 = coordinate.latitude * .pi / 180
        let lon1 = coordinate.longitude * .pi / 180
        let delta = distanceMeters / radius
        let lat2 = asin(sin(lat1) * cos(delta) + cos(lat1) * sin(delta) * cos(bearing))
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(delta) * cos(lat1),
            cos(delta) - sin(lat1) * sin(lat2)
        )
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }
    
    // Optimized Annotation Update
    private func updateAnnotations(in view: MKMapView) {
        // 1. Start Annotation
        if let first = coordinates.first {
            if let annotation = view.annotations.first(where: { $0.title == "START" }) {
                if annotation.coordinate.latitude != first.latitude || annotation.coordinate.longitude != first.longitude {
                    (annotation as? MKPointAnnotation)?.coordinate = first
                }
            } else {
                let annotation = MKPointAnnotation()
                annotation.coordinate = first
                annotation.title = "START"
                view.addAnnotation(annotation)
            }
        }
        
        // 2. Finish Annotation
        if let last = coordinates.last {
            if let annotation = view.annotations.first(where: { $0.title == "FINISH" }) {
                if annotation.coordinate.latitude != last.latitude || annotation.coordinate.longitude != last.longitude {
                    (annotation as? MKPointAnnotation)?.coordinate = last
                }
            } else {
                let annotation = MKPointAnnotation()
                annotation.coordinate = last
                annotation.title = "FINISH"
                view.addAnnotation(annotation)
            }
        }
        
        // 3. Current Location Annotation
        if let current = highlightCoordinate {
            if let annotation = view.annotations.first(where: { $0.title == "CURRENT" }) {
                UIView.animate(withDuration: 0.1) {
                    (annotation as? MKPointAnnotation)?.coordinate = current
                }
            } else {
                let annotation = MKPointAnnotation()
                annotation.coordinate = current
                annotation.title = "CURRENT"
                view.addAnnotation(annotation)
            }
        } else {
            if let annotation = view.annotations.first(where: { $0.title == "CURRENT" }) {
                view.removeAnnotation(annotation)
            }
        }
        
        // Remove any stray annotations that are not START, FINISH, or CURRENT
        // (Optional: depending on other map usage, but generally safe here)
    }
    
    private func handleMapControl(_ action: MapControlAction, in mapView: MKMapView) {
        switch action {
        case .zoomIn:
            var region = mapView.region
            region.span.latitudeDelta = max(region.span.latitudeDelta * 0.6, 0.002)
            region.span.longitudeDelta = max(region.span.longitudeDelta * 0.6, 0.002)
            mapView.setRegion(region, animated: true)
        case .zoomOut:
            var region = mapView.region
            region.span.latitudeDelta = min(region.span.latitudeDelta * 1.6, 5.0)
            region.span.longitudeDelta = min(region.span.longitudeDelta * 1.6, 5.0)
            mapView.setRegion(region, animated: true)
        case .center:
            if let coordinate = highlightCoordinate ?? coordinates.first {
                mapView.setCenter(coordinate, animated: true)
            }
        }
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewRepresentable
        
        // State tracking for partial updates
        var lastShowRoutePath: Bool?
        var lastShowStatusSegments: Bool?
        var lastHeatmapMode: HeatmapMode?
        var lastViewMode: MapViewMode?
        var lastHeading: Double?
        var lastActiveSignature: String?
        var hasSetRegion: Bool = false
        var lastCoordinatesCount: Int?
        var needsRegionReset: Bool = false
        
        init(_ parent: MapViewRepresentable) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let gradientPolyline = overlay as? GradientPolyline {
                 let renderer = MKGradientPolylineRenderer(polyline: gradientPolyline)
                 let count = gradientPolyline.strokeColors.count
                 let locations = (0..<count).map { CGFloat($0) / CGFloat(max(1, count - 1)) }
                 renderer.setColors(gradientPolyline.strokeColors, locations: locations)
                 renderer.lineWidth = 4.2
                 renderer.lineCap = .round
                 renderer.lineJoin = .round
                 renderer.alpha = 0.95
                 return renderer
            } else if let polyline = overlay as? MKPolyline {
                if polyline.title == "ActiveRoute" || polyline.title == "Route" {
                    let renderer = NeonPolylineRenderer(polyline: polyline)
                    renderer.strokeColor = parent.lineColor
                    renderer.lineWidth = 3.0
                    return renderer
                }
                
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.lineCap = .round
                renderer.lineJoin = .round
                
                switch polyline.title ?? "" {
                case "ActiveLift":
                    renderer.strokeColor = .white.withAlphaComponent(0.7)
                    renderer.lineWidth = 2.6
                    renderer.lineDashPattern = [3, 4]
                case "DimLift", "Lift":
                    renderer.strokeColor = .white.withAlphaComponent(0.2)
                    renderer.lineWidth = 1.6
                    renderer.lineDashPattern = [2, 6]
                case "ActiveRest", "ActiveUnknown":
                    renderer.strokeColor = .white.withAlphaComponent(0.45)
                    renderer.lineWidth = 2.2
                    renderer.lineDashPattern = [1, 5]
                case "DimRest", "DimUnknown", "Rest", "Unknown":
                    renderer.strokeColor = .white.withAlphaComponent(0.12)
                    renderer.lineWidth = 1.4
                    renderer.lineDashPattern = [1, 6]
                case "DimRoute":
                    renderer.strokeColor = .white.withAlphaComponent(0.16)
                    renderer.lineWidth = 1.6
                default:
                    renderer.strokeColor = parent.lineColor
                    renderer.lineWidth = 3
                }
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !annotation.isKind(of: MKUserLocation.self) else { return nil }
            
            // Original logic: Use default pins for Start/Finish
            if annotation.title == "START" || annotation.title == "FINISH" {
                return nil
            }
            
            // Custom logic for CURRENT marker
            let identifier = "current"
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            
            if view == nil {
                view = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            } else {
                view?.annotation = annotation
            }
            
            view?.bounds = CGRect(x: 0, y: 0, width: 16, height: 16)
            view?.layer.cornerRadius = 8
            view?.layer.borderWidth = 2
            view?.layer.borderColor = UIColor(red: 107/255, green: 249/255, blue: 6/255, alpha: 1.0).cgColor
            view?.backgroundColor = UIColor.black
            view?.layer.shadowColor = UIColor(red: 107/255, green: 249/255, blue: 6/255, alpha: 0.6).cgColor
            view?.layer.shadowRadius = 6
            view?.layer.shadowOpacity = 0.9
            view?.layer.shadowOffset = .zero
            
            return view
        }
    }
}

// 네온 글로우 렌더러 (HTML Reference Implementation)
class NeonPolylineRenderer: MKPolylineRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        context.saveGState()
        
        // Base width corresponds to the 'Core' width (3px in HTML)
        let baseWidth = self.lineWidth / zoomScale
        let neonColor = UIColor(red: 107/255, green: 249/255, blue: 6/255, alpha: 1.0)
        
        // 1. Outer Glow (The "Blur" Effect)
        // HTML: stroke-width="12", opacity-40, filter=blur(4)
        context.setBlendMode(.screen)
        context.setLineWidth(baseWidth * 4.0) // 12px / 3px = 4x
        context.setStrokeColor(neonColor.withAlphaComponent(0.4).cgColor)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        // Add a soft shadow to simulate the gaussian blur
        context.setShadow(offset: .zero, blur: baseWidth * 2.0, color: neonColor.withAlphaComponent(0.6).cgColor)
        
        context.addPath(self.path)
        context.strokePath()
        
        // Clean shadow for next pass
        context.setShadow(offset: .zero, blur: 0, color: nil)
        
        // 2. Inner Core (The "White" Line)
        // HTML: stroke-width="3", stroke="#ffffff"
        context.setBlendMode(.normal)
        context.setLineWidth(baseWidth * 1.0)
        context.setStrokeColor(UIColor.white.cgColor)
        context.addPath(self.path)
        context.strokePath()
        
        context.restoreGState()
    }
}

// Custom Subclass to hold colors
class GradientPolyline: MKPolyline {
    var strokeColors: [UIColor] = []
}
