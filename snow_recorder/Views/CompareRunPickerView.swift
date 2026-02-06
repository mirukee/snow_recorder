import SwiftUI

/// 세션 내 런 선택 화면 (시즌 평균 비교 진입 전)
struct CompareRunPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    
    let session: RunSession
    
    @State private var selectedRunId: UUID?
    @State private var compareTarget: RunSession.RunMetric?
    
    // Theme Colors
    private let neonGreen = Color(hex: "6bf906")
    private let backgroundDark = Color.black
    private let glassPanel = Color.white.opacity(0.05)
    private let selectedPanel = Color(red: 107/255, green: 249/255, blue: 6/255).opacity(0.08)
    
    private var runs: [RunSession.RunMetric] {
        session.runMetrics.sorted { $0.runNumber < $1.runNumber }
    }
    
    private var selectedRun: RunSession.RunMetric? {
        runs.first { $0.id == selectedRunId }
    }
    
    private var selectedCount: Int {
        selectedRunId == nil ? 0 : 1
    }
    
    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    backgroundDark.ignoresSafeArea()
                    
                    VStack {
                        GridPattern()
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                            .frame(height: 360)
                            .mask(
                                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            )
                        Spacer()
                    }
                    .ignoresSafeArea()
                    
                    VStack(spacing: 0) {
                        headerView
                            .padding(.top, proxy.safeAreaInsets.top + 8)
                            .padding(.bottom, 12)
                            .background(headerGradient)
                        
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 12) {
                                if runs.isEmpty {
                                    emptyState
                                } else {
                                    ForEach(runs) { metric in
                                        RunPickerCard(
                                            metric: metric,
                                            isSelected: selectedRunId == metric.id,
                                            neonGreen: neonGreen,
                                            glassPanel: glassPanel,
                                            selectedPanel: selectedPanel,
                                            timeText: formatRunTimeRange(metric.startTime, metric.endTime),
                                            distanceText: formatDistance(metric.distance),
                                            speedText: formatSpeed(metric.maxSpeed),
                                            difficulty: difficultyInfo(for: metric),
                                            runLabel: loc("compare.run_picker.run_label", "RUN")
                                        ) {
                                            if selectedRunId == metric.id {
                                                selectedRunId = nil
                                            } else {
                                                selectedRunId = metric.id
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 140)
                        }
                    }
                    
                    footerView
                        .padding(.bottom, proxy.safeAreaInsets.bottom + 8)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $compareTarget) { metric in
                CompareRunDetailView(session: session, metric: metric)
            }
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        VStack(spacing: 14) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                
                Spacer()
                
                Text(loc("compare.run_picker.title", "SESSION ANALYSIS"))
                    .font(.system(size: 12, weight: .bold))
                    .tracking(3)
                    .foregroundColor(.white.opacity(0.75))
                
                Spacer()
            }
            
            VStack(spacing: 6) {
                Text(session.locationName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                
                HStack(spacing: 8) {
                    Text(formattedDate(session.startTime))
                    Circle()
                        .fill(neonGreen)
                        .frame(width: 4, height: 4)
                    Text(formatSessionTimeRange(session.startTime, session.endTime))
                }
                .font(.system(size: 11, weight: .bold))
                .tracking(1.5)
                .foregroundColor(neonGreen.opacity(0.85))
            }
            
            HStack {
                Text(loc("compare.run_picker.subtitle", "Select a run to compare"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                
                Spacer()
                
                Text(String(format: loc("compare.run_picker.selected_count_format", "%d SELECTED"), selectedCount))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(neonGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(neonGreen.opacity(0.12))
                    .overlay(
                        Capsule()
                            .stroke(neonGreen.opacity(selectedCount > 0 ? 0.6 : 0.2), lineWidth: 1)
                    )
                    .clipShape(Capsule())
                    .opacity(selectedCount > 0 ? 1.0 : 0.6)
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var headerGradient: some View {
        LinearGradient(
            colors: [backgroundDark, backgroundDark.opacity(0.95), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
    
    // MARK: - Footer
    private var footerView: some View {
        VStack {
            LinearGradient(
                colors: [backgroundDark, backgroundDark.opacity(0.9), .clear],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 120)
            .overlay(alignment: .bottom) {
                Button(action: {
                    guard let selectedRun else { return }
                    compareTarget = selectedRun
                }) {
                    HStack(spacing: 10) {
                        Text(loc("compare.run_picker.compare_button", "COMPARE SELECTED"))
                            .font(.system(size: 16, weight: .bold))
                            .tracking(1.5)
                            .foregroundColor(.black)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(neonGreen)
                    .clipShape(Capsule())
                    .shadow(color: neonGreen.opacity(0.6), radius: 20, x: 0, y: 6)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .disabled(selectedRun == nil)
                .opacity(selectedRun == nil ? 0.4 : 1.0)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "slash.circle")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
            Text(loc("compare.run_picker.empty", "No runs in this session"))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.top, 40)
    }
    
    // MARK: - Helpers
    private func difficultyInfo(for metric: RunSession.RunMetric) -> (label: String, color: Color) {
        if let slope = SlopeDatabase.shared.findSlope(byName: metric.slopeName) {
            let colorHex = slope.difficulty.colorHex
            return (slope.difficulty.displayLabel.uppercased(), Color(hex: colorHex))
        }
        return (loc("compare.run_picker.difficulty_unknown", "UNKNOWN"), .gray)
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        if locale.identifier.hasPrefix("ko") {
            formatter.dateFormat = "yyyy.MM.dd"
        } else {
            formatter.dateFormat = "MMM d, yyyy"
        }
        return formatter.string(from: date)
    }
    
    private func formatSessionTimeRange(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
    
    private func formatRunTimeRange(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
    
    private func formatDistance(_ meters: Double) -> String {
        let km = meters / 1000.0
        return String(format: "%.1f KM", km)
    }
    
    private func formatSpeed(_ speed: Double) -> String {
        return String(format: "%.0f KM/H", speed)
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
}

private struct RunPickerCard: View {
    let metric: RunSession.RunMetric
    let isSelected: Bool
    let neonGreen: Color
    let glassPanel: Color
    let selectedPanel: Color
    let timeText: String
    let distanceText: String
    let speedText: String
    let difficulty: (label: String, color: Color)
    let runLabel: String
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                runNumberBadge
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(metric.slopeName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text(difficulty.label)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(difficulty.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(difficulty.color.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(isSelected ? neonGreen : .white.opacity(0.4))
                        Text(timeText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(isSelected ? neonGreen : .white.opacity(0.5))
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(distanceText)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(isSelected ? neonGreen : .white)
                    Text(speedText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(isSelected ? neonGreen.opacity(0.8) : .white.opacity(0.4))
                }
                
                checkBadge
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(cardBackground)
            .overlay(
                Capsule()
                    .stroke(isSelected ? neonGreen : Color.white.opacity(0.08), lineWidth: isSelected ? 1.2 : 1)
            )
            .clipShape(Capsule())
            .shadow(color: isSelected ? neonGreen.opacity(0.2) : .clear, radius: 12)
        }
        .buttonStyle(.plain)
    }
    
    private var cardBackground: some View {
        Group {
            if isSelected {
                selectedPanel
            } else {
                glassPanel
            }
        }
    }
    
    private var runNumberBadge: some View {
        ZStack {
            Circle()
                .fill(isSelected ? neonGreen : Color.white.opacity(0.06))
                .overlay(
                    Circle()
                        .stroke(isSelected ? neonGreen.opacity(0.8) : Color.white.opacity(0.08), lineWidth: 1)
                )
                .frame(width: 56, height: 56)
                .shadow(color: isSelected ? neonGreen.opacity(0.4) : .clear, radius: 10)
            
            VStack(spacing: 2) {
                Text(runLabel)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(isSelected ? .black.opacity(0.7) : .white.opacity(0.4))
                Text(String(format: "%02d", metric.runNumber))
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(isSelected ? .black : .white)
            }
        }
    }
    
    private var checkBadge: some View {
        ZStack {
            Circle()
                .stroke(isSelected ? neonGreen : Color.white.opacity(0.2), lineWidth: 2)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(isSelected ? neonGreen : .clear)
                )
            
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.black)
            }
        }
        .padding(.leading, 6)
    }
}
