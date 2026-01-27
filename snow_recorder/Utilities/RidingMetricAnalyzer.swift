import Foundation
import CoreMotion
import CoreLocation
import Combine

/// 라이딩 스타일 지표를 실시간 분석하는 매니저
final class RidingMetricAnalyzer: ObservableObject {
    static let shared = RidingMetricAnalyzer()
    
    // MARK: - 퍼블리시드 (UI 바인딩용)
    @Published private(set) var latestResult: RidingSessionResult?
    @Published private(set) var isAnalyzing: Bool = false
    
    // MARK: - 코어모션
    private let motionManager = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "RidingMetricAnalyzer.motionQueue"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    
    // MARK: - 내부 상태 (스레드 안전 보장)
    private let analysisQueue = DispatchQueue(label: "RidingMetricAnalyzer.analysisQueue")
    private var isAnalyzingInternal = false
    private var currentState: RidingState = .resting
    private var currentSpeedMS: Double = 0.0
    
    // MARK: - 전처리/스무딩
    private var lastMotionTimestamp: TimeInterval?
    private var previousRawMagnitude: Double?
    private var smoothingBuffer: [Double] = []
    private var smoothingSum: Double = 0.0
    
    // MARK: - 누적 지표
    private var edgeRawScore: Double = 0.0
    private var tieredTimeTotal: TimeInterval = 0.0
    private var tier2PlusTime: TimeInterval = 0.0
    private var maxGForce: Double = 0.0
    private var speedSum: Double = 0.0
    private var speedSampleCount: Int = 0
    private var maxSpeed: Double = 0.0 // 추가: 이번 런의 최고 속도
    private var latestEdgeResult: RidingSessionResult?
    
    // MARK: - 분석 리포트 (1초 샘플)
    private let sampleInterval: TimeInterval = 1.0
    private var sessionStartUptime: TimeInterval?
    private var currentSampleIndex: Int = 0
    private var sampleAccumulator = SampleAccumulator()
    private var analysisSamples: [RunSession.AnalysisSample] = []
    private var lastSmoothedMagnitude: Double?
    private var latestEdgeBreakdown: RunSession.EdgeScoreBreakdown = .empty
    
    // MARK: - 상수 (튜닝 가능)
    private let updateInterval: TimeInterval = 1.0 / 60.0
    private let speedGateMS: Double = 4.2
    private let bumpDeltaThresholdG: Double = 0.5
    private let smoothingWindowSize: Int = 10
    private let tier1MinG: Double = 1.2
    private let tier2MinG: Double = 1.4
    private let tier3MinG: Double = 1.7
    private let tier1Weight: Double = 0.2
    private let tier2Weight: Double = 2.5
    private let tier3Weight: Double = 6.0
    private let edgeLogNormalizationTarget: Double = 260.0
    private let proCapThresholdG: Double = 1.7
    private let proCapScore: Double = 940.0             // (was 94.0) 1000점 만점 스케일
    private let tier2RatioThreshold: Double = 0.25
    private let tier2RatioScoreCap: Double = 790.0      // (was 79.0) 1000점 만점 스케일
    
    // MARK: - 초기화
    init() {
        motionManager.deviceMotionUpdateInterval = updateInterval
    }
    
    // MARK: - 외부 제어
    
    /// 세션 분석 시작
    func startSession() {
        analysisQueue.async { [weak self] in
            guard let self else { return }
            self.resetSessionState()
            self.sessionStartUptime = ProcessInfo.processInfo.systemUptime
            self.currentSampleIndex = 0
            self.sampleAccumulator = SampleAccumulator()
            self.analysisSamples.removeAll()
            self.lastSmoothedMagnitude = nil
            self.setAnalyzing(true)
            if self.currentState == .riding {
                self.startMotionUpdatesIfNeeded()
            }
        }
    }
    
