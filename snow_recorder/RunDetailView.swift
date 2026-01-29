import SwiftUI
import MapKit
import SwiftData
import Charts
import CoreLocation

struct RunDetailView: View {
    @Environment(\.dismiss) var dismiss
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
                        
                        // 5. Run Metrics (Per Run)
                        if !session.runMetrics.isEmpty {
                            runMetricsSection
                        }
                        
                        // 6. Timeline
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
            FullScreenMapView(
                coordinates: routeCoordinates,
                speeds: session.routeSpeeds,
                maxSpeed: session.maxSpeed,
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
        .sheet(item: $gpxFileURL) { identifiableURL in
            ShareSheet(activityItems: [identifiableURL.url])
        }
        .sheet(item: $analysisFileURL) { identifiableURL in
            ShareSheet(activityItems: [identifiableURL.url])
        }
        .sheet(item: $baroLogFileURL) { identifiableURL in
            ShareSheet(activityItems: [identifiableURL.url])
        }
        .alert("GPX Export 불가", isPresented: $showNoDataAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("이 세션에는 GPS 경로 데이터가 없습니다.")
        }
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
#if DEBUG
        .sheet(isPresented: $showDebugSheet) {
            AnalysisDebugView(session: session)
        }
#endif
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
                    if !session.routeSpeeds.isEmpty {
                        GradientRouteOverlay(coordinates: routeCoordinates, speeds: session.routeSpeeds, maxSpeed: session.maxSpeed)
                    } else {
                        MapRouteOverlay(coordinates: routeCoordinates, color: primaryColor)
                    }
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
            }
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
                guard event.type == .pause else { return event }
                var normalized = event
                normalized.type = .rest
                if normalized.detail.isEmpty {
                    normalized.detail = "휴식"
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
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "arrow.down.to.line")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("VERTICAL DROP")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
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
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 10)
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
                legendItem(color: primaryColor, label: "RIDE")
                legendItem(color: Color.white.opacity(0.2), label: "LIFT")
                legendItem(color: surfaceCard, isBorder: true, label: "REST")
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
    let coordinates: [CLLocationCoordinate2D]
    let speeds: [Double]
    let maxSpeed: Double
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
    @State private var mapViewMode: MapViewMode = FeatureFlags.proFeaturesEnabled ? .threeD : .twoD
    @State private var heatmapMode: HeatmapMode = .off
    @State private var isProUnlocked: Bool = FeatureFlags.proFeaturesEnabled
    @State private var mapControlAction: MapControlAction? = nil
    
    var body: some View {
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
                useHeatmap: heatmapMode == .speed,
                headingDegrees: currentHeading,
                highlightCoordinate: currentCoordinate,
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
    }
    
    private var neonGreen: Color {
        Color(red: 107/255, green: 249/255, blue: 6/255)
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
        if let interpolation = currentInterpolation,
           interpolation.upper < routeAltitudes.count,
           interpolation.lower < routeAltitudes.count {
            let lower = routeAltitudes[interpolation.lower]
            let upper = routeAltitudes[interpolation.upper]
            return lower + (upper - lower) * interpolation.t
        }
        guard let index = currentIndex, index < routeAltitudes.count else { return nil }
        return routeAltitudes[index]
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
            .padding(.horizontal, 16)
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
            .padding(.horizontal, 16)
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
                                isProUnlocked: isProUnlocked,
                                accent: neonGreen
                            )
                        }
                        
                        // Heatmap Section (Pro)
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
                                HeatmapRow(
                                    title: "SPEED",
                                    icon: "speedometer",
                                    mode: .speed,
                                    selectedMode: $heatmapMode,
                                    isProUnlocked: isProUnlocked,
                                    accent: neonGreen
                                )
                                HeatmapRow(
                                    title: "G-FORCE",
                                    icon: "waveform.path.ecg",
                                    mode: .gForce,
                                    selectedMode: $heatmapMode,
                                    isProUnlocked: isProUnlocked,
                                    accent: neonGreen
                                )
                                HeatmapRow(
                                    title: "EDGE/FLOW",
                                    icon: "sparkles",
                                    mode: .edgeFlow,
                                    selectedMode: $heatmapMode,
                                    isProUnlocked: isProUnlocked,
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
                            
                            // Locked Rows
                            VStack(spacing: 8) {
                                ProLayerRow(title: "Flow", locked: true) {
                                    // Dummy visual for flow
                                    Path { path in
                                        path.move(to: CGPoint(x: 0, y: 15))
                                        path.addCurve(to: CGPoint(x: 40, y: 5), control1: CGPoint(x: 15, y: 5), control2: CGPoint(x: 25, y: 20))
                                        path.addLine(to: CGPoint(x: 40, y: 20))
                                        path.addLine(to: CGPoint(x: 0, y: 20))
                                        path.closeSubpath()
                                    }
                                    .fill(LinearGradient(colors: [neonGreen, neonGreen.opacity(0.2)], startPoint: .top, endPoint: .bottom))
                                    .opacity(0.5)
                                }
                                
                                ProLayerRow(title: "G-Force", locked: true) {
                                    // Dummy visual for g-force
                                    HStack(alignment: .bottom, spacing: 2) {
                                        Capsule().fill(Color.red).frame(width: 4, height: 12)
                                        Capsule().fill(Color.yellow).frame(width: 4, height: 16)
                                        Capsule().fill(neonGreen).frame(width: 4, height: 10)
                                        Capsule().fill(Color.blue).frame(width: 4, height: 14)
                                    }
                                    .opacity(0.8)
                                }
                            }
                            .padding(4)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
                            )
                            
                            // Unlock Button
                            Button(action: {}) {
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
            
            HStack(spacing: 14) {
                statusCard
                proCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .padding(.top, 30)
        .background(
            LinearGradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
        )
    }
    
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
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 6)
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                    
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [neonGreen.opacity(0.2), neonGreen.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, width * scrubProgress), height: 6)
                        .shadow(color: neonGreen.opacity(0.8), radius: 8)
                    
                    Circle()
                        .fill(Color.black)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .stroke(neonGreen, lineWidth: 2)
                        )
                        .shadow(color: neonGreen.opacity(0.8), radius: 8)
                        .offset(x: width * scrubProgress - 11)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let progress = min(max(0, value.location.x / width), 1)
                                    scrubProgress = progress
                                }
                        )
                }
            }
            .frame(height: 30)
            .padding(.horizontal, 24)
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("ALT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                    Text(formatAltitude())
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
                
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
    
    private var proCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(neonGreen)
                .padding(10)
                .background(Circle().fill(Color.white.opacity(0.08)))
            Text("Unlock Pro Metrics")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
            Button(action: {}) {
                Text("GET PRO")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(neonGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: neonGreen.opacity(0.6), radius: 10)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
                .foregroundColor(.white.opacity(0.2))
        )
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
            viewModeButton(title: "3D", mode: .threeD, locked: !isProUnlocked)
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
    let useHeatmap: Bool
    let headingDegrees: Double?
    let highlightCoordinate: CLLocationCoordinate2D?
    @Binding var mapControlAction: MapControlAction?
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false
        mapView.isPitchEnabled = true
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
        
        if needsRegionReset {
            view.setRegion(region, animated: false)
            context.coordinator.hasSetRegion = true
            context.coordinator.lastCoordinatesCount = coordinates.count
            context.coordinator.needsRegionReset = false
        }
        
        if context.coordinator.lastViewMode != viewMode || needsRegionReset || context.coordinator.lastHeading != headingDegrees {
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
            context.coordinator.lastUseHeatmap != useHeatmap
        
        if shouldRebuildOverlays {
            view.removeOverlays(view.overlays)
            
            if showRoutePath {
                // Add Polylines
                let canUseTimeline = !timelineEvents.isEmpty && routeTimestamps.count == coordinates.count
                
                func addRidingSegment(_ segmentCoords: [CLLocationCoordinate2D], startIndex: Int, endIndex: Int) {
                    let segmentSpeeds: [Double]
                    if !speeds.isEmpty, speeds.count >= endIndex {
                        segmentSpeeds = Array(speeds[startIndex..<endIndex])
                    } else {
                        segmentSpeeds = []
                    }
                    
                    if useHeatmap, !segmentSpeeds.isEmpty && segmentSpeeds.count == segmentCoords.count {
                        let colors = segmentSpeeds.map { speedToUIColor($0, maxSpeed: maxSpeed) }
                        let polyline = GradientPolyline(coordinates: segmentCoords, count: segmentCoords.count)
                        polyline.strokeColors = colors
                        polyline.title = "Heatmap"
                        view.addOverlay(polyline)
                    } else {
                        let polyline = MKPolyline(coordinates: segmentCoords, count: segmentCoords.count)
                        polyline.title = "Route"
                        view.addOverlay(polyline)
                    }
                }
                
                func addStyledSegment(_ segmentCoords: [CLLocationCoordinate2D], title: String) {
                    let polyline = MKPolyline(coordinates: segmentCoords, count: segmentCoords.count)
                    polyline.title = title
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
                        
                        switch currentType {
                        case .riding:
                            addRidingSegment(segmentCoords, startIndex: segmentStart, endIndex: endIndex)
                        case .lift:
                            if showStatusSegments {
                                addStyledSegment(segmentCoords, title: "Lift")
                            } else {
                                addRidingSegment(segmentCoords, startIndex: segmentStart, endIndex: endIndex)
                            }
                        case .rest, .pause:
                            if showStatusSegments {
                                addStyledSegment(segmentCoords, title: "Rest")
                            }
                        case .unknown:
                            if showStatusSegments {
                                addStyledSegment(segmentCoords, title: "Unknown")
                            } else {
                                addRidingSegment(segmentCoords, startIndex: segmentStart, endIndex: endIndex)
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
                                addRidingSegment(segmentCoords, startIndex: startIndex, endIndex: endIndex)
                            case .lift:
                                if showStatusSegments {
                                    addStyledSegment(segmentCoords, title: "Lift")
                                } else {
                                    addRidingSegment(segmentCoords, startIndex: startIndex, endIndex: endIndex)
                                }
                            case .rest, .pause:
                                if showStatusSegments {
                                    addStyledSegment(segmentCoords, title: "Rest")
                                }
                            case .unknown:
                                if showStatusSegments {
                                    addStyledSegment(segmentCoords, title: "Unknown")
                                } else {
                                    addRidingSegment(segmentCoords, startIndex: startIndex, endIndex: endIndex)
                                }
                            }
                        }
                    }
                } else {
                    let sortedIndices = runStartIndices.sorted()
                    
                    for (i, startIndex) in sortedIndices.enumerated() {
                        let endIndex = (i + 1 < sortedIndices.count) ? sortedIndices[i+1] : coordinates.count
                        
                        if endIndex > startIndex {
                            let segmentCoords = Array(coordinates[startIndex..<endIndex])
                            if segmentCoords.count > 1 {
                                addRidingSegment(segmentCoords, startIndex: startIndex, endIndex: endIndex)
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
                }
            } // end if showRoutePath
            
            // Update coordinator state
            context.coordinator.lastShowRoutePath = showRoutePath
            context.coordinator.lastShowStatusSegments = showStatusSegments
            context.coordinator.lastUseHeatmap = useHeatmap
        }
        
        // Always update annotations (optimized)
        // Note: we do NOT clear annotations here, preventing flickering
        updateAnnotations(in: view)
    }
    
    // Helper for color calculation
    func speedToUIColor(_ speed: Double, maxSpeed: Double) -> UIColor {
        let ratio = maxSpeed > 0 ? speed / maxSpeed : 0
        let hue = 0.33 - (0.33 * min(max(ratio, 0), 1))
        return UIColor(hue: hue, saturation: 1.0, brightness: 1.0, alpha: 1.0)
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
            camera.pitch = 0
            camera.heading = 0
            mapView.setCamera(camera, animated: animated)
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
        var lastUseHeatmap: Bool?
        var lastViewMode: MapViewMode?
        var lastHeading: Double?
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
                 renderer.lineWidth = 4.0
                 renderer.lineCap = .round
                 renderer.lineJoin = .round
                 renderer.alpha = 0.9
                 return renderer
            } else if let polyline = overlay as? MKPolyline {
                if polyline.title == "Route" {
                    let renderer = GlowingPolylineRenderer(polyline: polyline)
                    renderer.strokeColor = parent.lineColor
                    renderer.lineWidth = 3.0
                    return renderer
                }
                
                let renderer = MKPolylineRenderer(polyline: polyline)
                
                if polyline.title == "Lift" {
                    renderer.strokeColor = .white.withAlphaComponent(0.3)
                    renderer.lineWidth = 2
                    renderer.lineDashPattern = [2, 4]
                } else if polyline.title == "Rest" || polyline.title == "Unknown" {
                    renderer.strokeColor = .white.withAlphaComponent(0.15)
                    renderer.lineWidth = 2
                    renderer.lineDashPattern = [1, 5]
                } else {
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

// 네온 글로우 렌더러
class GlowingPolylineRenderer: MKPolylineRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        context.saveGState()
        
        // 줌 스케일과 무관하게 두께 유지
        let baseWidth = self.lineWidth / zoomScale
        let neonColor = UIColor(red: 107/255, green: 249/255, blue: 6/255, alpha: 1.0)
        
        // 1. 외곽 글로우 (넓고 부드럽게)
        context.setBlendMode(.screen)
        context.setLineWidth(baseWidth * 3.2)
        context.setStrokeColor(neonColor.withAlphaComponent(0.12).cgColor)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(self.path)
        context.strokePath()
        
        // 2. 중간 글로우 (집중된 하이라이트)
        context.setLineWidth(baseWidth * 1.9)
        context.setStrokeColor(neonColor.withAlphaComponent(0.28).cgColor)
        context.addPath(self.path)
        context.strokePath()
        
        // 3. 코어 라인 (선명한 본체)
        context.setBlendMode(.normal)
        context.setLineWidth(baseWidth * 1.0)
        context.setStrokeColor(neonColor.withAlphaComponent(0.95).cgColor)
        context.setShadow(offset: .zero, blur: 0, color: nil) // 코어는 선명하게 유지
        context.addPath(self.path)
        context.strokePath()
        
        // 4. White Hot Center (Optional, for extreme brightness feel)
        context.setLineWidth(baseWidth * 0.3)
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.8).cgColor)
        context.addPath(self.path)
        context.strokePath()
        
        context.restoreGState()
    }
}

// Custom Subclass to hold colors
class GradientPolyline: MKPolyline {
    var strokeColors: [UIColor] = []
}
