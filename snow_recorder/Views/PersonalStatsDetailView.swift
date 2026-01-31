import SwiftUI
import SwiftData

/// 퍼스널 스탯 상세 화면
struct PersonalStatsDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \RunSession.startTime, order: .reverse) private var sessions: [RunSession]
    
    private let neonGreen = Color(red: 107/255, green: 249/255, blue: 6/255)
    private let glassDark = Color.white.opacity(0.05)
    
    @State private var selectedSeasonId: String?
    @State private var selectedRange: RangeOption = .oneHour
    @State private var didSetInitialSeason = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack {
                GridPattern()
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    .frame(height: 300)
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                Spacer()
            }
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    headerView
                    
                    summaryGrid
                    
                    gaugesRow
                    
                    velocityMatrix
                    
                    footerSync
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { setInitialSeasonIfNeeded() }
        .onChange(of: sessions.count) { _ in
            setInitialSeasonIfNeeded()
        }
    }
    
    // MARK: - 서브뷰
    
    private var headerView: some View {
        VStack(spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedSeasonTitle)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(3)
                        .foregroundColor(neonGreen)
                    Text("PERSONAL STATS")
                        .font(.system(size: 28, weight: .black))
                        .foregroundColor(.white)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
            }
            
            if !availableSeasons.isEmpty {
                seasonPicker
            }
        }
        .padding(.top, 24)
    }
    
    private var summaryGrid: some View {
        HStack(spacing: 12) {
            SummaryStatCard(value: "\(totalRuns)", unit: "RUNS", neonGreen: neonGreen)
            SummaryStatCard(value: "\(totalDistanceKm)", unit: "km", neonGreen: neonGreen)
            SummaryStatCard(value: "\(totalDropK)", unit: "k", neonGreen: neonGreen)
            SummaryStatCard(value: "\(totalTimeHours)", unit: "h", neonGreen: neonGreen)
        }
    }
    
    private var gaugesRow: some View {
        HStack(spacing: 12) {
            GaugeCard(title: "EDGE SCORE", icon: "bolt.fill", value: edgeScore, neonGreen: neonGreen)
            GaugeCard(title: "FLOW SCORE", icon: "wind", value: flowScore, neonGreen: neonGreen)
        }
    }
    
    private var velocityMatrix: some View {
        VStack(spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("VELOCITY MATRIX")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.gray)
                    HStack(spacing: 4) {
                        Text("Peak \(peakSpeed)")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                        Text("km/h")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
                RangePicker(selected: $selectedRange, neonGreen: neonGreen)
            }
            
            NeonLineChart(values: chartValues, neonGreen: neonGreen)
                .frame(height: 170)
            
            HStack {
                Text("09:00")
                Spacer()
                Text("10:00")
                Spacer()
                Text("11:00")
                Spacer()
                Text("12:00")
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(.gray)
        }
        .padding(16)
        .background(glassDark)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(neonGreen.opacity(0.4), lineWidth: 1)
        )
        .cornerRadius(18)
        .shadow(color: neonGreen.opacity(0.2), radius: 12)
    }
    
    private var footerSync: some View {
        Text("SYSTEM SYNC: \(formattedSyncTime)")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(2)
            .foregroundColor(.gray)
            .padding(.top, 8)
    }
    
    // MARK: - 데이터 헬퍼
    
    private var activeSessions: [RunSession] {
        guard let selectedSeason = selectedSeason else {
            return sessions
        }
        return sessions.filter { $0.startTime >= selectedSeason.start && $0.startTime <= selectedSeason.end }
    }
    
    private var rangeFilteredSessions: [RunSession] {
        let source = activeSessions
        guard let cutoff = selectedRange.cutoffDate(from: Date()) else {
            return source
        }
        let filtered = source.filter { $0.endTime >= cutoff }
        return filtered.isEmpty ? source : filtered
    }
    
    private var totalRuns: Int {
        activeSessions.reduce(0) { $0 + $1.runCount }
    }
    
    private var totalDistanceKm: String {
        let meters = activeSessions.reduce(0.0) { $0 + $1.distance }
        let km = meters / 1000.0
        return String(format: "%.0f", km)
    }
    
    private var totalDropK: String {
        let meters = activeSessions.reduce(0.0) { $0 + $1.verticalDrop }
        let k = meters / 1000.0
        return String(format: "%.1f", k)
    }
    
    private var totalTimeHours: String {
        let seconds = activeSessions.reduce(0.0) { $0 + $1.duration }
        let hours = seconds / 3600.0
        return String(format: "%.1f", hours)
    }
    
    private var edgeScore: Int {
        let scores = collectRunScores(from: activeSessions)
        return top3Average(scores.edge)
    }
    
    private var flowScore: Int {
        let scores = collectRunScores(from: activeSessions)
        return top3Average(scores.flow)
    }
    
    private var peakSpeed: Int {
        let samples = speedSamples(from: rangeFilteredSessions, cutoff: selectedRange.cutoffDate(from: Date()))
        if let maxSample = samples.max() {
            return Int(maxSample)
        }
        return Int(rangeFilteredSessions.map { $0.maxSpeed }.max() ?? 0.0)
    }
    
    private var chartValues: [Double] {
        let samples = speedSamples(from: rangeFilteredSessions, cutoff: selectedRange.cutoffDate(from: Date()))
        if samples.isEmpty {
            return [12, 24, 38, 20, 16, 30, 48, 36, 52, 44, 60, 48]
        }
        return downsample(samples, maxSamples: 12)
    }
    
    private var formattedSyncTime: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "MM/dd HH:mm"
        let date = activeSessions.first?.endTime ?? Date()
        return formatter.string(from: date)
    }
    
    private func top3Average(_ scores: [Int]) -> Int {
        guard !scores.isEmpty else { return 0 }
        let top3 = scores.sorted(by: >).prefix(3)
        let sum = top3.reduce(0, +)
        let avg = Double(sum) / Double(top3.count)
        return Int(avg.rounded())
    }

    // 런 단위 점수 수집 (런 메트릭 없는 세션은 세션 최고점으로 보정)
    private func collectRunScores(from sessions: [RunSession]) -> (edge: [Int], flow: [Int]) {
        var edgeScores: [Int] = []
        var flowScores: [Int] = []
        
        for session in sessions {
            if session.runMetrics.isEmpty {
                if session.runCount > 0 {
                    edgeScores.append(session.edgeScore)
                    flowScores.append(session.flowScore)
                }
                continue
            }
            
            for metric in session.runMetrics {
                edgeScores.append(metric.edgeScore)
                flowScores.append(metric.flowScore)
            }
        }
        
        return (edgeScores, flowScores)
    }
    
    private func downsample(_ values: [Double], maxSamples: Int) -> [Double] {
        guard !values.isEmpty else { return [] }
        let strideValue = max(1, values.count / maxSamples)
        return stride(from: 0, to: values.count, by: strideValue).map { values[$0] }
    }
    
    private func speedSamples(from sessions: [RunSession], cutoff: Date?) -> [Double] {
        var samples: [Double] = []
        let cutoffTime = cutoff?.timeIntervalSince1970
        
        for session in sessions {
            let speeds = session.routeSpeeds
            let timestamps = session.routeTimestamps
            if speeds.isEmpty {
                continue
            }
            
            if let cutoffTime, timestamps.count == speeds.count {
                for (index, ts) in timestamps.enumerated() where ts >= cutoffTime {
                    samples.append(speeds[index])
                }
            } else {
                samples.append(contentsOf: speeds)
            }
        }
        
        return samples
    }
    
    private var kstCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        calendar.locale = Locale(identifier: "ko_KR")
        calendar.firstWeekday = 2
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
    
    private var availableSeasons: [SeasonInfo] {
        var map: [String: SeasonInfo] = [:]
        for session in sessions {
            guard let season = seasonInfo(for: session.startTime) else { continue }
            map[season.id] = season
        }
        return map.values.sorted { $0.start > $1.start }
    }
    
    private var selectedSeason: SeasonInfo? {
        guard let selectedSeasonId else { return nil }
        return availableSeasons.first { $0.id == selectedSeasonId }
    }
    
    private var selectedSeasonTitle: String {
        if let selectedSeason {
            return "SEASON \(selectedSeason.label)"
        }
        return "ALL TIME"
    }
    
    private var seasonPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                seasonPill(title: "ALL TIME", isSelected: selectedSeasonId == nil) {
                    selectedSeasonId = nil
                }
                ForEach(availableSeasons) { season in
                    seasonPill(title: season.shortLabel, isSelected: selectedSeasonId == season.id) {
                        selectedSeasonId = season.id
                    }
                }
            }
            .padding(4)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func seasonPill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { action() } }) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundColor(isSelected ? .black : .gray)
                .background(isSelected ? neonGreen : Color.clear)
                .clipShape(Capsule())
        }
    }
    
    private func setInitialSeasonIfNeeded() {
        guard !didSetInitialSeason else { return }
        if let currentSeason = seasonInfo(for: Date()),
           availableSeasons.contains(where: { $0.id == currentSeason.id }) {
            selectedSeasonId = currentSeason.id
        } else if let fallback = availableSeasons.first {
            selectedSeasonId = fallback.id
        } else {
            selectedSeasonId = nil
        }
        didSetInitialSeason = true
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
}

