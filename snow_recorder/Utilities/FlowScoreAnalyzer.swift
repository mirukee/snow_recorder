import Foundation
import CoreLocation
import Combine

/// 주행 리듬(Flow) 점수를 계산하는 분석기
final class FlowScoreAnalyzer: ObservableObject {
    static let shared = FlowScoreAnalyzer()
    
    // MARK: - 퍼블리시드 (UI 바인딩용)
    @Published private(set) var latestFlowScore: Int?
    @Published private(set) var isAnalyzing: Bool = false
    
    // MARK: - 내부 상태 (스레드 안전 보장)
    private let analysisQueue = DispatchQueue(label: "FlowScoreAnalyzer.analysisQueue")
    private var isAnalyzingInternal = false
    private var currentState: RidingState = .resting
    
    // MARK: - 시간/속도 추적
    private var lastTimestamp: TimeInterval?
    private var lastSpeedMS: Double?
    private var speedSmoothingBuffer: [Double] = []
    private var speedSmoothingSum: Double = 0.0
    
    // MARK: - 누적 메트릭
    private var activeTime: TimeInterval = 0.0
    private var cruisingTime: TimeInterval = 0.0
    private var hardBrakeCount: Int = 0
    private var microStopCount: Int = 0
    private var chatterEventCount: Int = 0
    private var quietEventCount: Int = 0
    
    // MARK: - 이벤트 상태
    private var isInBrakeEvent: Bool = false
    private var isInStopEvent: Bool = false
    private var isInChatterEvent: Bool = false
    private var isInQuietPhase: Bool = false
    private var transitionGraceRemaining: TimeInterval = 0.0
    private var brakeEpisodeDuration: TimeInterval = 0.0
    private var stopCandidateCount: Int = 0
    private var quietPhaseDuration: TimeInterval = 0.0
    private var lastChatterEventTime: TimeInterval?
    
    // MARK: - 상수 (튜닝 가능)
    private let cruisingSpeedMS: Double = 4.2
    private let stopSpeedMS: Double = 1.39
    private let stopExitSpeedMS: Double = 1.6
    private let hardBrakeThreshold: Double = -2.0
    private let hardBrakePenalty: Int = 3
    private let microStopPenalty: Int = 5
    private let chatterPenalty: Int = 2
    private let quietBonus: Int = 2
    private let maxHorizontalAccuracy: Double = 50.0
    private let maxSpeedAccuracy: Double = 2.0
    private let smoothingWindowSize: Int = 3
    private let minStopSamples: Int = 2
    private let slowBrakeDuration: TimeInterval = 2.0
    private let chatterWindow: TimeInterval = 0.1
    private let chatterJerkThreshold: Double = 7.0
    private let chatterCooldown: TimeInterval = 1.0
    private let quietTargetG: Double = 1.0
    private let quietToleranceG: Double = 0.08
    private let quietMinDuration: TimeInterval = 0.2
    private let cruisingThresholdRatio: Double = 0.5
    private let cruisingPenaltyMax: Double = 20.0
    private let gravityMS2: Double = 9.80665
    private let chatterSpeedGateMS: Double = 4.2
    private let transitionGraceDuration: TimeInterval = 0.3
    
    // MARK: - 모션 추적 (RidingMetricAnalyzer에서 전달)
    private var lastMotionTimestamp: TimeInterval?
    private var lastMotionAccelMS2: Double?
    private var jerkSamples: [(timestamp: TimeInterval, value: Double)] = []
    
    // MARK: - 외부 제어
    
    /// 세션 분석 시작
    func startSession() {
        analysisQueue.async { [weak self] in
            guard let self else { return }
            self.resetSessionState()
            self.setAnalyzing(true)
        }
    }
    
    /// 세션 분석 종료
    func stopSession() {
        analysisQueue.async { [weak self] in
            guard let self else { return }
            if self.activeTime > 0 {
                self.finalizeSessionResult()
            }
            self.setAnalyzing(false)
        }
    }
    
    /// 현재 활동 상태 업데이트 (LocationManager에서 전달)
    func updateState(_ newState: RidingState) {
        analysisQueue.async { [weak self] in
            guard let self else { return }
            let previousState = self.currentState
            self.currentState = newState
            
            if self.isAnalyzingInternal && newState == .resting && previousState != .resting {
                self.finalizeSessionResult()
                self.resetMetricsForNextRun()
            }
            
            if newState != .riding {
                // 활강 상태가 아닐 때는 이벤트 상태 리셋
                self.lastTimestamp = nil
                self.lastSpeedMS = nil
                self.resetSmoothing()
                self.isInBrakeEvent = false
                self.isInStopEvent = false
                self.isInChatterEvent = false
                self.isInQuietPhase = false
                self.transitionGraceRemaining = 0.0
                self.brakeEpisodeDuration = 0.0
                self.stopCandidateCount = 0
                self.quietPhaseDuration = 0.0
                self.lastChatterEventTime = nil
                self.resetMotionStats()
            }
        }
    }
    
