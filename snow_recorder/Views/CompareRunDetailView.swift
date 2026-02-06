import SwiftUI
import SwiftData

struct CompareRunDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @EnvironmentObject private var storeManager: StoreManager
    @Query(sort: \RunSession.startTime, order: .reverse) private var sessions: [RunSession]
    
    let session: RunSession
    let metric: RunSession.RunMetric
    
    @State private var showPaywall = false
    @State private var scoreMode: ScoreMode = .edge
    @State private var showSaveToast = false
    
    private let neonGreen = Color(hex: "6bf906")
    private let alertRed = Color(hex: "fa4b38")
    private let backgroundDark = Color.black
    private let surfaceDark = Color(hex: "0f0f0f")
    private let surfaceBorder = Color(hex: "333333")
    
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                contentView(proxy: proxy)
                    .blur(radius: storeManager.isPro ? 0 : 8)
                
                if !storeManager.isPro {
                    CompareLockOverlay(
                        accent: neonGreen,
                        title: loc("compare.lock_title", "PRO COMPARISON"),
                        description: loc("compare.lock_desc", "런 비교는 PRO 전용 기능이에요."),
                        actionTitle: loc("compare.lock_cta", "UNLOCK PRO"),
                        onClose: { dismiss() },
                        onUnlock: { showPaywall = true }
                    )
                }
                
                if showSaveToast {
                    saveToast
                        .transition(.opacity)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
    
    private func contentView(proxy: GeometryProxy) -> some View {
        ZStack {
            backgroundDark.ignoresSafeArea()
            
            GridPattern()
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                headerView
                    .padding(.top, proxy.safeAreaInsets.top + 8)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .background(headerBackground)
                
                ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            metaBar
                            
                            metricGrid
                            
                            Spacer(minLength: 6)
                        }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
                
                footerView
                    .padding(.horizontal, 16)
                    .padding(.bottom, proxy.safeAreaInsets.bottom + 8)
                    .background(footerBackground)
            }
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            
            Spacer()
            
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text(loc("compare.detail.analysis_label", "ANALYSIS"))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.6))
                    Circle()
                        .fill(neonGreen)
                        .frame(width: 4, height: 4)
                        .shadow(color: neonGreen.opacity(0.8), radius: 4)
                }
                
                HStack(spacing: 8) {
                    Text(headerDateText)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                    Text("//")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                    Text(loc("compare.detail.season_avg_label", "SEASON AVG"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(neonGreen)
                }
                .tracking(2)
            }
            
            Spacer()
            
            Button(action: { saveCardImage() }) {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(neonGreen)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.04))
                    .clipShape(Circle())
            }
        }
    }
    
    private var headerBackground: some View {
        LinearGradient(
            colors: [backgroundDark.opacity(0.96), backgroundDark.opacity(0.9), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
    
    private var saveToast: some View {
        VStack {
            Spacer()
            Text(loc("compare.save_toast", "저장 완료"))
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
                .foregroundColor(.white)
                .overlay(
                    Capsule()
                        .stroke(neonGreen.opacity(0.4), lineWidth: 1)
                )
                .padding(.bottom, 20)
        }
        .animation(.easeOut(duration: 0.2), value: showSaveToast)
    }
    
    // MARK: - Meta
    private var metaBar: some View {
        HStack {
            Text(String(format: loc("compare.detail.run_id_format", "RUN_ID: %@"), runIdValue))
            Spacer()
            Text(loc("compare.detail.system_ready", "SYSTEM_READY"))
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundColor(.white.opacity(0.45))
        .tracking(1.5)
        .padding(.bottom, 10)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    // MARK: - Metrics
    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            metricCard(
                title: loc("compare.detail.metric_max_speed", "MAX SPEED"),
                valueText: formatNumber(metric.maxSpeed, digits: 0),
                unitText: "km/h",
                avgValue: seasonAverage?.maxSpeed,
                currentValue: metric.maxSpeed,
                avgDisplay: formatNumber(seasonAverage?.maxSpeed, digits: 0),
                deltaMode: .percent
            )
            
            metricCard(
                title: loc("compare.detail.metric_avg_speed", "AVG SPEED"),
                valueText: formatNumber(metric.avgSpeed, digits: 0),
                unitText: "km/h",
                avgValue: seasonAverage?.avgSpeed,
                currentValue: metric.avgSpeed,
                avgDisplay: formatNumber(seasonAverage?.avgSpeed, digits: 0),
                deltaMode: .percent
            )
            
            metricCard(
                title: loc("compare.detail.metric_distance", "DISTANCE"),
                valueText: formatDistance(metric.distance),
                unitText: "km",
                avgValue: seasonAverage?.distance,
                currentValue: metric.distance,
                avgDisplay: formatDistance(seasonAverage?.distance),
                deltaMode: .percent
            )
            
            metricCard(
                title: loc("compare.detail.metric_vert_drop", "VERT DROP"),
                valueText: formatNumber(metric.verticalDrop, digits: 0),
                unitText: "m",
                avgValue: seasonAverage?.verticalDrop,
                currentValue: metric.verticalDrop,
                avgDisplay: formatNumber(seasonAverage?.verticalDrop, digits: 0),
                deltaMode: .percent
            )
            
            metricCard(
                title: loc("compare.detail.metric_duration", "DURATION"),
                valueText: formatDuration(metric.duration),
                unitText: "min",
                avgValue: seasonAverage?.duration,
                currentValue: metric.duration,
                avgDisplay: formatDuration(seasonAverage?.duration),
                deltaMode: .percent
            )
            
            scoreToggleCard
        }
    }
    
    private var scoreToggleCard: some View {
        let isEdge = scoreMode == .edge
        let title = isEdge
            ? loc("compare.detail.metric_edge_score", "EDGE SCORE")
            : loc("compare.detail.metric_flow_score", "FLOW SCORE")
        let currentValue = isEdge ? Double(metric.edgeScore) : Double(metric.flowScore)
        let avgValue = isEdge ? seasonAverage?.edgeScore : seasonAverage?.flowScore
        let valueText = isEdge ? "\(metric.edgeScore)" : "\(metric.flowScore)"
        let avgDisplay = avgValue.map { "\(Int($0))" }
        let avgText = avgDisplay.map { String(format: loc("compare.detail.vs_avg_format", "vs %@ avg"), $0) }
            ?? loc("compare.detail.vs_avg_missing", "vs -- avg")
        let delta = deltaText(current: currentValue, avg: avgValue, mode: .value)
        let deltaColor = delta.isPositive ? neonGreen : alertRed
        
        return CompareScoreToggleCard(
            edgeLabel: loc("compare.detail.edge_tab", "EDGE"),
            flowLabel: loc("compare.detail.flow_tab", "FLOW"),
            valueText: valueText,
            unitText: "/1000",
            avgText: avgText,
            deltaText: delta.text,
            deltaColor: deltaColor,
            currentValue: currentValue,
            avgValue: avgValue ?? 0,
            neonGreen: neonGreen,
            surfaceDark: surfaceDark,
            surfaceBorder: surfaceBorder,
            mode: $scoreMode
        )
    }
    
    private func metricCard(
        title: String,
        valueText: String,
        unitText: String,
        avgValue: Double?,
        currentValue: Double,
        avgDisplay: String?,
        deltaMode: DeltaMode
    ) -> some View {
        let avgText = avgDisplay.map { String(format: loc("compare.detail.vs_avg_format", "vs %@ avg"), $0) }
            ?? loc("compare.detail.vs_avg_missing", "vs -- avg")
        let delta = deltaText(current: currentValue, avg: avgValue, mode: deltaMode)
        let deltaColor = delta.isPositive ? neonGreen : alertRed
        let barValues = (avg: max(avgValue ?? 0, 0), current: max(currentValue, 0))
        
        return CompareMetricCard(
            title: title,
            valueText: valueText,
            unitText: unitText,
            avgText: avgText,
            deltaText: delta.text,
            deltaColor: deltaColor,
            currentValue: barValues.current,
            avgValue: barValues.avg,
            neonGreen: neonGreen,
            surfaceDark: surfaceDark,
            surfaceBorder: surfaceBorder
        )
    }
    
    // MARK: - Footer
    private var footerView: some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(Color.white.opacity(0.1))
                .frame(width: 60, height: 4)
            
            HStack(spacing: 8) {
                Text(String(format: loc("compare.detail.footer_sys_id_format", "SYS_ID: %@"), sysIdValue))
                Text("•")
                    .foregroundColor(neonGreen)
                Text(String(format: loc("compare.detail.footer_total_runs_format", "TOTAL SEASON RUNS: %d"), seasonRunCount))
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.5))
        }
        .padding(.vertical, 14)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1),
            alignment: .top
        )
    }
    
    private var footerBackground: some View {
        LinearGradient(
            colors: [backgroundDark, backgroundDark.opacity(0.95), backgroundDark.opacity(0.9)],
            startPoint: .bottom,
            endPoint: .top
        )
        .ignoresSafeArea()
    }
    
    // MARK: - Data
    private var seasonRunMetrics: [RunSession.RunMetric] {
        guard let season = seasonInfo(for: metric.startTime) else { return [] }
        let seasonSessions = sessions.filter { $0.startTime >= season.start && $0.startTime <= season.end }
        return seasonSessions.flatMap { $0.runMetrics }
    }
    
    private var seasonAverage: SeasonAverage? {
        let runs = seasonRunMetrics
        guard !runs.isEmpty else { return nil }
        let count = Double(runs.count)
        let maxSpeed = runs.reduce(0) { $0 + $1.maxSpeed } / count
        let avgSpeed = runs.reduce(0) { $0 + $1.avgSpeed } / count
        let distance = runs.reduce(0) { $0 + $1.distance } / count
        let verticalDrop = runs.reduce(0) { $0 + $1.verticalDrop } / count
        let duration = runs.reduce(0) { $0 + $1.duration } / count
        let edgeScore = runs.reduce(0) { $0 + Double($1.edgeScore) } / count
        let flowScore = runs.reduce(0) { $0 + Double($1.flowScore) } / count
        return SeasonAverage(
            maxSpeed: maxSpeed,
            avgSpeed: avgSpeed,
            distance: distance,
            verticalDrop: verticalDrop,
            duration: duration,
            edgeScore: edgeScore,
            flowScore: flowScore
        )
    }
    
    private var seasonRunCount: Int {
        seasonRunMetrics.count
    }
    
    private var runIdValue: String {
        let runText = String(format: "%02d", metric.runNumber)
        let idText = session.id.uuidString.replacingOccurrences(of: "-", with: "").uppercased()
        return "\(runText)_\(idText.prefix(3))"
    }
    
    private var sysIdValue: String {
        let idText = session.id.uuidString.replacingOccurrences(of: "-", with: "").uppercased()
        return "SR-\(idText.prefix(2))"
    }
    
    private var headerDateText: String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = locale.identifier.hasPrefix("ko") ? "M월 d일" : "MMM d"
        return formatter.string(from: metric.startTime).uppercased()
    }
    
    private func formatNumber(_ value: Double?, digits: Int) -> String? {
        guard let value else { return nil }
        return String(format: "%.\(digits)f", value)
    }
    
    private func formatNumber(_ value: Double, digits: Int) -> String {
        return String(format: "%.\(digits)f", value)
    }
    
    private func formatDistance(_ meters: Double?) -> String? {
        guard let meters else { return nil }
        let km = meters / 1000.0
        return String(format: "%.1f", km)
    }
    
    private func formatDistance(_ meters: Double) -> String {
        let km = meters / 1000.0
        return String(format: "%.1f", km)
    }
    
    private func formatDuration(_ seconds: Double?) -> String? {
        guard let seconds else { return nil }
        return formatDuration(seconds)
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = max(Int(round(seconds)), 0)
        let minutes = totalSeconds / 60
        let remainder = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }
    
    private func deltaText(current: Double, avg: Double?, mode: DeltaMode) -> (text: String?, isPositive: Bool) {
        guard let avg, avg > 0 else { return (nil, true) }
        let diff = current - avg
        switch mode {
        case .percent:
            let percent = (diff / avg) * 100
            let sign = percent >= 0 ? "+" : "-"
            return ("\(sign)\(Int(round(abs(percent))))%", percent >= 0)
        case .value:
            let sign = diff >= 0 ? "+" : "-"
            return ("\(sign)\(Int(round(abs(diff))))", diff >= 0)
        }
    }
    
    private func loc(_ key: String, _ fallback: String) -> String {
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
    
    private func seasonInfo(for date: Date) -> SeasonInfo? {
        let calendar = kstCalendar
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        
        let startYear: Int
        let endYear: Int
        
        if month >= 11 {
            startYear = year
            endYear = year + 1
        } else if month <= 3 {
            startYear = year - 1
            endYear = year
        } else {
            return nil
        }
        
        let start = makeKSTDate(year: startYear, month: 11, day: 1, hour: 0, minute: 0, second: 0)
        let end = makeKSTDate(year: endYear, month: 3, day: 31, hour: 23, minute: 59, second: 59)
        let label = String(format: "%02d/%02d", startYear % 100, endYear % 100)
        let id = String(format: "%04d_%04d", startYear, endYear)
        return SeasonInfo(id: id, start: start, end: end, label: label)
    }
    
    private var kstCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return calendar
    }
    
    private func makeKSTDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = TimeZone(identifier: "Asia/Seoul")
        return kstCalendar.date(from: components) ?? Date()
    }
    
    @MainActor
    private func saveCardImage() {
        let renderer = ImageRenderer(content: exportCardView())
        renderer.scale = UIScreen.main.scale
        if let image = renderer.uiImage {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            withAnimation(.easeOut(duration: 0.2)) {
                showSaveToast = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation(.easeOut(duration: 0.2)) {
                    showSaveToast = false
                }
            }
        }
    }
    
    private func exportCardView() -> some View {
        ZStack(alignment: .bottom) {
            ZStack {
                backgroundDark
                GridPattern()
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
                
                VStack(spacing: 18) {
                    exportHeaderView
                        .padding(.top, 18)
                    
                    metaBar
                    
                    metricGrid
                    
                    footerView
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
            .frame(width: 360)
            .background(backgroundDark)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }
    
    private var exportHeaderView: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(loc("compare.detail.analysis_label", "ANALYSIS"))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(3)
                    .foregroundColor(.white.opacity(0.6))
                Circle()
                    .fill(neonGreen)
                    .frame(width: 4, height: 4)
                    .shadow(color: neonGreen.opacity(0.8), radius: 4)
            }
            
            HStack(spacing: 8) {
                Text(headerDateText)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                Text("//")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                Text(loc("compare.detail.season_avg_label", "SEASON AVG"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(neonGreen)
            }
            .tracking(2)
        }
    }
}

private struct SeasonAverage {
    let maxSpeed: Double
    let avgSpeed: Double
    let distance: Double
    let verticalDrop: Double
    let duration: Double
    let edgeScore: Double
    let flowScore: Double
}

private struct SeasonInfo: Identifiable, Hashable {
    let id: String
    let start: Date
    let end: Date
    let label: String
}

private enum DeltaMode {
    case percent
    case value
}

private enum ScoreMode {
    case edge
    case flow
}

private struct CompareMetricCard: View {
    let title: String
    let valueText: String
    let unitText: String
    let avgText: String
    let deltaText: String?
    let deltaColor: Color
    let currentValue: Double
    let avgValue: Double
    let neonGreen: Color
    let surfaceDark: Color
    let surfaceBorder: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundColor(.white.opacity(0.5))
            
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(valueText)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                Text(unitText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
            
            Text(avgText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
            
            Spacer()
            
            HStack(alignment: .bottom, spacing: 8) {
                if let deltaText {
                    Text(deltaText)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(deltaColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(deltaColor.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(deltaColor.opacity(0.4), lineWidth: 1)
                        )
                        .cornerRadius(6)
                } else {
                    Text("--")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.3))
                }
                
                Spacer()
                
                MiniBarsView(
                    avgValue: avgValue,
                    currentValue: currentValue,
                    neonGreen: neonGreen
                )
                .frame(height: 28)
            }
        }
        .padding(14)
        .frame(height: 160)
        .background(surfaceDark)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(surfaceBorder, lineWidth: 1)
        )
        .cornerRadius(12)
    }
}