private struct SeasonInfo: Identifiable, Hashable {
    let id: String
    let start: Date
    let end: Date
    let label: String
    
    var shortLabel: String { label }
}

// MARK: - 구성 요소

private struct SummaryStatCard: View {
    let value: String
    let unit: String
    let neonGreen: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
            Text(unit.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(neonGreen.opacity(0.4), lineWidth: 1)
        )
        .cornerRadius(14)
    }
}

private struct GaugeCard: View {
    let title: String
    let icon: String
    let value: Int
    let neonGreen: Color
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.gray)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(neonGreen)
            }
            
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 10)
                RingGaugeView(progress: Double(value) / 1000.0, color: neonGreen)
                    .frame(width: 120, height: 120)
                VStack(spacing: 2) {
                    Text("\(value)")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                    Text("PTS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(neonGreen)
                }
            }
            .frame(width: 140, height: 140)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(neonGreen.opacity(0.4), lineWidth: 1)
        )
        .cornerRadius(18)
        .shadow(color: neonGreen.opacity(0.25), radius: 10)
    }
}

private struct RangePicker: View {
    @Binding var selected: RangeOption
    let neonGreen: Color
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(RangeOption.allCases, id: \.self) { option in
                Text(option.title)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(selected == option ? neonGreen.opacity(0.2) : Color.clear)
                    .foregroundColor(selected == option ? neonGreen : .gray)
                    .clipShape(Capsule())
                    .onTapGesture { selected = option }
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
    }
}

