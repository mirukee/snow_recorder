import Foundation
import CoreLocation
import Combine

/// 주행 리듬(Flow) 점수를 계산하는 분석기
/// - Concept: "속도의 빠르기"가 아닌 "속도의 안정성(Stability)"을 평가
/// - Core Logic: Speed Variance를 역수로 취해 Base Score(60~100)를 산출하고, 
///   정지 시간 및 불안정 이벤트(떨림, 급제동)를 감점 요소로 반영함. (1000점 만점)
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
    
    // MARK: - Stability (Local Window) 추적
    // 전역 분산 대신, 최근 N초간의 "국소적 안정성"을 누적하여 평균냄.
    // 이를 통해 급경사->완경사 진입 시 자연스러운 감속이 "불안정"으로 기록되는 것을 방지.
    private var speedWindow: [Double] = [] // 최근 속도 샘플 버퍼
    private var localStabilitySum: Double = 0.0 // 측정된 순간 안정성 합계
    private var localStabilityCount: Int = 0 // 측정 횟수
    
    // MARK: - 누적 메트릭
    private var activeTime: TimeInterval = 0.0 // 전체 주행 시간 (정지 포함)
    private var movingTime: TimeInterval = 0.0 // 실제 이동 시간 (일정 속도 이상)
    private var totalStopDuration: TimeInterval = 0.0 // 정지 시간 누적
    private var locationSampleCount: Int = 0
    private var locationSampleSkippedAccuracyCount: Int = 0
    private var locationSampleUsedCount: Int = 0
    
    private var hardBrakeCount: Int = 0
    private var chatterEventCount: Int = 0
    private var quietEventCount: Int = 0 // Quiet Phase 감지 횟수
    
    // MARK: - 이벤트 상태
    private var isInBrakeEvent: Bool = false
    private var isInChatterEvent: Bool = false
    private var isInQuietPhase: Bool = false // Quiet Phase 상태
    private var transitionGraceRemaining: TimeInterval = 0.0
    private var brakeEpisodeDuration: TimeInterval = 0.0
    private var lastChatterEventTime: TimeInterval?
    private var quietPhaseDuration: TimeInterval = 0.0 // Quiet Phase 지속시간
    
    // MARK: - 모션 추적 (RidingMetricAnalyzer에서 전달)
    private var lastMotionTimestamp: TimeInterval?
    private var lastMotionAccelMS2: Double?
    private var jerkSamples: [(timestamp: TimeInterval, value: Double)] = []
    
    // MARK: - 분석 리포트
    private var sessionStartUptime: TimeInterval?
    private var analysisEvents: [RunSession.AnalysisEvent] = []
    private var analysisSegments: [RunSession.AnalysisSegment] = []
    private var latestBreakdown: RunSession.FlowScoreBreakdown = .empty
    private var latestInstantStability: Double?
    
    // 이벤트 구간(10Hz) 캡처
    private var highResBuffer: [HighResSample] = []
    private var activeCaptures: [ActiveCapture] = []
    private var lastHighResSampleTime: TimeInterval?
    
    // MARK: - 상수 (Tuning: Spicy Mode)
    // 1. Stop / Move Criteria
    private let stopSpeedMS: Double = 2.0 // 약 7.2km/h 이하를 '정지'로 간주
    private let stopExitSpeedMS: Double = 2.2 // 히스테리시스 (상승 시 기준)
    
    // 2. Events Criteria (Stricter)
    private let hardBrakeThreshold: Double = -2.0 // m/s² (was -1.2) -> 슬라이딩 턴 감속 허용, 급정거(사람 회피 등)만 감지
    private let chatterJerkThreshold: Double = 4.5 // 저크(Jerk) 임계값
    private let chatterCooldown: TimeInterval = 1.0
    private let chatterWindow: TimeInterval = 0.1
    private let chatterSpeedGateMS: Double = 4.2 // 이 속도 이상일 때만 떨림 감지
    private let quietTargetG: Double = 1.0 // Quiet Phase 기준 G
    private let quietToleranceG: Double = 0.05 // (was 0.08) 허용 오차 축소 (Very Strict)
    private let quietMinDuration: TimeInterval = 0.3 // (was 0.2) 0.3초 이상 유지해야 인정
    private let quietSpeedGateMS: Double = 5.5 // (New) 20km/h 이상일 때만 보너스 인정
    private let gravityMS2: Double = 9.80665
    private let transitionGraceDuration: TimeInterval = 0.3
    private let slowBrakeDuration: TimeInterval = 2.0
    
    // 3. Scoring Weights (High Variance) - 1000 Point Scale
    private let stabilityWindowSize: Int = 5      // 5초(5샘플) 구간의 분산을 봅니다.
    private let stabilityBase: Double = 300.0    // (was 30.0) 기본 점수 상향 (x10)
    private let stabilityRange: Double = 700.0   // (was 70.0) 안정성 비중 확대 (x10)
    private let varianceDenominator: Double = 3.5 // (Maintained) 3.5로 조정 (슬라이딩 턴 리듬 적절히 허용)
    
    private let stopTimePenaltyWeight: Double = 5.0 // 초당 5점 감점 (x10)
    private let stopTimePenaltyCap: Double = 300.0   // 정지 패널티 최대 300점 제한 (x10)
    
    private let hardBrakePenalty: Double = 40.0      // (was 4.0) 실수 한방에 40점
    private let chatterPenalty: Double = 20.0        // (was 2.0) 털리면 20점
    private let bonusPoint: Double = 20.0            // Quiet Phase 보너스 (+20점)
    
    // 4. 이벤트 구간 샘플링
    private let eventSampleInterval: TimeInterval = 0.1
    private let eventPreBufferSeconds: TimeInterval = 2.0
    private let eventPostBufferSeconds: TimeInterval = 2.0
    
    // MARK: - 외부 제어
    
    func startSession() {
        analysisQueue.async { [weak self] in
            guard let self else { return }
            self.resetSessionState()
            self.sessionStartUptime = ProcessInfo.processInfo.systemUptime
            self.analysisEvents.removeAll()
            self.analysisSegments.removeAll()
            self.highResBuffer.removeAll()
            self.activeCaptures.removeAll()
            self.lastHighResSampleTime = nil
            self.setAnalyzing(true)
        }
    }
    
    func stopSession(completion: @escaping (Int) -> Void) {
        analysisQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(0) }
                return
            }
            if self.activeTime > 0 {
                self.finalizeSessionResult()
            }
            self.finalizeActiveCaptures()
            self.setAnalyzing(false)
            
            let result = self.latestFlowScore ?? 0
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
    
    func updateState(_ newState: RidingState) {
        analysisQueue.async { [weak self] in
            guard let self else { return }
            let previousState = self.currentState
            self.currentState = newState
            
            // Resting으로 진입 시 결과 확정
            if self.isAnalyzingInternal && newState == .resting && previousState != .resting {
                self.finalizeSessionResult()
                self.resetMetricsForNextRun()
            }
            
            // 라이딩 아닐 때는 상태 리셋
            if newState != .riding {
                self.lastTimestamp = nil
                self.lastSpeedMS = nil
                self.isInBrakeEvent = false
                self.isInChatterEvent = false
                self.transitionGraceRemaining = 0.0
                self.brakeEpisodeDuration = 0.0
                self.lastChatterEventTime = nil
                self.resetMotionStats()
            }
        }
    }
    
    func updateLocation(_ location: CLLocation) {
        analysisQueue.async { [weak self] in
            guard let self else { return }
            self.processLocation(location)
        }
    }
    
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
        
        locationSampleCount += 1
        let timestamp = location.timestamp.timeIntervalSince1970
        let currentSpeed = max(0.0, location.speed)
        
        // 유효성 체크 (정확도 등) - 필드 테스트 기준으로 필터 완화
        // speedAccuracy가 음수이면(정보 없음) 필터링하지 않음
        if location.horizontalAccuracy > 80.0
            || (location.speedAccuracy >= 0 && location.speedAccuracy > 10.0) {
            locationSampleSkippedAccuracyCount += 1
            lastTimestamp = timestamp // 시간만 갱신, 계산 건너뜀
            return
        }
        locationSampleUsedCount += 1
        
        guard let lastTime = lastTimestamp else {
            lastTimestamp = timestamp
            lastSpeedMS = currentSpeed
            return
        }
        
        let deltaTime = timestamp - lastTime
        lastTimestamp = timestamp
        
        guard deltaTime > 0 else { return }
        
        // 1. 시간 누적
        activeTime += deltaTime
        
        // 2. 정지 여부 및 Local Stability 계산
        if currentSpeed <= stopSpeedMS {
            totalStopDuration += deltaTime
            // 정지 상태에서는 윈도우 초기화? 아니면 0을 넣어서 "급격한 감속"을 반영?
            // -> 여기서는 윈도우에 0을 넣으면 분산이 커져 "멈추는 과정"도 불안정으로 봅니다.
            // -> 하지만 이미 StopPenalty가 있으므로, Stability 계산에서는 제외하는 것이 깔끔할 수 있음.
            // -> 일단은 제외. 멈춰있는 동안 Stability 깎이는 건 억울할 수 있음.
        } else {
            movingTime += deltaTime
            
            // 3. Local Window Stability
            updateLocalStability(newSpeed: currentSpeed)
        }
        
        // 4. 이벤트 감지 (급제동)
        if let prevSpeed = lastSpeedMS {
            let acceleration = (currentSpeed - prevSpeed) / deltaTime
            
            if acceleration <= hardBrakeThreshold {
                isInBrakeEvent = true
                brakeEpisodeDuration += deltaTime
            } else {
                if isInBrakeEvent {
                    // 짧은 순간의 감속은 노이즈일 수 있으므로 일정 시간 이상 지속되었거나 강도가 쎌 때만 카운트
                    // 여기선 단순화하여 진입했다 나오면 카운트
                    hardBrakeCount += 1
                    recordEvent(.hardBrake, value: brakeEpisodeDuration, speedMS: currentSpeed)
                }
                isInBrakeEvent = false
                brakeEpisodeDuration = 0.0
            }
        }
        lastSpeedMS = currentSpeed
    }
    
    private func updateLocalStability(newSpeed: Double) {
        // 윈도우 채우기
        speedWindow.append(newSpeed)
        if speedWindow.count > stabilityWindowSize {
            speedWindow.removeFirst()
        }
        
        // 윈도우가 꽉 찼을 때만 계산 (초반 진입 안정화)
        if speedWindow.count >= 2 {
            let sum = speedWindow.reduce(0, +)
            let mean = sum / Double(speedWindow.count)
            
            // 분산 계산
            let sumSquaredDiff = speedWindow.reduce(0) { total, val in
                let diff = val - mean
                return total + (diff * diff)
            }
            let variance = sumSquaredDiff / Double(speedWindow.count - 1)
            let stdDev = sqrt(variance)
            
            // 순간 안정성 (0.0 ~ 1.0)
            // stdDev가 높을수록 안정성 낮음
            let instantStability = 1.0 / (1.0 + (stdDev / varianceDenominator))
            
            localStabilitySum += instantStability
            localStabilityCount += 1
            latestInstantStability = instantStability
        }
    }
    
    private func processMotionSample(magnitudeG: Double, timestamp: TimeInterval) {
        guard isAnalyzingInternal else { return }
        guard currentState == .riding else { return }
        
        guard let lastTime = lastMotionTimestamp else {
            lastMotionTimestamp = timestamp
            lastMotionAccelMS2 = magnitudeG * gravityMS2
            return
        }
        let deltaTime = timestamp - lastTime
        lastMotionTimestamp = timestamp
        
        guard deltaTime > 0 else { return }
        
        // Jerk 계산 (떨림 감지)
        let currentAccelMS2 = magnitudeG * gravityMS2
        var jerkValue: Double = 0.0
        if let lastAccel = lastMotionAccelMS2 {
            let jerk = (currentAccelMS2 - lastAccel) / deltaTime
            jerkValue = jerk
            appendJerkSample(jerk, timestamp: timestamp)
            
            if transitionGraceRemaining > 0 {
                transitionGraceRemaining = max(0.0, transitionGraceRemaining - deltaTime)
            }
            
            let isChattering = detectChattering()
            if isChattering {
                // 특정 속도 이상일 때만 Chatter 인정 (저속에서의 덜컹거림은 무시)
                if (lastSpeedMS ?? 0) >= chatterSpeedGateMS
                    && transitionGraceRemaining <= 0
                    && !isInChatterEvent
                    && canRegisterChatterEvent(at: timestamp) {
                    
                    chatterEventCount += 1
                    lastChatterEventTime = timestamp
                    isInChatterEvent = true
                    recordEvent(.chatter, value: jerkValue, speedMS: lastSpeedMS ?? 0.0)
                }
            } else {
                isInChatterEvent = false
            }
        }
        lastMotionAccelMS2 = currentAccelMS2
        
        // 이벤트 구간 샘플링 (10Hz)
        if let elapsed = elapsedTime() {
            let didAppend = updateHighResBuffer(elapsed: elapsed, magnitudeG: magnitudeG, jerk: jerkValue, speedMS: lastSpeedMS ?? 0.0)
            if didAppend {
                updateActiveCaptures(with: elapsed)
            }
        }
        
        // Quiet Phase 감지 (언웨이팅: 1G 근처 유지 + 일정 속도 이상)
        // 20km/h 이상 속도에서만 보너스 인정 (초보자의 저속 주행 악용 방지)
        let isFastEnough = (lastSpeedMS ?? 0) >= quietSpeedGateMS
        let isQuietRange = abs(magnitudeG - quietTargetG) <= quietToleranceG
        
        if isFastEnough && isQuietRange {
            quietPhaseDuration += deltaTime
            if quietPhaseDuration >= quietMinDuration && !isInQuietPhase {
                // 진입 시점 1회 카운트
                quietEventCount += 1
                isInQuietPhase = true
                transitionGraceRemaining = transitionGraceDuration
                recordEvent(.quietPhase, value: quietPhaseDuration, speedMS: lastSpeedMS ?? 0.0)
            }
        } else {
            quietPhaseDuration = 0.0
            isInQuietPhase = false
        }
    }
    
    // MARK: - 결과 계산 (핵심)
    
    private func finalizeSessionResult() {
        // 1. Calculate Average Stability
        let avgStability: Double
        if localStabilityCount > 0 {
            avgStability = localStabilitySum / Double(localStabilityCount)
        } else {
            avgStability = 0.0 // 데이터 없으면 0으로 처리
        }
        
        // 2. Base Score (Spicy Mode)
        // Base 300 + (Max 700 * Stability)
        // Stability 0.5 -> 300 + 350 = 650점 (초보/중수 구간)
        // Stability 0.8 -> 300 + 560 = 860점 (고수 구간)
        // Stability 0.95 -> 300 + 665 = 965점 (프로)
        let baseScore = stabilityBase + (stabilityRange * avgStability)
        var score = baseScore
        
        // ActiveTime 너무 짧으면(5초 미만) 점수 무효화 -> 0점
        if activeTime < 5.0 { score = 0 }
        
        // 이동 샘플이 부족하면(리프트/저속) 점수 무효화
        if movingTime < 5.0 || localStabilityCount == 0 { score = 0 }
        
        // 3. Apply Penalties & Bonus
        
        // (A) Stop Penalty (Capped)
        // 정지 패널티는 최대 300점까지만 까임 (300점 까이면 이미 치명적)
        // 300점 / 5.0 = 60초. 즉 1분 이상 쉬면 최대 감점 도달. 더 쉬어도 더 안 까임.
        let rawStopPenalty = totalStopDuration * stopTimePenaltyWeight
        let stopPenalty = min(stopTimePenaltyCap, rawStopPenalty)
        
        // (B) Event Penalties (Increased) & Bonus
        let brakePenalty = Double(hardBrakeCount) * hardBrakePenalty
        let chatterDeduction = Double(chatterEventCount) * chatterPenalty
        let quietBonus = Double(quietEventCount) * bonusPoint // Quiet Phase 보너스 추가
        
        // 점수 반영: 감점은 빼고 가산점은 더함
        score = score - (stopPenalty + brakePenalty + chatterDeduction) + quietBonus
        
        // 4. Final Clamp (Max 1000)
        let finalScore = max(0.0, min(1000.0, score))
        let resultInt = Int(finalScore.rounded())
        
        latestBreakdown = RunSession.FlowScoreBreakdown(
            avgStability: avgStability,
            baseScore: baseScore,
            activeTime: activeTime,
            movingTime: movingTime,
            totalStopDuration: totalStopDuration,
            stopPenalty: stopPenalty,
            hardBrakeCount: hardBrakeCount,
            brakePenalty: brakePenalty,
            chatterEventCount: chatterEventCount,
            chatterPenalty: chatterDeduction,
            quietEventCount: quietEventCount,
            quietBonus: quietBonus,
            finalScore: resultInt,
            locationSampleCount: locationSampleCount,
            locationSampleSkippedAccuracyCount: locationSampleSkippedAccuracyCount,
            locationSampleUsedCount: locationSampleUsedCount,
            stabilitySampleCount: localStabilityCount
        )
        
        print("[FlowScore(Spicy)] AvgStability: \(String(format: "%.2f", avgStability)) -> Base: \(String(format: "%.1f", stabilityBase + (stabilityRange * avgStability)))")
        print("[FlowScore] StopTime: \(String(format: "%.1fs", totalStopDuration)) -> -\(stopPenalty) (Cap: \(stopTimePenaltyCap))")
        print("[FlowScore] HardBrake: \(hardBrakeCount) * \(hardBrakePenalty) = -\(brakePenalty)")
        print("[FlowScore] Chatter: \(chatterEventCount) * \(chatterPenalty) = -\(chatterDeduction)")
        print("[FlowScore] QuietBonus: \(quietEventCount) * \(bonusPoint) = +\(quietBonus)")
        print("[FlowScore] Final: \(resultInt)")
        
        RidingMetricAnalyzer.shared.updateFlowScore(resultInt)
        
        DispatchQueue.main.async { [weak self] in
            self?.latestFlowScore = resultInt
        }
    }
    
    // MARK: - Helpers
    
    private func resetSessionState() {
        resetMetricsForNextRun()
        latestBreakdown = .empty
        latestInstantStability = nil
        DispatchQueue.main.async { [weak self] in
            self?.latestFlowScore = nil
        }
    }
    
    private func resetMetricsForNextRun() {
        lastTimestamp = nil
        lastSpeedMS = nil
        
        localStabilitySum = 0.0
        localStabilityCount = 0
        speedWindow.removeAll()
        
        activeTime = 0.0
        movingTime = 0.0
        totalStopDuration = 0.0
        locationSampleCount = 0
        locationSampleSkippedAccuracyCount = 0
        locationSampleUsedCount = 0
        
        hardBrakeCount = 0
        chatterEventCount = 0
        quietEventCount = 0
        
        isInBrakeEvent = false
        isInChatterEvent = false
        isInQuietPhase = false
        brakeEpisodeDuration = 0.0
        transitionGraceRemaining = 0.0
        lastChatterEventTime = nil
        quietPhaseDuration = 0.0
        
        resetMotionStats()
        
        highResBuffer.removeAll()
        activeCaptures.removeAll()
        lastHighResSampleTime = nil
    }
    
    private func resetMotionStats() {
        lastMotionTimestamp = nil
        lastMotionAccelMS2 = nil
        jerkSamples.removeAll()
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
    
    // MARK: - 분석 이벤트 기록
    
    private func elapsedTime() -> TimeInterval? {
        guard let start = sessionStartUptime else { return nil }
        return ProcessInfo.processInfo.systemUptime - start
    }
    
    private func recordEvent(_ type: RunSession.AnalysisEvent.EventType, value: Double? = nil, speedMS: Double? = nil) {
        guard let elapsed = elapsedTime() else { return }
        let speedKmH = speedMS.map { max(0.0, $0 * 3.6) }
        let event = RunSession.AnalysisEvent(
            t: elapsed,
            type: type,
            value: value,
            speed: speedKmH
        )
        analysisEvents.append(event)
        
        // 이벤트 구간 캡처 시작
        startEventCapture(type: type, eventTime: elapsed)
    }
    
    private func updateHighResBuffer(elapsed: TimeInterval, magnitudeG: Double, jerk: Double, speedMS: Double) -> Bool {
        if let last = lastHighResSampleTime, (elapsed - last) < eventSampleInterval {
            return false
        }
        lastHighResSampleTime = elapsed
        
        let speedKmH = max(0.0, speedMS * 3.6)
        let sample = HighResSample(t: elapsed, g: magnitudeG, jerk: jerk, speed: speedKmH)
        highResBuffer.append(sample)
        
        let cutoff = elapsed - eventPreBufferSeconds
        while let first = highResBuffer.first, first.t < cutoff {
            highResBuffer.removeFirst()
        }
        return true
    }
    
    private func startEventCapture(type: RunSession.AnalysisEvent.EventType, eventTime: TimeInterval) {
        let preSamples = highResBuffer
        let capture = ActiveCapture(type: type, eventTime: eventTime, samples: preSamples)
        activeCaptures.append(capture)
    }
    
    private func updateActiveCaptures(with elapsed: TimeInterval) {
        guard !activeCaptures.isEmpty else { return }
        
        for index in activeCaptures.indices {
            let eventTime = activeCaptures[index].eventTime
            if elapsed >= eventTime && elapsed <= (eventTime + eventPostBufferSeconds) {
                if let lastSample = highResBuffer.last {
                    activeCaptures[index].samples.append(lastSample)
                }
            }
        }
        
        // 종료 조건 충족 캡처 정리
        let finished = activeCaptures.filter { elapsed > ($0.eventTime + eventPostBufferSeconds) }
        if !finished.isEmpty {
            for capture in finished {
                appendSegment(from: capture)
            }
            activeCaptures.removeAll { elapsed > ($0.eventTime + eventPostBufferSeconds) }
        }
    }
    
    private func finalizeActiveCaptures() {
        guard !activeCaptures.isEmpty else { return }
        for capture in activeCaptures {
            appendSegment(from: capture)
        }
        activeCaptures.removeAll()
    }
    
    private func appendSegment(from capture: ActiveCapture) {
        guard let first = capture.samples.first else { return }
        let segment = RunSession.AnalysisSegment(
            type: capture.type,
            tStart: first.t,
            interval: eventSampleInterval,
            gSamples: capture.samples.map { $0.g },
            jerkSamples: capture.samples.map { $0.jerk },
            speedSamples: capture.samples.map { $0.speed }
        )
        analysisSegments.append(segment)
    }
    
    // MARK: - 외부 조회
    
    func exportAnalysisData() -> (events: [RunSession.AnalysisEvent], segments: [RunSession.AnalysisSegment], breakdown: RunSession.FlowScoreBreakdown) {
        return analysisQueue.sync {
            (analysisEvents, analysisSegments, latestBreakdown)
        }
    }
    
    private func setAnalyzing(_ isAnalyzing: Bool) {
        isAnalyzingInternal = isAnalyzing
        DispatchQueue.main.async { [weak self] in
            self?.isAnalyzing = isAnalyzing
        }
    }
}

// MARK: - 이벤트 구간 샘플
private struct HighResSample {
    var t: Double
    var g: Double
    var jerk: Double
    var speed: Double
}

private struct ActiveCapture {
    var type: RunSession.AnalysisEvent.EventType
    var eventTime: Double
    var samples: [HighResSample]
}