private struct MiniBarsView: View {
    let avgValue: Double
    let currentValue: Double
    let neonGreen: Color
    
    var body: some View {
        let maxValue = max(avgValue, currentValue, 1)
        let avgHeight = max(6, (avgValue / maxValue) * 26)
        let currentHeight = max(6, (currentValue / maxValue) * 26)
        
        return HStack(alignment: .bottom, spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.2))
                .frame(width: 6, height: avgHeight)
            RoundedRectangle(cornerRadius: 2)
                .fill(neonGreen)
                .frame(width: 6, height: currentHeight)
                .shadow(color: neonGreen.opacity(0.6), radius: 6)
        }
    }
}

private struct CompareScoreToggleCard: View {
    let edgeLabel: String
    let flowLabel: String
    let valueText: String
    let unitText: String
    let avgText: String
    let deltaText: String?
    let deltaColor: Color
    let currentValue: Double
    let avgValue: Double
    let neonGreen: Color
    let surfaceDark: Color
    let surfaceBorder: Color
    @Binding var mode: ScoreMode
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                toggleButton(label: edgeLabel, isSelected: mode == .edge) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        mode = .edge
                    }
                }
                toggleButton(label: flowLabel, isSelected: mode == .flow) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        mode = .flow
                    }
                }
                Spacer()
            }
            
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(valueText)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                Text(unitText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
            
            Text(avgText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
            
            Spacer()
            
            HStack(alignment: .bottom, spacing: 8) {
                if let deltaText {
                    Text(deltaText)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(deltaColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(deltaColor.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(deltaColor.opacity(0.4), lineWidth: 1)
                        )
                        .cornerRadius(6)
                } else {
                    Text("--")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.3))
                }
                
                Spacer()
                
                MiniBarsView(
                    avgValue: avgValue,
                    currentValue: currentValue,
                    neonGreen: neonGreen
                )
                .frame(height: 28)
            }
        }
        .padding(14)
        .frame(height: 160)
        .background(surfaceDark)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(surfaceBorder, lineWidth: 1)
        )
        .cornerRadius(12)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: mode)
    }
    
    private func toggleButton(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(isSelected ? .black : .white.opacity(0.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? neonGreen : Color.white.opacity(0.05))
                .overlay(
                    Capsule()
                        .stroke(isSelected ? neonGreen.opacity(0.7) : Color.white.opacity(0.08), lineWidth: 1)
                )
                .clipShape(Capsule())
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
    }
}

private struct CompareLockOverlay: View {
    let accent: Color
    let title: String
    let description: String
    let actionTitle: String
    let onClose: () -> Void
    let onUnlock: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
            
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
            
            VStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.yellow)
                
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
                
                Button(action: onUnlock) {
                    HStack(spacing: 6) {
                        Text(actionTitle)
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
        }
    }
}