private struct NeonLineChart: View {
    let values: [Double]
    let neonGreen: Color
    
    var body: some View {
        GeometryReader { geo in
            let points = normalizedPoints(values, size: geo.size)
            ZStack {
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in
                        Rectangle()
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundColor(.white.opacity(0.12))
                            .frame(height: 0.5)
                        Spacer()
                    }
                }
                
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(neonGreen, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .shadow(color: neonGreen.opacity(0.6), radius: 6)
                
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: geo.size.height))
                    path.addLine(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                    path.addLine(to: CGPoint(x: points.last?.x ?? 0, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(neonGreen.opacity(0.12))
            }
        }
    }
    
    private func normalizedPoints(_ values: [Double], size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let maxValue = values.max() ?? 1
        let minValue = values.min() ?? 0
        let range = max(maxValue - minValue, 1)
        
        return values.enumerated().map { index, value in
            let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
            let normalized = (value - minValue) / range
            let y = size.height * (1 - CGFloat(normalized))
            return CGPoint(x: x, y: y)
        }
    }
}

private enum RangeOption: CaseIterable {
    case oneHour
    case day
    case week
    
    var title: String {
        switch self {
        case .oneHour: return "1H"
        case .day: return "24H"
        case .week: return "7D"
        }
    }
    
    func cutoffDate(from date: Date) -> Date? {
        switch self {
        case .oneHour:
            return date.addingTimeInterval(-3600)
        case .day:
            return date.addingTimeInterval(-86400)
        case .week:
            return date.addingTimeInterval(-7 * 86400)
        }
    }
}

#Preview {
    PersonalStatsDetailView()
        .modelContainer(for: RunSession.self, inMemory: true)
}