    /// 세션 분석 종료 (강제 종료용)
    func stopSession(completion: @escaping (RidingSessionResult?) -> Void) {
        analysisQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self.stopMotionUpdates()
            self.finalizeSessionResult()
            self.setAnalyzing(false)
            
            // 결과 반환
            let result = self.latestEdgeResult
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
    
    /// 현재 활동 상태 업데이트 (LocationManager에서 전달)
    func updateState(_ newState: RidingState) {
        analysisQueue.async { [weak self] in
            guard let self else { return }
            let previousState = self.currentState
            self.currentState = newState
            
            switch newState {
            case .riding:
                if self.isAnalyzingInternal {
                    self.startMotionUpdatesIfNeeded()
                }
            case .resting:
                self.stopMotionUpdates()
                if self.isAnalyzingInternal && previousState != .resting {
                    self.finalizeSessionResult()
                    self.resetMetricsForNextRun()
                }
            case .onLift:
                self.stopMotionUpdates()
                self.resetSmoothing()
            }
        }
    }
    
    /// 현재 속도 업데이트 (m/s)
    func updateSpeed(_ speedMS: Double) {
        analysisQueue.async { [weak self] in
            guard let self else { return }
            let safeSpeed = max(0.0, speedMS)
            self.currentSpeedMS = safeSpeed
            
            if self.isAnalyzingInternal && self.currentState == .riding {
                self.speedSum += safeSpeed
                self.speedSampleCount += 1
                if safeSpeed > self.maxSpeed {
                    self.maxSpeed = safeSpeed
                }
            }
        }
    }
    
    /// 위치 기반 속도 업데이트 (m/s)
    func updateLocation(_ location: CLLocation) {
        updateSpeed(location.speed)
    }
    
    // MARK: - 코어모션 처리
    
    private func startMotionUpdatesIfNeeded() {
        guard motionManager.isDeviceMotionAvailable else { return }
        guard !motionManager.isDeviceMotionActive else { return }
        
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: motionQueue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.analysisQueue.async {
                self.handleDeviceMotion(motion)
            }
        }
    }
    
    private func stopMotionUpdates() {
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
    }
    
    private func handleDeviceMotion(_ motion: CMDeviceMotion) {
        guard isAnalyzingInternal else { return }
        
        let timestamp = motion.timestamp
        let totalAccelX = motion.userAcceleration.x + motion.gravity.x
        let totalAccelY = motion.userAcceleration.y + motion.gravity.y
        let totalAccelZ = motion.userAcceleration.z + motion.gravity.z
        let rawMagnitude = sqrt(
            totalAccelX * totalAccelX +
            totalAccelY * totalAccelY +
            totalAccelZ * totalAccelZ
        )
        
        // 타임스탬프 업데이트 (첫 프레임 보호)
        guard let lastTimestamp = lastMotionTimestamp else {
            lastMotionTimestamp = timestamp
            previousRawMagnitude = rawMagnitude
            return
        }
        
        let deltaTime = timestamp - lastTimestamp
        lastMotionTimestamp = timestamp
        
        if deltaTime <= 0 {
            previousRawMagnitude = rawMagnitude
            return
        }
        
        // 속도 게이트: 일정 속도 이하이면 계산 중단
        guard currentSpeedMS > speedGateMS else {
            previousRawMagnitude = rawMagnitude
            resetSmoothing()
            return
        }
        
        // 델타 체크: 범프(충격) 프레임 제거
        if let prev = previousRawMagnitude, abs(rawMagnitude - prev) >= bumpDeltaThresholdG {
            previousRawMagnitude = rawMagnitude
            return
        }
        previousRawMagnitude = rawMagnitude
        
        // 스무딩: 단순 이동 평균
        let smoothedMagnitude = appendToSmoothing(rawMagnitude)
        
        // 저크 계산 (G/s)
        let jerk: Double
        if let last = lastSmoothedMagnitude {
            jerk = (smoothedMagnitude - last) / deltaTime
        } else {
            jerk = 0.0
        }
        lastSmoothedMagnitude = smoothedMagnitude
        
        // 1초 단위 샘플 누적
        if let elapsed = elapsedTime() {
            updateAnalysisSample(elapsed: elapsed, g: smoothedMagnitude, jerk: jerk, speedMS: currentSpeedMS)
        }
        
        // Flow Score 보정용 모션 샘플 전달
        FlowScoreAnalyzer.shared.updateMotionSample(magnitudeG: smoothedMagnitude, timestamp: timestamp)
        
        // 최대 G-Force 갱신 (스무딩 후 값)
        if smoothedMagnitude > maxGForce {
            maxGForce = smoothedMagnitude
        }
        
        // 엣지 점수 계산 로직 (지수 가중치)
        let weight = edgeWeight(for: smoothedMagnitude)
        if weight > 0 {
            tieredTimeTotal += deltaTime
            if smoothedMagnitude >= tier2MinG {
                tier2PlusTime += deltaTime
            }
            edgeRawScore += (smoothedMagnitude * weight) * deltaTime
        }
    }
    
