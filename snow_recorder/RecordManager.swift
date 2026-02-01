import Foundation
import Combine
import SwiftData
import CoreLocation

/// 녹화 상태 및 타이머를 관리하는 매니저 클래스 (Singleton)
class RecordManager: ObservableObject {
    static let shared = RecordManager()
    
    @Published var isRecording: Bool = false       // 현재 녹화 중 여부
    @Published var isPaused: Bool = false          // 일시 정지 여부
    @Published var elapsedTime: TimeInterval = 0   // 경과 시간 (초)
    @Published private(set) var currentRunMetrics: [RunSession.RunMetric] = [] // 세션 중 런별 스탯
    
    private var timer: Timer?
    private var startTime: Date?
    private var pauseTime: Date?
    private var totalPausedDuration: TimeInterval = 0
    
    private var cancellables = Set<AnyCancellable>()
    private var tempRunMetrics: [RunSession.RunMetric] = []
    
    private init() {}
    
    /// 녹화 시작
    func startRecording() {
        guard !isRecording else { return }
        
        isRecording = true
        elapsedTime = 0
        startTime = Date()
        tempRunMetrics = [] // 초기화
        currentRunMetrics = []
        
        // 라이딩 점수 분석 시작
        RidingMetricAnalyzer.shared.startSession()
        FlowScoreAnalyzer.shared.startSession()
        
        // LocationManager 트래킹 시작
        LocationManager.shared.startTracking()
        
        // 런 종료(분석 완료) 시점에 데이터 수집을 위한 구독
        // RidingMetricAnalyzer가 resting 상태가 되어 결과를 내뱉을 때마다 수집
        RidingMetricAnalyzer.shared.$latestResult
            .dropFirst() // 초기값 제외
            .compactMap { $0 }
            .sink { [weak self] result in
                self?.recordRunMetric(result: result)
            }
            .store(in: &cancellables)
            
        // 1초 단위 타이머 시작
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.startTime else { return }
            
            if !self.isPaused {
                self.elapsedTime = Date().timeIntervalSince(start) - self.totalPausedDuration
            }
        }
    }
    
    // 런 분석 결과가 나오면 RunMetric으로 변환하여 임시 저장
    private func recordRunMetric(result: RidingSessionResult, isRetry: Bool = false, retryCount: Int = 0) {
        // LocationManager의 현재(직전) 런 정보 가져오기
        let locationManager = LocationManager.shared
        let maxRetryCount = 5
        let retryDelay: TimeInterval = 0.4
        let metricReadyEpsilon = 0.1
        
        func scheduleRetry(_ reason: String) {
            guard retryCount < maxRetryCount else {
                print("⚠️ Run Metric 재시도 한도 초과: \(reason) (runCount=\(locationManager.completedRunCount))")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { [weak self] in
                self?.recordRunMetric(result: result, isRetry: true, retryCount: retryCount + 1)
            }
        }
        
        // 주의: Riding -> Resting 전환 후 결과가 오지만, 그 사이 사용자가 급격히 다시 Riding을 시작했을 수도 있음.
        // 따라서 TimelineEvents가 아니라 완료된 런 메타데이터 기준으로 매칭.
        
        // 노이즈 런이 확정된 직후라면 결과를 무시 (런 확정 이후 재시도)
        if !locationManager.lastRunWasAccepted {
            scheduleRetry("lastRunWasAccepted=false")
            return
        }
        
        let runNumber = locationManager.completedRunCount
        guard runNumber > 0,
              let startTime = locationManager.completedRunStartTime(for: runNumber),
              let endTime = locationManager.completedRunEndTime(for: runNumber) else {
            // 아직 끝난 런이 없거나 매칭 실패 → 짧게 재시도
            scheduleRetry("run meta not ready")
            return
        }
        
        let slopeName = locationManager.completedRunSlopeName(for: runNumber) ?? "알 수 없는 슬로프"
        
        // RidingSessionResult speed unit: m/s -> convert to km/h for UI consistency
        let runDistance = locationManager.completedRunDistance(for: runNumber)
        let runVerticalDrop = locationManager.completedRunVerticalDrop(for: runNumber)
        let duration = endTime.timeIntervalSince(startTime)
        let runSpeedSeries = locationManager.completedRunSpeedSeries(for: runNumber)
        let seriesMaxSpeed = runSpeedSeries.max()
        let seriesAvgSpeed: Double? = {
            guard !runSpeedSeries.isEmpty else { return nil }
            let sum = runSpeedSeries.reduce(0, +)
            return sum / Double(runSpeedSeries.count)
        }()
        
        // 거리/하강이 아직 확정 전이면 잠시 대기 후 재시도
        if runDistance <= metricReadyEpsilon && runVerticalDrop <= metricReadyEpsilon {
            scheduleRetry("distance/vertical not ready")
            return
        }
        
        // 노이즈 런 필터: 40초 이하 + 하강고도 30m 이하
        if duration <= 40.0 && runVerticalDrop <= 30.0 {
            return
        }
        
        // 중복 저장 방지 (같은 runNumber 기준으로 확인)
        if let existingIndex = tempRunMetrics.firstIndex(where: { $0.runNumber == runNumber }) {
            // Flow는 늦게 도착할 수 있으므로, 기존 값보다 큰 값이면 갱신
            let updatedFlowScore = max(tempRunMetrics[existingIndex].flowScore, result.flowScore)
            var didUpdate = false
            if updatedFlowScore != tempRunMetrics[existingIndex].flowScore {
                tempRunMetrics[existingIndex].flowScore = updatedFlowScore
                didUpdate = true
            }
            if tempRunMetrics[existingIndex].leftTurnRatio != result.leftTurnRatio
                || tempRunMetrics[existingIndex].rightTurnRatio != result.rightTurnRatio {
                tempRunMetrics[existingIndex].leftTurnRatio = result.leftTurnRatio
                tempRunMetrics[existingIndex].rightTurnRatio = result.rightTurnRatio
                didUpdate = true
            }
            // 거리/버티컬이 0으로 저장됐던 경우 보정
            if tempRunMetrics[existingIndex].distance <= metricReadyEpsilon, runDistance > metricReadyEpsilon {
                tempRunMetrics[existingIndex].distance = runDistance
                didUpdate = true
            }
            if tempRunMetrics[existingIndex].verticalDrop <= metricReadyEpsilon, runVerticalDrop > metricReadyEpsilon {
                tempRunMetrics[existingIndex].verticalDrop = runVerticalDrop
                didUpdate = true
            }
            if didUpdate {
                currentRunMetrics = tempRunMetrics
                print("🔁 Run Metric Updated: Run #\(tempRunMetrics[existingIndex].runNumber), Flow: \(updatedFlowScore), Dist: \(Int(tempRunMetrics[existingIndex].distance))m, Drop: \(Int(tempRunMetrics[existingIndex].verticalDrop))m")
            }
            return
        }
        
        // Flow Score (결과에 포함된 값 사용)
        let flowScore = result.flowScore
        
        let edgeBreakdown = RidingMetricAnalyzer.shared.exportAnalysisData().edgeBreakdown
        let flowBreakdown = FlowScoreAnalyzer.shared.exportAnalysisData().breakdown
        let flowScoreEvents = FlowScoreAnalyzer.shared.exportScoreEvents()
        let edgeScoreEvents = RidingMetricAnalyzer.shared.exportScoreEvents()
        let scoreEvents = (flowScoreEvents + edgeScoreEvents).sorted { $0.t < $1.t }
        
        let metric = RunSession.RunMetric(
            runNumber: runNumber, // 완료된 런 기준 번호
            slopeName: slopeName,
            startTime: startTime,
            endTime: endTime,
            duration: duration,
            distance: runDistance,
            verticalDrop: runVerticalDrop,
            maxSpeed: seriesMaxSpeed ?? (result.maxSpeed * 3.6),
            avgSpeed: seriesAvgSpeed ?? (result.averageSpeed * 3.6),
            edgeScore: result.edgeScore,
            flowScore: flowScore ?? 0,
            maxGForce: result.maxGForce,
            leftTurnRatio: result.leftTurnRatio,
            rightTurnRatio: result.rightTurnRatio,
            scoreEvents: scoreEvents.isEmpty ? nil : scoreEvents,
            edgeBreakdown: edgeBreakdown,
            flowBreakdown: flowBreakdown
        )
        
        tempRunMetrics.append(metric)
        currentRunMetrics = tempRunMetrics
        print("✅ Run Metric Recorded: Run #\(metric.runNumber), Slope: \(metric.slopeName), Edge: \(metric.edgeScore), Flow: \(metric.flowScore)")
    }
    
    /// 녹화 일시 정지
    func pauseRecording() {
        guard isRecording && !isPaused else { return }
        isPaused = true
        pauseTime = Date()
        LocationManager.shared.pauseTracking()
    }
    
    /// 녹화 재개
    func resumeRecording() {
        guard isRecording && isPaused, let pauseStart = pauseTime else { return }
        
        // 정지된 시간 누적
        totalPausedDuration += Date().timeIntervalSince(pauseStart)
        pauseTime = nil
        isPaused = false
        LocationManager.shared.resumeTracking()
    }
    
    /// 녹화 종료 & 저장
    func stopRecording(context: ModelContext) {
        guard isRecording, let start = startTime else { return }
        
        // LocationManager 트래킹 종료 (최종 데이터 확정)
        LocationManager.shared.stopTracking()
        cancellables.removeAll() // 구독 취소
        
        let end = Date()
        let duration = elapsedTime
        

        // 라이딩 점수 분석 종료 및 결과 수신 (마지막 런이 진행 중이었다면 여기서 처리됨)
        // 비동기 처리 때문에 복잡해지는데, 마지막 런이 있다면 stopSession 콜백에서 tempRunMetrics에 추가해줘야 함.
        // 하지만 stopSession 콜백은 '마지막 상태'에 대한 결과임.
        
        RidingMetricAnalyzer.shared.stopSession { [weak self] ridingResult in
            guard let self = self else { return }
            
            FlowScoreAnalyzer.shared.stopSession { [weak self] flowScore in
                guard let self = self else { return }
                
                // 마지막 런 처리 확인: 마지막 이벤트가 Riding이고 아직 저장이 안됐다면 저장 시도
                // 세션 종료 시점에 Riding/보류 상태였다면 마지막 런 메트릭이 누락될 수 있으므로 강제 확정
                let locationManager = LocationManager.shared
                if let ridingResult, locationManager.lastRunWasAccepted {
                    var finalizedResult = ridingResult
                    finalizedResult.flowScore = flowScore
                    if self.tempRunMetrics.count < locationManager.completedRunCount {
                        self.recordRunMetric(result: finalizedResult)
                    }
                }
                
                // LocationManager에서 메트릭 수집
                let distance = locationManager.totalDistance
                let maxSpeed = locationManager.maxSpeed
                let avgSpeed = locationManager.avgSpeed
                let verticalDrop = locationManager.verticalDrop
                let runCount = locationManager.runCount
                let currentSlope = locationManager.currentSlope?.name
                let sessionSlopes = locationManager.sessionSlopeCounts
                let routeCoordinates = locationManager.routeCoordinates
                let routeSpeeds = locationManager.routeSpeeds
                let routeTimestamps = locationManager.routeTimestamps
                let routeAltitudes = locationManager.routeAltitudes
                let routeDistances = locationManager.routeDistances
                let routeStates = locationManager.routeStates
                let runStartIndices = locationManager.runStartIndices
                let detectedResortName = self.detectResortName(from: routeCoordinates)
                
                // 분석 리포트 데이터
                let ridingAnalysis = RidingMetricAnalyzer.shared.exportAnalysisData()
                let flowAnalysis = FlowScoreAnalyzer.shared.exportAnalysisData()
                
                // Best Score 계산
                let bestEdgeMetric = self.tempRunMetrics.max { $0.edgeScore < $1.edgeScore }
                let bestFlowMetric = self.tempRunMetrics.max { $0.flowScore < $1.flowScore }
                
                let bestEdgeScore = bestEdgeMetric?.edgeScore ?? (ridingResult?.edgeScore ?? 0)
                let bestFlowScore = bestFlowMetric?.flowScore ?? flowScore
                let maxG = self.tempRunMetrics.map { $0.maxGForce }.max() ?? (ridingResult?.maxGForce ?? 0.0)
                let metricMaxSpeed = self.tempRunMetrics.map { $0.maxSpeed }.max()
                let sessionMaxSpeed = metricMaxSpeed ?? maxSpeed
                
                // 세션 요약용 브레이크다운은 최고 점수 런 기준으로 캐싱
                let bestEdgeBreakdown = bestEdgeMetric?.edgeBreakdown ?? ridingAnalysis.edgeBreakdown
                let bestFlowBreakdown = bestFlowMetric?.flowBreakdown ?? flowAnalysis.breakdown
                
                // 1. 데이터 저장 (RunMetrics 포함)
                let gForceSamples = ridingAnalysis.samples.map {
                    RunSession.GForceSample(t: $0.t, gAvg: $0.gAvg, gMax: $0.gMax)
                }
                
                let session = RunSession(
                    startTime: start,
                    endTime: end,
                    duration: duration,
                    distance: distance,
                    maxSpeed: sessionMaxSpeed,
                    avgSpeed: avgSpeed,
                    verticalDrop: verticalDrop,
                    runCount: runCount,
                    slopeName: currentSlope,
                    riddenSlopes: sessionSlopes,
                    locationName: detectedResortName ?? "HIGH1 RESORT",
                    countryCode: resolveCountryCode(from: routeCoordinates),
                    routeCoordinates: routeCoordinates,
                    routeSpeeds: routeSpeeds,
                    routeTimestamps: routeTimestamps,
                    routeAltitudes: routeAltitudes,
                    routeDistances: routeDistances,
                    routeStates: routeStates,
                    runStartIndices: runStartIndices,
                    timelineEvents: locationManager.timelineEvents,
                    edgeScore: bestEdgeScore,
                    flowScore: bestFlowScore,
                    maxGForce: maxG,
                    baroAvailable: locationManager.barometerAvailable,
                    baroVerticalDrop: locationManager.baroVerticalDropValue,
                    baroGain: locationManager.baroGainValue,
                    baroSampleCount: locationManager.baroSampleCountValue,
                    baroBaselineAltitude: locationManager.baroBaselineAltitudeValue,
                    baroDriftCorrection: locationManager.baroDriftCorrectionValue,
                    analysisSamples: ridingAnalysis.samples,
                    analysisEvents: flowAnalysis.events,
                    analysisSegments: flowAnalysis.segments,
                    gForceSamples: gForceSamples.isEmpty ? nil : gForceSamples,
                    flowBreakdown: bestFlowBreakdown,
                    edgeBreakdown: bestEdgeBreakdown
                )
                
                session.runMetrics = self.tempRunMetrics
                
                // SwiftData 저장 (에러 로그 남김)
                context.insert(session)
                do {
                    try context.save()
                    print("✅ RunSession 저장 완료: \(session.startTime)")
                    
                    // 바리오 로그 내보내기 (파일 저장)
                    _ = locationManager.exportBarometerLog(startTime: start, endTime: end)
                    
                    // 랭킹 업로드 판단을 위해 전체 세션 재계산
                    let descriptor = FetchDescriptor<RunSession>(sortBy: [SortDescriptor(\.startTime, order: .reverse)])
                    if let allSessions = try? context.fetch(descriptor) {
                        RankingService.shared.processRun(latestSession: session, sessions: allSessions)
                    }
                } catch {
                    print("❌ RunSession 저장 실패: \(error)")
                }
                
                // 2. 상태 초기화
                self.isRecording = false
                self.isPaused = false
                self.timer?.invalidate()
                self.timer = nil
                self.startTime = nil
                self.pauseTime = nil
                self.totalPausedDuration = 0
                self.tempRunMetrics = []
                self.currentRunMetrics = []
            }
        }
    }
    
    // MARK: - 리조트 감지 (세션 종료 시점)
    
    private func detectResortName(from routeCoordinates: [[Double]]) -> String? {
        let samples = sampleRouteCoordinates(routeCoordinates, maxSamples: 200)
        guard !samples.isEmpty else { return nil }
        
        // 1) 하이원: 슬로프 폴리곤 기반 판정 (정확도 우선)
        if samples.contains(where: { isInHigh1Slope($0) }) {
            return "하이원 리조트"
        }
        
        // 2) 기타 리조트: 리조트 중심 반경 기반 (슬로프 데이터에 맞춰 확장)
        let regions = ResortRegion.domesticResorts
        var hitCounts: [String: Int] = [:]
        var displayNameByKey: [String: String] = [:]
        for region in regions {
            displayNameByKey[region.key] = region.displayName
        }
        
        for coord in samples {
            let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            for region in regions where region.contains(location) {
                hitCounts[region.key, default: 0] += 1
            }
        }
        
        guard let best = hitCounts.max(by: { $0.value < $1.value }),
              best.value >= 3,
              let displayName = displayNameByKey[best.key] else {
            return nil
        }
        return displayName
    }
    
    private func sampleRouteCoordinates(_ routeCoordinates: [[Double]], maxSamples: Int) -> [CLLocationCoordinate2D] {
        guard !routeCoordinates.isEmpty else { return [] }
        let strideValue = max(1, routeCoordinates.count / maxSamples)
        var samples: [CLLocationCoordinate2D] = []
        samples.reserveCapacity(min(routeCoordinates.count, maxSamples))
        
        for index in stride(from: 0, to: routeCoordinates.count, by: strideValue) {
            let coord = routeCoordinates[index]
            guard coord.count >= 2 else { continue }
            samples.append(CLLocationCoordinate2D(latitude: coord[0], longitude: coord[1]))
        }
        return samples
    }
    
    private func isInHigh1Slope(_ coordinate: CLLocationCoordinate2D) -> Bool {
        // 하이원 슬로프 폴리곤 포함 여부 체크
        for slope in SlopeDatabase.shared.slopes {
            if slope.contains(coordinate) {
                return true
            }
        }
        return false
    }
    
    /// 경과 시간을 "MM:ss" 또는 "HH:mm:ss" 형식의 문자열로 반환
    func formattedElapsedTime() -> String {
        let hours = Int(elapsedTime) / 3600
        let minutes = (Int(elapsedTime) % 3600) / 60
        let seconds = Int(elapsedTime) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    // GPS 좌표 기반 국내(KR) 여부 판단
    private func resolveCountryCode(from routeCoordinates: [[Double]]) -> String {
        guard !routeCoordinates.isEmpty else { return "UNKNOWN" }
        
        for coord in routeCoordinates {
            guard coord.count >= 2 else { continue }
            let lat = coord[0]
            let lon = coord[1]
            if isDomesticCoordinate(lat: lat, lon: lon) {
                return "KR"
            }
        }
        return "UNKNOWN"
    }
    
    private func isDomesticCoordinate(lat: Double, lon: Double) -> Bool {
        // 한국 대략 바운딩 박스 (제주/독도 포함 여유 범위)
        return lat >= 33.0 && lat <= 39.0 && lon >= 124.5 && lon <= 132.0
    }
}