    /// 위치 기반 속도 업데이트 (m/s)
    func updateLocation(_ location: CLLocation) {
        analysisQueue.async { [weak self] in
            guard let self else { return }
            self.processLocation(location)
        }
    }
    
    /// 라이딩 모션 샘플 업데이트 (G 단위, total G 기준)
    func updateMotionSample(magnitudeG: Double, timestamp: TimeInterval) {
        analysisQueue.async { [weak self] in
            guard let self else { return }
            self.processMotionSample(magnitudeG: magnitudeG, timestamp: timestamp)
        }
    }
    
    // MARK: - 메인 로직
    
    private func processLocation(_ location: CLLocation) {
        guard isAnalyzingInternal else { return }
        guard currentState == .riding else { return }
        
        let timestamp = location.timestamp.timeIntervalSince1970
        let speed = location.speed
        
        // 정확도 필터링 (GPS 노이즈 방지)
        if location.horizontalAccuracy < 0 || location.horizontalAccuracy > maxHorizontalAccuracy {
            lastTimestamp = timestamp
            lastSpeedMS = nil
            resetSmoothing()
            return
        }
        
        if location.speedAccuracy >= 0 && location.speedAccuracy > maxSpeedAccuracy {
            lastTimestamp = timestamp
            lastSpeedMS = nil
            resetSmoothing()
            return
        }
        
        // 유효하지 않은 속도는 무시
        guard speed >= 0 else {
            lastTimestamp = timestamp
            lastSpeedMS = nil
            resetSmoothing()
            return
        }
        
        let currentSpeed = speed
        
        guard let lastTime = lastTimestamp else {
            lastTimestamp = timestamp
            lastSpeedMS = currentSpeed
            return
        }
        
        let deltaTime = timestamp - lastTime
        lastTimestamp = timestamp
        
        guard deltaTime > 0 else {
            lastSpeedMS = currentSpeed
            return
        }
        
        // 스무딩 적용 (GPS 노이즈 완화)
        let smoothedSpeed = appendToSmoothing(currentSpeed)
        
        // Active Time 누적
        activeTime += deltaTime
        
        // Cruising Time 누적
        if smoothedSpeed >= cruisingSpeedMS {
            cruisingTime += deltaTime
        }
        
        
        // 가속도 계산 (Δv / Δt) - 급제동/속도 조절 구분
        if let prevSpeed = lastSpeedMS {
            let acceleration = (smoothedSpeed - prevSpeed) / deltaTime
            
            if acceleration <= hardBrakeThreshold {
                isInBrakeEvent = true
                brakeEpisodeDuration += deltaTime
            } else {
                if isInBrakeEvent {
                    if brakeEpisodeDuration < slowBrakeDuration {
                        hardBrakeCount += 1
                    }
                }
                isInBrakeEvent = false
                brakeEpisodeDuration = 0.0
            }
        }
        
        // 마이크로 스톱 감지
        if smoothedSpeed <= stopSpeedMS {
            stopCandidateCount += 1
            if stopCandidateCount >= minStopSamples && !isInStopEvent {
                microStopCount += 1
                isInStopEvent = true
            }
        } else if smoothedSpeed >= stopExitSpeedMS {
            isInStopEvent = false
            stopCandidateCount = 0
        } else {
            stopCandidateCount = 0
        }
        
        lastSpeedMS = smoothedSpeed
    }
    
    // MARK: - 결과 계산
    
    private func finalizeSessionResult() {
        let baseScore = activeTime > 0 ? 100.0 : 0.0
        let cruisingRatio = activeTime > 0 ? (cruisingTime / activeTime) : 0.0
        let cruisingPenalty: Double
        if cruisingRatio < cruisingThresholdRatio {
            let deficit = (cruisingThresholdRatio - cruisingRatio) / cruisingThresholdRatio
            cruisingPenalty = min(cruisingPenaltyMax, max(0.0, deficit * cruisingPenaltyMax))
        } else {
            cruisingPenalty = 0.0
        }
        
        let penalty = Double(hardBrakeCount * hardBrakePenalty)
            + Double(microStopCount * microStopPenalty)
            + Double(chatterEventCount * chatterPenalty)
            + cruisingPenalty
        let bonus = Double(quietEventCount * quietBonus)
        let finalScore = max(0.0, min(100.0, baseScore - penalty + bonus))
        let result = Int(finalScore.rounded())
        
        // 라이딩 메트릭 분석기와 동기화
        RidingMetricAnalyzer.shared.updateFlowScore(result)
        
        DispatchQueue.main.async { [weak self] in
            self?.latestFlowScore = result
        }
    }
    
    private func resetSessionState() {
        resetMetricsForNextRun()
        
        DispatchQueue.main.async { [weak self] in
            self?.latestFlowScore = nil
        }
    }
    