    // MARK: - 유틸
    
    private func appendToSmoothing(_ value: Double) -> Double {
        smoothingBuffer.append(value)
        smoothingSum += value
        
        if smoothingBuffer.count > smoothingWindowSize, let first = smoothingBuffer.first {
            smoothingSum -= first
            smoothingBuffer.removeFirst()
        }
        
        let divisor = Double(smoothingBuffer.count)
        guard divisor > 0 else { return value }
        return smoothingSum / divisor
    }
    
    private func resetSmoothing() {
        smoothingBuffer.removeAll()
        smoothingSum = 0.0
    }
    
    private func resetSessionState() {
        resetMetricsForNextRun()
        latestEdgeBreakdown = .empty
        DispatchQueue.main.async { [weak self] in
            self?.latestResult = nil
        }
        latestEdgeResult = nil
    }

    private func resetMetricsForNextRun() {
        lastMotionTimestamp = nil
        previousRawMagnitude = nil
        resetSmoothing()
        
        edgeRawScore = 0.0
        tieredTimeTotal = 0.0
        tier2PlusTime = 0.0
        maxGForce = 0.0
        speedSum = 0.0
        speedSampleCount = 0
        maxSpeed = 0.0
    }
    
    private func finalizeSessionResult() {
        let edgeScore = calculateEdgeScore()
        let flowScore = FlowScoreAnalyzer.shared.latestFlowScore ?? 0
        let averageSpeed = speedSampleCount > 0 ? (speedSum / Double(speedSampleCount)) : 0.0
        
        // 샘플 버킷 플러시
        flushAnalysisSample()
        
        let result = RidingSessionResult(
            edgeScore: edgeScore,
            flowScore: flowScore,
            maxGForce: maxGForce,
            averageSpeed: averageSpeed,
            maxSpeed: maxSpeed
        )
        
        latestEdgeResult = result
        DispatchQueue.main.async { [weak self] in
            self?.latestResult = result
        }
    }
    
    private func calculateEdgeScore() -> Int {
        guard edgeRawScore > 0 else {
            latestEdgeBreakdown = .empty
            return 0
        }
        
        let normalized = log(1.0 + edgeRawScore) / log(1.0 + edgeLogNormalizationTarget)
        let rawScore = max(0.0, min(1000.0, normalized * 1000.0))
        var score = rawScore
        
        let proCapApplied = maxGForce < proCapThresholdG && score > proCapScore
        if proCapApplied {
            score = min(score, proCapScore)
        }
        
        let tier2Ratio = tieredTimeTotal > 0 ? (tier2PlusTime / tieredTimeTotal) : 0.0
        let tier2CapApplied = tier2Ratio < tier2RatioThreshold && score > tier2RatioScoreCap
        if tier2CapApplied {
            score = min(score, tier2RatioScoreCap)
        }
        
        latestEdgeBreakdown = RunSession.EdgeScoreBreakdown(
            edgeRawScore: edgeRawScore,
            normalized: normalized,
            rawScore: rawScore,
            finalScore: Int(score.rounded()),
            maxGForce: maxGForce,
            tieredTimeTotal: tieredTimeTotal,
            tier2PlusTime: tier2PlusTime,
            tier2Ratio: tier2Ratio,
            proCapApplied: proCapApplied,
            tier2CapApplied: tier2CapApplied
        )
        
        return Int(score.rounded())
    }
    
