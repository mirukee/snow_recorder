#if DEBUG
import SwiftUI

/// 분석 리포트 디버그 화면 (출시 전 제거 가능)
struct AnalysisDebugView: View {
    let session: RunSession
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    summarySection
                    flowSection
                    edgeSection
                    eventSection
                    sampleSection
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("ANALYSIS DEBUG")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var summarySection: some View {
        debugCard(title: "SUMMARY") {
            debugRow("샘플 수", "\(session.analysisSamples.count)")
            debugRow("이벤트 수", "\(session.analysisEvents.count)")
            debugRow("구간 수", "\(session.analysisSegments.count)")
        }
    }
    
    private var flowSection: some View {
        let f = session.flowBreakdown
        return debugCard(title: "FLOW BREAKDOWN") {
            debugRow("최종 점수", "\(f.finalScore ?? 0)")
            debugRow("평균 안정도", formatDouble(f.avgStability ?? 0, 3))
            debugRow("베이스 점수", formatDouble(f.baseScore ?? 0, 1))
            debugRow("활동 시간", "\(Int(f.activeTime ?? 0))s")
            debugRow("이동 시간", "\(Int(f.movingTime ?? 0))s")
            debugRow("정지 시간", "\(Int(f.totalStopDuration ?? 0))s")
            debugRow("정지 패널티", formatDouble(f.stopPenalty ?? 0, 1))
            debugRow("브레이크 횟수", "\(f.hardBrakeCount ?? 0)")
            debugRow("브레이크 패널티", formatDouble(f.brakePenalty ?? 0, 1))
            debugRow("채터 횟수", "\(f.chatterEventCount ?? 0)")
            debugRow("채터 패널티", formatDouble(f.chatterPenalty ?? 0, 1))
            debugRow("Quiet 횟수", "\(f.quietEventCount ?? 0)")
            debugRow("Quiet 보너스", formatDouble(f.quietBonus ?? 0, 1))
        }
    }
    
    private var edgeSection: some View {
        let e = session.edgeBreakdown
        return debugCard(title: "EDGE BREAKDOWN") {
            debugRow("최종 점수", "\(e.finalScore ?? 0)")
            debugRow("Raw 점수", formatDouble(e.rawScore ?? 0, 1))
            debugRow("정규화", formatDouble(e.normalized ?? 0, 3))
            debugRow("최대 G", formatDouble(e.maxGForce ?? 0, 2))
            debugRow("Tier 시간", "\(Int(e.tieredTimeTotal ?? 0))s")
            debugRow("Tier2+ 시간", "\(Int(e.tier2PlusTime ?? 0))s")
            debugRow("Tier2 비율", formatDouble(e.tier2Ratio ?? 0, 3))
            debugRow("Pro 캡 적용", (e.proCapApplied ?? false) ? "Y" : "N")
            debugRow("Tier2 캡 적용", (e.tier2CapApplied ?? false) ? "Y" : "N")
        }
    }
    
    private var eventSection: some View {
        let hardBrakeCount = session.analysisEvents.filter { $0.type == .hardBrake }.count
        let chatterCount = session.analysisEvents.filter { $0.type == .chatter }.count
        let quietCount = session.analysisEvents.filter { $0.type == .quietPhase }.count
        
        return debugCard(title: "EVENTS") {
            debugRow("하드 브레이크", "\(hardBrakeCount)")
            debugRow("채터", "\(chatterCount)")
            debugRow("Quiet", "\(quietCount)")
        }
    }
    
    private var sampleSection: some View {
        let lastTime = session.analysisSamples.last?.t ?? 0
        return debugCard(title: "SAMPLES") {
            debugRow("총 길이", "\(Int(lastTime))s")
            debugRow("1초 샘플", "\(session.analysisSamples.count)")
            debugRow("구간(10Hz)", "\(session.analysisSegments.count)")
        }
    }
    
    private func debugCard(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.7))
                .tracking(1.5)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    private func debugRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
    }
    
    private func formatDouble(_ value: Double, _ digits: Int) -> String {
        String(format: "%.\(digits)f", value)
    }
}
#endif
