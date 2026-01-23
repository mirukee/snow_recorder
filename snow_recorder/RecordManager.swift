import Foundation
import Combine
import SwiftData

/// 녹화 상태 및 타이머를 관리하는 매니저 클래스 (Singleton)
class RecordManager: ObservableObject {
    static let shared = RecordManager()
    
    @Published var isRecording: Bool = false       // 현재 녹화 중 여부
    @Published var isPaused: Bool = false          // 일시 정지 여부
    @Published var elapsedTime: TimeInterval = 0   // 경과 시간 (초)
    
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
    private func recordRunMetric(result: RidingSessionResult) {
        // LocationManager의 현재(직전) 런 정보 가져오기
        let locationManager = LocationManager.shared
        
        // 주의: Riding -> Resting 전환 후 결과가 오지만, 그 사이 사용자가 급격히 다시 Riding을 시작했을 수도 있음.
        // TimelineEvents에는 [Run1(Finished), Run2(Active)] 가 들어있을 수 있음.
        // 따라서 '마지막'이 아니라 '마지막으로 완료된(endTime != nil)' Riding 이벤트를 찾아야 함.
        
        guard let lastCompletedRidingEvent = locationManager.timelineEvents.reversed().first(where: { $0.type == .riding && $0.endTime != nil }),
              let endTime = lastCompletedRidingEvent.endTime else {
            // 아직 끝난 런이 없거나 매칭 실패
            return
        }
        
        let lastRidingEvent = lastCompletedRidingEvent
        
        // 중복 저장 방지 (같은 startTime의 런이 이미 있는지 확인)
        if tempRunMetrics.contains(where: { $0.startTime == lastRidingEvent.startTime }) {
            return
        }
        
        // Flow Score (현재 시점의 값)
        let flowScore = FlowScoreAnalyzer.shared.latestFlowScore
        
        let metric = RunSession.RunMetric(
            runNumber: locationManager.runCount, // 단순히 현재 카운트 사용 (정확한 매칭은 복잡할 수 있음)
            slopeName: lastRidingEvent.detail,
            startTime: lastRidingEvent.startTime,
            endTime: endTime,
            duration: lastRidingEvent.duration,
            maxSpeed: result.maxSpeed, // LocationManager.maxSpeed는 전체 세션 최대이므로, 이번 런의 maxSpeed가 필요함. (Analyzer에서 받아야 함) -> RidingSessionResult에 maxSpeed 추가 필요할지도? 일단 GForce만 있으므로... 
            // FIXME: RidingSessionResult에 maxSpeed가 없음. 일단 전체 avg, max 사용하거나 Analyzer 수정 필요.
            // 일단은 현재 구현된 Analyzer는 GForce, EdgeScore 만 줌.
            // 임시로 LocationManager의 lastRunMaxSpeed 같은게 있다면 좋겠지만 없음.
            // 여기서는 0.0 으로 두거나 추후 보완.
            avgSpeed: result.averageSpeed, 
            edgeScore: result.edgeScore,
            flowScore: flowScore ?? 0,
            maxGForce: result.maxGForce
        )
        
        tempRunMetrics.append(metric)
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
                // (생략: 복잡도 줄이기 위해 일단 마지막 런 자동 감지 로직에 의존)
                
                // LocationManager에서 메트릭 수집
                let locationManager = LocationManager.shared
                let distance = locationManager.totalDistance
                let maxSpeed = locationManager.maxSpeed
                let avgSpeed = locationManager.avgSpeed
                let verticalDrop = locationManager.verticalDrop
                let runCount = locationManager.runCount
                let currentSlope = locationManager.currentSlope?.name
                let sessionSlopes = locationManager.sessionSlopeCounts
                let routeCoordinates = locationManager.routeCoordinates
                let routeSpeeds = locationManager.routeSpeeds
                let runStartIndices = locationManager.runStartIndices
                
                // Best Score 계산
                let bestEdgeScore = self.tempRunMetrics.map { $0.edgeScore }.max() ?? (ridingResult?.edgeScore ?? 0)
                let bestFlowScore = self.tempRunMetrics.map { $0.flowScore }.max() ?? flowScore
                let maxG = self.tempRunMetrics.map { $0.maxGForce }.max() ?? (ridingResult?.maxGForce ?? 0.0)
                
                // 1. 데이터 저장 (RunMetrics 포함)
                let session = RunSession(
                    startTime: start,
                    endTime: end,
                    duration: duration,
                    distance: distance,
                    maxSpeed: maxSpeed,
                    avgSpeed: avgSpeed,
                    verticalDrop: verticalDrop,
                    runCount: runCount,
                    slopeName: currentSlope,
                    riddenSlopes: sessionSlopes,
                    locationName: "HIGH1 RESORT",
                    routeCoordinates: routeCoordinates,
                    routeSpeeds: routeSpeeds,
                    runStartIndices: runStartIndices,
                    timelineEvents: locationManager.timelineEvents,
                    edgeScore: bestEdgeScore,
                    flowScore: bestFlowScore,
                    maxGForce: maxG
                )
                
                session.runMetrics = self.tempRunMetrics
                
                context.insert(session)
                try? context.save()
                
                // 3. 랭킹 시스템 연동 (자동 업로드)
                RankingService.shared.processRun(session: session)
                
                // 2. 상태 초기화
                self.isRecording = false
                self.isPaused = false
                self.timer?.invalidate()
                self.timer = nil
                self.startTime = nil
                self.pauseTime = nil
                self.totalPausedDuration = 0
                self.tempRunMetrics = []
            }
        }
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
}