    private func edgeWeight(for magnitude: Double) -> Double {
        if magnitude >= tier3MinG {
            return tier3Weight
        }
        if magnitude >= tier2MinG {
            return tier2Weight
        }
        if magnitude >= tier1MinG {
            return tier1Weight
        }
        return 0.0
    }
    
    /// FlowScoreAnalyzer가 계산한 점수를 반영 (런 단위 동기화)
    func updateFlowScore(_ score: Int) {
        analysisQueue.async { [weak self] in
            guard let self else { return }
            guard var result = self.latestEdgeResult else { return }
            result.flowScore = score
            self.latestEdgeResult = result
            DispatchQueue.main.async { [weak self] in
                self?.latestResult = result
            }
        }
    }
    
    // MARK: - 분석 샘플 생성
    
    private func elapsedTime() -> TimeInterval? {
        guard let start = sessionStartUptime else { return nil }
        return ProcessInfo.processInfo.systemUptime - start
    }
    
    private func updateAnalysisSample(elapsed: TimeInterval, g: Double, jerk: Double, speedMS: Double) {
        let sampleIndex = Int(elapsed / sampleInterval)
        if sampleIndex != currentSampleIndex {
            flushAnalysisSample()
            currentSampleIndex = sampleIndex
        }
        
        // 속도 누적 (km/h)
        let speedKmH = max(0.0, speedMS * 3.6)
        sampleAccumulator.speedSum += speedKmH
        sampleAccumulator.speedSumSq += speedKmH * speedKmH
        sampleAccumulator.speedCount += 1
        if speedKmH > sampleAccumulator.speedMax {
            sampleAccumulator.speedMax = speedKmH
        }
        
        // G 누적
        sampleAccumulator.gSum += g
        sampleAccumulator.gCount += 1
        if g > sampleAccumulator.gMax {
            sampleAccumulator.gMax = g
        }
        
        // 저크 피크
        let jerkAbs = abs(jerk)
        if jerkAbs > sampleAccumulator.jerkPeak {
            sampleAccumulator.jerkPeak = jerkAbs
        }
    }
    
    private func flushAnalysisSample() {
        guard sampleAccumulator.speedCount > 0 || sampleAccumulator.gCount > 0 else { return }
        
        let speedAvg = sampleAccumulator.speedCount > 0 ? (sampleAccumulator.speedSum / Double(sampleAccumulator.speedCount)) : 0.0
        let speedVar = sampleAccumulator.speedCount > 0
            ? max(0.0, (sampleAccumulator.speedSumSq / Double(sampleAccumulator.speedCount)) - (speedAvg * speedAvg))
            : 0.0
        let speedStdDev = sqrt(speedVar)
        
        let gAvg = sampleAccumulator.gCount > 0 ? (sampleAccumulator.gSum / Double(sampleAccumulator.gCount)) : 0.0
        
        let t = Double(currentSampleIndex) * sampleInterval
        let sample = RunSession.AnalysisSample(
            t: t,
            speedAvg: speedAvg,
            speedMax: sampleAccumulator.speedMax,
            speedStdDev: speedStdDev,
            gAvg: gAvg,
            gMax: sampleAccumulator.gMax,
            jerkPeak: sampleAccumulator.jerkPeak
        )
        analysisSamples.append(sample)
        
        sampleAccumulator = SampleAccumulator()
    }
    
    // MARK: - 외부 조회
    
    func exportAnalysisData() -> (samples: [RunSession.AnalysisSample], edgeBreakdown: RunSession.EdgeScoreBreakdown) {
        return analysisQueue.sync {
            (analysisSamples, latestEdgeBreakdown)
        }
    }
    
    private func setAnalyzing(_ isAnalyzing: Bool) {
        isAnalyzingInternal = isAnalyzing
        DispatchQueue.main.async { [weak self] in
            self?.isAnalyzing = isAnalyzing
        }
    }
}

// MARK: - 분석 샘플 누적용 구조체
private struct SampleAccumulator {
    var speedSum: Double = 0.0
    var speedSumSq: Double = 0.0
    var speedCount: Int = 0
    var speedMax: Double = 0.0
    
    var gSum: Double = 0.0
    var gCount: Int = 0
    var gMax: Double = 0.0
    
    var jerkPeak: Double = 0.0
}