    private func resetMetricsForNextRun() {
        lastTimestamp = nil
        lastSpeedMS = nil
        resetSmoothing()
        activeTime = 0.0
        cruisingTime = 0.0
        hardBrakeCount = 0
        microStopCount = 0
        chatterEventCount = 0
        quietEventCount = 0
        isInBrakeEvent = false
        isInStopEvent = false
        isInChatterEvent = false
        isInQuietPhase = false
        brakeEpisodeDuration = 0.0
        stopCandidateCount = 0
        quietPhaseDuration = 0.0
        transitionGraceRemaining = 0.0
        lastChatterEventTime = nil
        resetMotionStats()
    }
    
    private func appendToSmoothing(_ value: Double) -> Double {
        speedSmoothingBuffer.append(value)
        speedSmoothingSum += value
        
        if speedSmoothingBuffer.count > smoothingWindowSize, let first = speedSmoothingBuffer.first {
            speedSmoothingSum -= first
            speedSmoothingBuffer.removeFirst()
        }
        
        let divisor = Double(speedSmoothingBuffer.count)
        guard divisor > 0 else { return value }
        return speedSmoothingSum / divisor
    }
    
    private func resetSmoothing() {
        speedSmoothingBuffer.removeAll()
        speedSmoothingSum = 0.0
    }
    
    private func processMotionSample(magnitudeG: Double, timestamp: TimeInterval) {
        guard isAnalyzingInternal else { return }
        guard currentState == .riding else { return }
        
        // 시간 간격 계산
        guard let lastTime = lastMotionTimestamp else {
            lastMotionTimestamp = timestamp
            lastMotionAccelMS2 = magnitudeG * gravityMS2
            return
        }
        
        let deltaTime = timestamp - lastTime
        lastMotionTimestamp = timestamp
        
        guard deltaTime > 0 else { return }
        
        let currentAccelMS2 = magnitudeG * gravityMS2
        if let lastAccel = lastMotionAccelMS2 {
            let jerk = (currentAccelMS2 - lastAccel) / deltaTime
            appendJerkSample(jerk, timestamp: timestamp)
            
            // 채터링 감지: 0.1초 내 +/− 급격한 저크 요동만 감점
            if transitionGraceRemaining > 0 {
                transitionGraceRemaining = max(0.0, transitionGraceRemaining - deltaTime)
            }
            
            let isChattering = detectChattering()
            if isChattering {
                if smoothedSpeedGateAllows()
                    && transitionGraceRemaining <= 0
                    && !isInChatterEvent
                    && canRegisterChatterEvent(at: timestamp) {
                    chatterEventCount += 1
                    lastChatterEventTime = timestamp
                    isInChatterEvent = true
                }
            } else {
                isInChatterEvent = false
            }
        }
        lastMotionAccelMS2 = currentAccelMS2
        
        // Quiet Phase 감지 (언웨이팅)
        let isQuietRange = abs(magnitudeG - quietTargetG) <= quietToleranceG
        if isQuietRange {
            quietPhaseDuration += deltaTime
            if quietPhaseDuration >= quietMinDuration && !isInQuietPhase {
                quietEventCount += 1
                isInQuietPhase = true
                transitionGraceRemaining = transitionGraceDuration
            }
        } else {
            quietPhaseDuration = 0.0
            isInQuietPhase = false
        }
    }
    
    private func appendJerkSample(_ jerk: Double, timestamp: TimeInterval) {
        jerkSamples.append((timestamp: timestamp, value: jerk))
        let cutoff = timestamp - chatterWindow
        while let first = jerkSamples.first, first.timestamp < cutoff {
            jerkSamples.removeFirst()
        }
    }
    
    private func detectChattering() -> Bool {
        guard !jerkSamples.isEmpty else { return false }
        var maxJerk: Double = -Double.greatestFiniteMagnitude
        var minJerk: Double = Double.greatestFiniteMagnitude
        for sample in jerkSamples {
            if sample.value > maxJerk { maxJerk = sample.value }
            if sample.value < minJerk { minJerk = sample.value }
        }
        return maxJerk >= chatterJerkThreshold && minJerk <= -chatterJerkThreshold
    }

    private func canRegisterChatterEvent(at timestamp: TimeInterval) -> Bool {
        guard let lastTime = lastChatterEventTime else { return true }
        return (timestamp - lastTime) >= chatterCooldown
    }
    
    private func smoothedSpeedGateAllows() -> Bool {
        guard !speedSmoothingBuffer.isEmpty else { return false }
        let avgSpeed = speedSmoothingSum / Double(speedSmoothingBuffer.count)
        return avgSpeed >= chatterSpeedGateMS
    }
    
    private func resetMotionStats() {
        lastMotionTimestamp = nil
        lastMotionAccelMS2 = nil
        jerkSamples.removeAll()
    }
    
    private func setAnalyzing(_ isAnalyzing: Bool) {
        isAnalyzingInternal = isAnalyzing
        DispatchQueue.main.async { [weak self] in
            self?.isAnalyzing = isAnalyzing
        }
    }
}
