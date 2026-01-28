import SwiftUI
import Charts
import UIKit

struct RunMetricDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let metric: RunSession.RunMetric
    let accentColor: Color
    let speedSeries: [Double]
    let locationName: String
    
    private let surfaceCard = Color(red: 17/255, green: 17/255, blue: 17/255)
    private let surfaceSoft = Color.white.opacity(0.04)
    private let strokeSoft = Color.white.opacity(0.08)
    
    @State private var showSaveToast = false
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
            
            VStack {
                Spacer(minLength: 0)
                cardContainer(showControls: true)
                
                Spacer(minLength: 0)
            }
        }
        .overlay(alignment: .top) {
            if showSaveToast {
                Text("Saved to Photos")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(8)
                    .padding(.top, 24)
                    .transition(.opacity)
            }
        }
    }
    
    private var cardWidth: CGFloat {
        min(UIScreen.main.bounds.width - 64, 360)
    }
    
    private func cardContainer(showControls: Bool, includeOuterPadding: Bool = true) -> some View {
        let card = cardContent(showControls: showControls)
            .frame(width: cardWidth)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(surfaceCard.opacity(0.92))
                    .shadow(color: accentColor.opacity(0.2), radius: 24, x: 0, y: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(accentColor.opacity(0.3), lineWidth: 1)
            )
        return Group {
            if includeOuterPadding {
                card.padding(18)
            } else {
                card
            }
        }
    }
    
    private func cardContent(showControls: Bool) -> some View {
        VStack(spacing: 16) {
            headerSection(showControls: showControls)
            
            timeRow
            
            topStatsSection
            
            // Watermark (Snow Record)
            HStack {
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "snowflake")
                        .font(.system(size: 28))
                        .foregroundColor(accentColor)
                    Text("SNOW RECORD")
                        .font(.system(size: 24, weight: .black))
                        .italic()
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.vertical, 8)
            }
            .padding(.horizontal, 4)
            
            speedChartSection
        }
    }
    
    // MARK: - Helpers
    private var difficultyInfo: (color: Color, label: String) {
        if let slope = SlopeDatabase.shared.findSlope(byName: metric.slopeName) {
            let colorHex = slope.difficulty.colorHex
            return (Color(hex: colorHex), slope.difficulty.rawValue)
        }
        return (.gray, "Unknown")
    }

    private func headerSection(showControls: Bool) -> some View {
        HStack {
            if showControls {
                Button(action: { saveCardImage() }) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
            } else {
                Color.clear.frame(width: 32, height: 32)
            }
            
            Spacer()
            
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    // Left Dot
                    Circle()
                        .fill(difficultyInfo.color)
                        .frame(width: 8, height: 8)
                        .shadow(color: difficultyInfo.color.opacity(0.5), radius: 4)
                    
                    Text(metric.slopeName)
                        .font(.system(size: 22, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(.white)
                    
                    // Right Badge
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
                
                Text(locationName.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(3)
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            if showControls {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Circle())
                }
            } else {
                Color.clear.frame(width: 32, height: 32)
            }
        }
    }
    
    private var timeRow: some View {
        HStack {
            Text(formatRunTimeRange(metric.startTime, metric.endTime))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Text(formatRunDuration(metric.duration))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 8)
    }
    
    private var topStatsSection: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 10) {
                ringScoreCard(title: "EDGE", score: metric.edgeScore)
                ringScoreCard(title: "FLOW", score: metric.flowScore)
            }
            
            VStack(spacing: 10) {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        statCard(title: "MAX SPEED", value: formatSpeedOneDecimal(displayMaxSpeed), unit: "KM/H")
                        statCard(title: "DISTANCE", value: formatDistance(metric.distance), unit: nil)
                    }
                    
                    HStack(spacing: 10) {
                        statCard(title: "AVG SPEED", value: formatSpeedOneDecimal(displayAvgSpeed), unit: "KM/H")
                        statCard(title: "VERT DROP", value: formatVertical(metric.verticalDrop), unit: "M")
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    private func ringScoreCard(title: String, score: Int) -> some View {
        let progress = min(max(Double(score) / 1000.0, 0.0), 1.0)
        return VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        accentColor,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: accentColor.opacity(0.6), radius: 6)
                
                VStack(spacing: -2) {
                    Text("\(score)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    Text("/1000")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .frame(width: 84, height: 84)
            
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(width: 110)
        .padding(.horizontal, 6)
        .padding(.vertical, 12)
        .background(surfaceSoft)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(accentColor.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func statCard(title: String, value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.gray)
                .tracking(1)
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            if let unit {
                Text(unit)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.gray)
            }
        }
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .padding(12)
        .background(surfaceSoft)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(strokeSoft, lineWidth: 1)
        )
    }
    
    private var maxSpeedPoint: (index: Int, value: Double)? {
        guard let maxValue = speedSeries.max(),
              let index = speedSeries.firstIndex(of: maxValue) else {
            return nil
        }
        return (index, maxValue)
    }

    private var speedScale: Double {
        let seriesMax = speedSeries.max() ?? 0
        guard seriesMax > 0, metric.maxSpeed > 0 else { return 1.0 }
        let ratio = seriesMax / metric.maxSpeed
        if ratio > 2.6 && ratio < 4.6 {
            return 3.6
        }
        return 1.0
    }
    
    private var displayMaxSpeed: Double {
        if let seriesMax = speedSeries.max(), seriesMax > 0 {
            return seriesMax
        }
        return metric.maxSpeed * speedScale
    }
    
    private var displayAvgSpeed: Double {
        metric.avgSpeed * speedScale
    }
    
    private var speedChartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 4, height: 4)
                        .shadow(color: accentColor.opacity(0.6), radius: 4)
                    Text("SPEED PROFILE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(accentColor)
                }
                Spacer()
                Text(formatRunDuration(metric.duration))
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.4))
            }
            
            if speedSeries.isEmpty {
                Text("No speed data")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .background(surfaceSoft)
                    .cornerRadius(12)
            } else {
                ZStack {
                    VStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 1)
                            Spacer()
                        }
                    }
                    
                    Chart {
                        ForEach(Array(speedSeries.enumerated()), id: \.offset) { index, speed in
                            AreaMark(
                                x: .value("Index", index),
                                y: .value("Speed", speed)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [accentColor.opacity(0.25), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            
                            LineMark(
                                x: .value("Index", index),
                                y: .value("Speed", speed)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(accentColor)
                        }
                        
                        if let point = maxSpeedPoint {
                            PointMark(
                                x: .value("Index", point.index),
                                y: .value("Speed", point.value)
                            )
                            .foregroundStyle(accentColor)
                            .symbolSize(40)
                            .annotation(position: .top, alignment: .center) {
                                Text("MAX \(formatSpeedOneDecimal(point.value))")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(accentColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.black.opacity(0.6))
                                    .cornerRadius(6)
                            }
                        }
                    }
                    .chartYScale(domain: 0...max(10, (speedSeries.max() ?? 0) * 1.1))
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                }
                .frame(height: 140)
                .padding(10)
                .background(surfaceSoft)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(strokeSoft, lineWidth: 1)
                )
                .shadow(color: accentColor.opacity(0.15), radius: 12, x: 0, y: 6)
            }
        }
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
    
    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1fKM", meters / 1000)
        }
        return "\(Int(meters))M"
    }
    
    private func formatVertical(_ meters: Double) -> String {
        "\(Int(meters))"
    }
    
    private func formatRunTimeRange(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start)) ~ \(formatter.string(from: end))"
    }
    
    @MainActor
    private func saveCardImage() {
        let renderer = ImageRenderer(content: cardContainer(showControls: false, includeOuterPadding: false))
        renderer.scale = UIScreen.main.scale
        if let image = renderer.uiImage {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            withAnimation(.easeOut(duration: 0.2)) {
                showSaveToast = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation(.easeOut(duration: 0.2)) {
                    showSaveToast = false
                }
            }
        }
    }
}
