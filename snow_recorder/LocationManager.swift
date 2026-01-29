import Foundation
import CoreLocation
import CoreMotion
import Combine

/// 위치 정보 및 속도를 관리하는 매니저 클래스 (Singleton)
/// 상태 기반 측정 시스템으로 배터리 효율 최적화
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    
    private let locationManager = CLLocationManager()
    private let altimeter = CMAltimeter()
    
    // MARK: - Published Properties (실시간 데이터)
    @Published var speed: Double = 0.0              // 현재 속도 (km/h)
    @Published var altitude: Double = 0.0           // 현재 고도 (m)
    @Published var barometerAvailable: Bool = false // 기압계 사용 가능 여부
    @Published var totalDistance: Double = 0.0      // 누적 활강 거리 (m) - RIDING 상태에서만
    @Published var maxSpeed: Double = 0.0           // 최고 속도 (km/h)
    @Published var location: CLLocation?            // 현재 위치 좌표
    @Published var slopeAngle: Double = 0.0         // 현재 경사각 (°)
    
    // MARK: - 추가된 메트릭
    @Published var verticalDrop: Double = 0.0       // 총 하강 고도 (m) - RIDING 상태에서만
    @Published var currentSlope: Slope?             // 현재 인식된 슬로프
    @Published var currentState: RidingState = .resting  // 현재 활동 상태
    @Published var avgSpeed: Double = 0.0           // 평균 속도 (km/h)
    @Published var runCount: Int = 0                // 런 횟수
    @Published var sessionSlopeCounts: [String: Int] = [:] // 세션 동안 탄 슬로프별 횟수
    @Published var routeCoordinates: [[Double]] = [] // GPS 경로 좌표 [[lat, lon], ...]
    @Published var routeSpeeds: [Double] = [] // GPS 경로별 속도 (km/h)
    @Published var routeTimestamps: [TimeInterval] = [] // GPS 경로별 타임스탬프 (UNIX 초)
    @Published var routeAltitudes: [Double] = [] // GPS 경로별 고도 (m)
    @Published var routeDistances: [Double] = [] // GPS 경로별 누적 거리 (m)
    @Published var routeStates: [RunSession.TimelineEvent.EventType] = [] // GPS 샘플별 상태
    @Published var routeSpeedAccuracies: [Double] = [] // GPS 경로별 속도 정확도 (m/s)
    @Published var runStartIndices: [Int] = [0] // 각 런 시작 인덱스
    @Published var timelineEvents: [RunSession.TimelineEvent] = [] // 타임라인 이벤트 목록
    private(set) var lastRunWasAccepted: Bool = true // 최근 런이 유효로 확정되었는지 여부
    
    // MARK: - Private Properties
    private var lastLocation: CLLocation?
    private var isTracking = false
    private var speedSamples: [Double] = []         // avgSpeed 계산용 속도 샘플
    private var stateChangeTime: Date?              // 상태 전환 시간 (debounce용)
    private var lastSlopeCheckLocation: CLLocation? // 슬로프 체크 최적화용
    private var visitedSlopeCounts: [String: Int] = [:] // 현재 런에서 방문한 슬로프별 샘플 수 (Dwell Time)
    private var visitedSlopeStartHits: Set<String> = [] // 현재 런에서 시작점(Top)을 통과한 슬로프 이름
    private var visitedSlopeFinishHits: Set<String> = [] // 현재 런에서 종료점(Bottom)을 통과한 슬로프 이름
    private var altitudeHistory: [Double] = []          // 상태 판정 안정화를 위한 고도 기록 (최근 5~10초)
    private var outOfSlopeStartTime: Date?              // 슬로프 이탈 시점 기록
    private var currentTimelineEventStart: Date?        // 현재 이벤트 시작 시간
    private var liftStationaryStartTime: Date?          // 리프트 정지/대기 시간 측정용
    private var liftAccuracyBoostUntil: Date?           // 리프트 하차 감지 시 GPS 정확도 임시 상승 종료 시각
    private var lastLiftAccuracyBoostTime: Date?        // 리프트 정확도 상승 쿨다운 체크용
    private var currentRunDistance: Double = 0.0        // 현재 런 거리 (m)
    private var currentRunVerticalDrop: Double = 0.0    // 현재 런 하강 고도 (m)
    private var currentRunStartTime: Date?              // 현재 런 시작 시간
    private var completedRunDistances: [Double] = []    // 완료된 런 거리 기록
    private var completedRunVerticalDrops: [Double] = [] // 완료된 런 하강 고도 기록
    private var completedRunEndIndices: [Int] = []     // 완료된 런 종료 인덱스 (속도 그래프용)
    private var completedRunStartTimes: [Date] = []     // 완료된 런 시작 시간
    private var completedRunEndTimes: [Date] = []       // 완료된 런 종료 시간
    private var completedRunSlopeNames: [String] = []   // 완료된 런 슬로프 이름
    private var sessionStartLocation: CLLocation?
    private var sessionStartSmoothedAltitude: Double?
    private var recentLocations: [CLLocation] = []
    private var recentBaroSamples: [(time: Date, altitude: Double)] = []
    private var recentGPSAltitudeSamples: [(time: Date, altitude: Double)] = []
    private var pendingRidingStartTime: Date?
    private var pendingRidingStartIndex: Int?
    private var pendingRidingLocations: [CLLocation] = []
    private var pendingRestStartTime: Date?
    private var pendingRestStartIndex: Int?
    private var pendingRestFinalizeTime: Date?
    private var pendingRestFinalizeIndex: Int?
    private var onLiftStartCandidates: Set<String> = []
    private var pendingRestBoostUntil: Date?
    private var lastPendingRestBoostTime: Date?
    private var baroFallbackTimer: DispatchSourceTimer?
    private var baroFallbackLiftTicks: Int = 0
    
    // MARK: - Barometer 로깅 (Phase 0 설계)
    private struct BarometerLogEntry {
        let timestamp: Date
        let baroAltitude: Double?
        let verticalSpeed: Double?
        let speed: Double?
        let state: RidingState?
        let recentGain: Double?
        let recentDrop: Double?
        let note: String?
    }
    
    private var barometerLogs: [BarometerLogEntry] = []
    private let barometerLogLimit: Int = 2000
    
    // MARK: - Barometer 상태 (Phase 1 연결)
    private var sessionBarometerEnabled: Bool = false
    private var baroBaselineAltitude: Double?
    private var baroBaselineSamples: [Double] = []
    private let baroBaselineSampleWindow: Int = 5 // 초기 베이스라인 샘플 수
    private var baroBaselineSetTime: Date?
    private var lastBaroAltitude: Double?
    private var previousBaroAltitude: Double?
    private var lastBaroTimestamp: Date?
    private var baroRawHistory: [Double] = []
    private var baroAltitudeHistory: [Double] = []
    private var baroVerticalSpeed: Double = 0.0
    private var baroGainTotal: Double = 0.0
    private var baroDropTotal: Double = 0.0
    private var baroSampleCount: Int = 0
    private var baroDriftCorrection: Double = 0.0
    private var baroDriftApplied: Bool = false
    private var baroDriftOffset: Double = 0.0
    private var baroOutlierCount: Int = 0
    private var baroDriftUpdateCount: Int = 0
    private let baroMinVerticalDelta: Double = 0.3 // 바리오 노이즈 필터 (m)
    private let baroOutlierThreshold: Double = 4.0 // 급격한 점프 제거 (m)
    private let baroSmoothingWindow: Int = 10 // 5~10초 이동 평균 (샘플 기준)
    private let baroDriftThreshold: Double = 3.0 // 드리프트 보정 최소 임계값 (m)
    private let baroDriftUpdateThreshold: Double = 1.5 // 휴식 구간 보정 최소 오차 (m)
    private let baroDriftUpdateGain: Double = 0.02 // 휴식 구간 보정 비율
    
    // MARK: - 리프트/라이딩 구분 필터
    private let recentLocationWindow: TimeInterval = 20.0 // 최근 위치 보관 시간(초)
    private let minLinearityDistance: Double = 60.0 // 직진성 계산 최소 이동 거리(m)
    private let liftLinearityThreshold: Double = 0.95 // 직진성 임계값(리프트 판정)
    private let liftCourseStdThreshold: Double = 5.0 // 방향 분산 임계값(도)
    private let minCourseSpeed: Double = 1.5 // 방향 계산 최소 속도(m/s)
    private let liftDescentWindow: TimeInterval = 20.0 // 리프트 하차 감지용 누적 하강 윈도우(초)
    private let liftDescentThreshold: Double = 5.0 // 리프트 하차 감지 누적 하강 임계값(m)
    private let liftAccuracyBoostDuration: TimeInterval = 20.0 // 정확도 상승 유지 시간(초)
    private let liftAccuracyBoostCooldown: TimeInterval = 20.0 // 정확도 상승 쿨다운(초)
    private let ridingRestSpeedThreshold: Double = 6.0 // 라이딩→휴식 전환용 속도 상한(km/h)
    private let ridingRestDropThreshold: Double = 10.0 // 라이딩→휴식 전환용 하강량 상한(m)
    private let altitudeTrendWindow: TimeInterval = 10.0 // 상승/하강 판정 윈도우(초)
    private let altitudeTrendMinSpan: TimeInterval = 6.0 // 판정 최소 시간 span(초)
    private let pendingRidingDuration: TimeInterval = 5.0 // 라이딩 확정 대기 시간(초)
    private let pendingRidingMinAvgSpeed: Double = 5.0 // 확정 조건: 평균 속도(km/h)
    private let pendingRidingMinDistance: Double = 5.0 // 확정 조건: 수평 이동(m)
    private let pendingRidingMinDrop: Double = 3.0 // 확정 조건: 누적 하강(m)
    private let pendingRestResumeSpeedThreshold: Double = 10.0 // 보류 해제 조건: 재개 속도(km/h)
    private let pendingRestResumeDropThreshold: Double = 3.0 // 보류 해제 조건: 순하강(m)
    private let pendingRestTimeout: TimeInterval = 90.0 // 보류 해제 타임아웃(초)
    private let pendingRestDescentWindow: TimeInterval = 5.0 // Pending Rest 하강 감지 윈도우(초)
    private let pendingRestDescentThreshold: Double = 2.0 // Pending Rest 하강 감지 임계값(m)
    private let pendingRestBoostDuration: TimeInterval = 10.0 // Pending Rest 정확도 상승 유지 시간(초)
    private let pendingRestBoostCooldown: TimeInterval = 10.0 // Pending Rest 정확도 상승 쿨다운(초)
    private let baroFallbackTickInterval: TimeInterval = 1.0 // 바리오 보조 판정 주기(초)
    private let baroFallbackMinGpsGap: TimeInterval = 10.0 // GPS 업데이트 지연 임계값(초)
    private let baroFallbackRequiredTicks: Int = 3 // 리프트 전환 확정 연속 틱 수
    private let baroFallbackRestGainThreshold: Double = 5.0 // Resting→OnLift 보조 판정 상승 임계값(m)
    private let baroFallbackRidingGainThreshold: Double = 7.0 // Riding→OnLift 보조 판정 상승 임계값(m)
    
    // MARK: - GPS 고도 스무딩
    private var gpsRawAltitudeHistory: [Double] = []
    private var gpsSmoothedAltitudeHistory: [Double] = []
    private var lastSmoothedGPSAltitude: Double?
    private var previousSmoothedGPSAltitude: Double?
    private let gpsOutlierThreshold: Double = 6.0 // GPS 고도 점프 제거 (m)
    private let gpsSmoothingWindow: Int = 8 // GPS 이동 평균 샘플 수
    private let gpsDriftDistanceThreshold: Double = 100.0 // 시작/종료 거리 임계값 (m)
    private let gpsDriftAltitudeThreshold: Double = 5.0 // 시작/종료 고도 차 임계값 (m)
    private let gpsDriftSmoothingWindow: Int = 5 // 드리프트 보정용 GPS 추가 스무딩
    private var gpsAltitudeOutlierCount: Int = 0
    
    // MARK: - 상태 전환 임계값 (튜닝 가능)
    private let ridingSpeedThreshold: Double = 5.0      // 활강 판정 최소 속도 (km/h)
    private let stateChangeDebounce: TimeInterval = 5.0 // 상태 전환 debounce (초)
    private let slopeCheckDistance: Double = 50.0       // 슬로프 체크 최소 이동 거리 (m)
    private let pointHitRadius: Double = 50.0           // 시작/종료점 통과 판정 반경 (m)
    private let minVerticalDrop: Double = 1.0           // 최소 하강 고도 (GPS 노이즈 필터)
    private let runSpeedAccuracyThreshold: Double = 2.0 // 런 그래프/메트릭용 속도 정확도 상한 (m/s)
    private let routeTimeSampleInterval: TimeInterval = 30.0 // 경로 포인트 시간 기반 최소 샘플링 간격 (초)
    private let restToLiftMinSpeedKmH: Double = 4.0     // 휴식→리프트 전환 최소 속도(느슨한 게이트)
    private let restToLiftMinHorizontalDistance: Double = 8.0 // 휴식→리프트 전환 최소 수평 이동(m)
    private let shortOnLiftMergeThreshold: TimeInterval = 30.0 // 짧은 리프트 이벤트 병합 기준(초)

    /// UI 표기용 상태 (Pending Rest는 RESTING으로 표시)
    var displayState: RidingState {
        if currentState == .riding, pendingRestStartTime != nil {
            return .resting
        }
        return currentState
    }
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    /// 위치 매니저 초기 설정
    private func setupLocationManager() {
        locationManager.delegate = self
        // 초기 정확도: 중간 정확도(Resting 수준)
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        // 백그라운드 위치 업데이트 허용 (스키 탈 때 주머니에 넣을 수 있음)
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false // 자동 일시정지 방지
        
        // 기압계 지원 여부 체크 (Phase 0)
        barometerAvailable = CMAltimeter.isRelativeAltitudeAvailable()
        appendBarometerLog(note: "기압계 지원 여부: \(barometerAvailable)")
    }
    
    /// 위치 권한 요청
    func requestPermission() {
        locationManager.requestAlwaysAuthorization()
    }
    
    /// 트래킹 시작 (새로운 세션)
    func startTracking() {
        isTracking = true
        resetMetrics()
        currentState = .resting
        currentTimelineEventStart = Date() // 첫 이벤트 시작 시간 기록
        updateLocationAccuracy(for: .resting)
        locationManager.startUpdatingLocation()
        
        // 세션 시작 시점 기준으로 기압계 지원 여부 재확인
        barometerAvailable = CMAltimeter.isRelativeAltitudeAvailable()
        sessionBarometerEnabled = FeatureFlags.barometerEnabled
        appendBarometerLog(note: "세션 시작 - barometerAvailable: \(barometerAvailable), flag: \(FeatureFlags.barometerEnabled)")
        
        if isUsingBarometer {
            startBarometerUpdates()
            startBarometerFallbackTimer()
        } else {
            stopBarometerUpdates()
            stopBarometerFallbackTimer()
        }
    }
    
    /// 트래킹 일시 정지 (데이터 유지)
    func pauseTracking() {
        isTracking = false
        locationManager.stopUpdatingLocation()
        stopBarometerFallbackTimer()
    }
    
    /// 트래킹 재개 (데이터 유지)
    func resumeTracking() {
        isTracking = true
        locationManager.startUpdatingLocation()
        if isUsingBarometer {
            startBarometerFallbackTimer()
        }
    }
    
    /// 트래킹 종료
    func stopTracking() {
        isTracking = false
        locationManager.stopUpdatingLocation()
        speed = 0.0
        stopBarometerUpdates()
        stopBarometerFallbackTimer()
        
        // 마지막 런이 진행 중이었다면 카운트 및 슬로프 확정
        if currentRunStartTime != nil {
            finalizeCurrentRun(at: Date())
        }
        
        // 세션 종료 시 드리프트 보정
        applyBarometerDriftCorrectionIfNeeded()
        
        // 평균 속도 최종 계산
        calculateAvgSpeed()
        
        // 마지막 이벤트 기록
        if let start = currentTimelineEventStart {
            let now = Date()
            let timelineCurrentState = timelineState(currentState)
            var detail = timelineCurrentState.displayLabel
            if timelineCurrentState == .riding {
               detail = currentSlope?.name ?? "알 수 없는 슬로프"
            }
            let event = RunSession.TimelineEvent(type: mapStateToEventType(timelineCurrentState), startTime: start, endTime: now, detail: detail)
            timelineEvents.append(event)
        }
        currentTimelineEventStart = nil
    }

    // MARK: - Run Metrics Accessors
    
    var baroVerticalDropValue: Double? {
        isUsingBarometer ? baroDropTotal : nil
    }
    
    var baroGainValue: Double? {
        isUsingBarometer ? baroGainTotal : nil
    }
    
    var baroSampleCountValue: Int? {
        isUsingBarometer ? baroSampleCount : nil
    }
    
    var baroBaselineAltitudeValue: Double? {
        isUsingBarometer ? baroBaselineAltitude : nil
    }
    
    var baroDriftCorrectionValue: Double? {
        isUsingBarometer ? baroDriftCorrection : nil
    }

    func completedRunDistance(for runNumber: Int) -> Double {
        let index = runNumber - 1
        guard index >= 0, index < completedRunDistances.count else { return 0.0 }
        return completedRunDistances[index]
    }

    func completedRunVerticalDrop(for runNumber: Int) -> Double {
        let index = runNumber - 1
        guard index >= 0, index < completedRunVerticalDrops.count else { return 0.0 }
        return completedRunVerticalDrops[index]
    }
    
    func completedRunStartTime(for runNumber: Int) -> Date? {
        let index = runNumber - 1
        guard index >= 0, index < completedRunStartTimes.count else { return nil }
        return completedRunStartTimes[index]
    }
    
    func completedRunEndTime(for runNumber: Int) -> Date? {
        let index = runNumber - 1
        guard index >= 0, index < completedRunEndTimes.count else { return nil }
        return completedRunEndTimes[index]
    }
    
    func completedRunSlopeName(for runNumber: Int) -> String? {
        let index = runNumber - 1
        guard index >= 0, index < completedRunSlopeNames.count else { return nil }
        return completedRunSlopeNames[index]
    }
    
    var completedRunCount: Int {
        completedRunDistances.count
    }

    func completedRunSpeedSeries(for runNumber: Int) -> [Double] {
        guard !routeSpeeds.isEmpty else { return [] }
        let index = runNumber - 1
        guard index >= 0 else { return [] }

        // runStartIndices는 초기값 0을 포함하므로, 실제 런 시작 인덱스는 index+1이 우선
        let startIndex: Int
        if index + 1 < runStartIndices.count {
            startIndex = runStartIndices[index + 1]
        } else if index < runStartIndices.count {
            startIndex = runStartIndices[index]
        } else {
            startIndex = 0
        }
        let endIndex = index < completedRunEndIndices.count ? completedRunEndIndices[index] : routeSpeeds.count
        
        let safeStart = max(0, min(startIndex, routeSpeeds.count))
        let safeEnd = max(safeStart, min(endIndex, routeSpeeds.count))
        guard safeEnd > safeStart else { return [] }
        
        let speedsSlice = Array(routeSpeeds[safeStart..<safeEnd])
        guard routeSpeedAccuracies.count >= safeEnd else {
            return speedsSlice
        }
        let accuracySlice = Array(routeSpeedAccuracies[safeStart..<safeEnd])
        let filtered: [Double] = zip(speedsSlice, accuracySlice).compactMap { pair -> Double? in
            let (speed, accuracy) = pair
            guard accuracy >= 0, accuracy <= runSpeedAccuracyThreshold else { return nil }
            return speed
        }
        return filtered
    }
    
    /// 메트릭 초기화
    private func resetMetrics() {
        totalDistance = 0.0
        maxSpeed = 0.0
        verticalDrop = 0.0
        avgSpeed = 0.0
        runCount = 0
        speedSamples = []
        lastLocation = nil
        lastSlopeCheckLocation = nil
        currentSlope = nil
        stateChangeTime = nil
        visitedSlopeCounts.removeAll()
        visitedSlopeStartHits.removeAll()
        visitedSlopeFinishHits.removeAll()
        altitudeHistory.removeAll()
        outOfSlopeStartTime = nil
        sessionSlopeCounts.removeAll()
        routeCoordinates.removeAll()
        routeSpeeds.removeAll()
        routeTimestamps.removeAll()
        routeAltitudes.removeAll()
        routeDistances.removeAll()
        routeStates.removeAll()
        routeSpeedAccuracies.removeAll()
        runStartIndices = [0]
        timelineEvents.removeAll()
        currentTimelineEventStart = nil
        liftAccuracyBoostUntil = nil
        lastLiftAccuracyBoostTime = nil
        currentRunDistance = 0.0
        currentRunVerticalDrop = 0.0
        currentRunStartTime = nil
        completedRunDistances.removeAll()
        completedRunVerticalDrops.removeAll()
        completedRunEndIndices.removeAll()
        completedRunStartTimes.removeAll()
        completedRunEndTimes.removeAll()
        completedRunSlopeNames.removeAll()
        sessionStartLocation = nil
        sessionStartSmoothedAltitude = nil
        recentLocations.removeAll()
        recentBaroSamples.removeAll()
        recentGPSAltitudeSamples.removeAll()
        resetPendingRiding()
        resetPendingRest()
        resetBarometerLogs()
        resetBarometerMetrics()
        resetGPSAltitudeSmoothing()
    }

    // MARK: - Barometer 로깅 유틸
    
    private func appendBarometerLog(
        timestamp: Date = Date(),
        baroAltitude: Double? = nil,
        verticalSpeed: Double? = nil,
        speed: Double? = nil,
        state: RidingState? = nil,
        recentGain: Double? = nil,
        recentDrop: Double? = nil,
        note: String? = nil
    ) {
        let entry = BarometerLogEntry(
            timestamp: timestamp,
            baroAltitude: baroAltitude,
            verticalSpeed: verticalSpeed,
            speed: speed,
            state: state,
            recentGain: recentGain,
            recentDrop: recentDrop,
            note: note
        )
        barometerLogs.append(entry)
        
        // 메모리 보호용 상한 유지
        if barometerLogs.count > barometerLogLimit {
            barometerLogs.removeFirst(barometerLogs.count - barometerLogLimit)
        }
    }
    
    private func resetBarometerLogs() {
        barometerLogs.removeAll()
    }
    
    private func resetBarometerMetrics() {
        sessionBarometerEnabled = false
        baroBaselineAltitude = nil
        baroBaselineSamples.removeAll()
        baroBaselineSetTime = nil
        lastBaroAltitude = nil
        previousBaroAltitude = nil
        lastBaroTimestamp = nil
        baroRawHistory.removeAll()
        baroAltitudeHistory.removeAll()
        baroVerticalSpeed = 0.0
        baroGainTotal = 0.0
        baroDropTotal = 0.0
        baroSampleCount = 0
        baroDriftCorrection = 0.0
        baroDriftApplied = false
        baroDriftOffset = 0.0
        baroOutlierCount = 0
        baroDriftUpdateCount = 0
    }

    private func resetGPSAltitudeSmoothing() {
        gpsRawAltitudeHistory.removeAll()
        gpsSmoothedAltitudeHistory.removeAll()
        lastSmoothedGPSAltitude = nil
        previousSmoothedGPSAltitude = nil
        gpsAltitudeOutlierCount = 0
    }
    
    private var isUsingBarometer: Bool {
        sessionBarometerEnabled && barometerAvailable
    }
    
    private func startBarometerUpdates() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else {
            appendBarometerLog(note: "기압계 미지원: 업데이트 시작 실패")
            return
        }
        
        altimeter.startRelativeAltitudeUpdates(to: OperationQueue.main) { [weak self] data, error in
            guard let self = self else { return }
            
            if let error = error {
                self.appendBarometerLog(note: "바리오 업데이트 오류: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else { return }
            self.handleBarometerUpdate(data)
        }
        appendBarometerLog(note: "바리오 업데이트 시작")
    }
    
    private func stopBarometerUpdates() {
        altimeter.stopRelativeAltitudeUpdates()
        appendBarometerLog(note: "바리오 업데이트 중지")
    }

    // MARK: - 바리오 보조 상태 전환 타이머
    private func startBarometerFallbackTimer() {
        guard baroFallbackTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + baroFallbackTickInterval, repeating: baroFallbackTickInterval)
        timer.setEventHandler { [weak self] in
            self?.handleBarometerFallbackTick()
        }
        timer.resume()
        baroFallbackTimer = timer
    }

    private func stopBarometerFallbackTimer() {
        baroFallbackTimer?.cancel()
        baroFallbackTimer = nil
        baroFallbackLiftTicks = 0
    }

    private func handleBarometerFallbackTick() {
        guard isTracking, isUsingBarometer else {
            baroFallbackLiftTicks = 0
            return
        }
        guard let lastLocation else {
            baroFallbackLiftTicks = 0
            return
        }
        let now = Date()
        let gap = now.timeIntervalSince(lastLocation.timestamp)
        guard gap >= baroFallbackMinGpsGap else {
            baroFallbackLiftTicks = 0
            return
        }
        guard let trend = recentAltitudeNetChange(
            window: altitudeTrendWindow,
            minSpan: altitudeTrendMinSpan,
            useBarometer: true
        ) else {
            baroFallbackLiftTicks = 0
            return
        }
        
        let recentGain = trend.gain
        let shouldLift: Bool
        switch currentState {
        case .resting:
            shouldLift = recentGain > baroFallbackRestGainThreshold
        case .riding:
            shouldLift = recentGain > baroFallbackRidingGainThreshold
        default:
            shouldLift = false
        }
        
        if shouldLift {
            baroFallbackLiftTicks += 1
        } else {
            baroFallbackLiftTicks = 0
        }
        
        guard baroFallbackLiftTicks >= baroFallbackRequiredTicks else { return }
        baroFallbackLiftTicks = 0
        
        guard currentState == .riding || currentState == .resting else { return }
        
        print("🪂 바리오 보조 전환: GPS 지연 \(String(format: "%.1f", gap))s, gain=\(String(format: "%.2f", recentGain))m")
        appendBarometerLog(note: "바리오 보조 전환: GPS 지연 \(String(format: "%.1f", gap))s, gain=\(String(format: "%.2f", recentGain))m")
        handleStateChange(from: currentState, to: .onLift, currentLocation: lastLocation)
        currentState = .onLift
    }
    
    private func handleBarometerUpdate(_ data: CMAltitudeData) {
        let now = Date()
        let rawAltitude = data.relativeAltitude.doubleValue
        
        if baroBaselineAltitude == nil {
            // 초기 N샘플 기준으로 베이스라인 설정 (노이즈 완화)
            baroBaselineSamples.append(rawAltitude)
            if baroBaselineSamples.count < baroBaselineSampleWindow {
                return
            }
            let sorted = baroBaselineSamples.sorted()
            let mid = sorted.count / 2
            let baseline = sorted.count % 2 == 0
                ? (sorted[mid - 1] + sorted[mid]) / 2.0
                : sorted[mid]
            baroBaselineAltitude = baseline
            baroBaselineSetTime = Date()
            baroBaselineSamples.removeAll()
            baroRawHistory.removeAll()
            baroAltitudeHistory.removeAll()
            previousBaroAltitude = nil
            lastBaroAltitude = nil
            lastBaroTimestamp = nil
            baroSampleCount = 0
            appendBarometerLog(note: "바리오 베이스라인 설정(중앙값, N=\(baroBaselineSampleWindow))")
            return
        }
        let baseline = baroBaselineAltitude ?? rawAltitude
        let relativeAltitude = rawAltitude - baseline - baroDriftOffset
        
        // Outlier 제거
        if let lastRaw = baroRawHistory.last, abs(relativeAltitude - lastRaw) > baroOutlierThreshold {
            baroOutlierCount += 1
            appendBarometerLog(note: "바리오 아웃라이어 제거: Δ\(String(format: "%.2f", abs(relativeAltitude - lastRaw)))m")
            return
        }
        
        // 이동 평균 스무딩
        baroRawHistory.append(relativeAltitude)
        if baroRawHistory.count > baroSmoothingWindow {
            baroRawHistory.removeFirst(baroRawHistory.count - baroSmoothingWindow)
        }
        let smoothedAltitude = baroRawHistory.reduce(0, +) / Double(max(1, baroRawHistory.count))
        
        previousBaroAltitude = lastBaroAltitude
        lastBaroAltitude = smoothedAltitude
        baroSampleCount += 1
        
        baroAltitudeHistory.append(smoothedAltitude)
        if baroAltitudeHistory.count > 12 {
            baroAltitudeHistory.removeFirst()
        }
        
        recentBaroSamples.append((time: now, altitude: smoothedAltitude))
        let baroCutoff = now.addingTimeInterval(-recentLocationWindow)
        recentBaroSamples.removeAll { $0.time < baroCutoff }
        
        if let lastTime = lastBaroTimestamp, let prev = previousBaroAltitude {
            let dt = now.timeIntervalSince(lastTime)
            if dt > 0 {
                baroVerticalSpeed = (smoothedAltitude - prev) / dt
            }
        }
        lastBaroTimestamp = now
        
        let delta = (previousBaroAltitude ?? smoothedAltitude) - smoothedAltitude // 양수 = 하강
        if delta > baroMinVerticalDelta {
            baroDropTotal += delta
            if isTracking && currentState == .riding {
                verticalDrop += delta
                currentRunVerticalDrop += delta
            }
        } else if delta < -baroMinVerticalDelta {
            baroGainTotal += -delta
        }
        
        let recentGain = max(0, (baroAltitudeHistory.last ?? 0) - (baroAltitudeHistory.first ?? 0))
        let recentDrop = max(0, (baroAltitudeHistory.first ?? 0) - (baroAltitudeHistory.last ?? 0))
        appendBarometerLog(
            baroAltitude: smoothedAltitude,
            verticalSpeed: baroVerticalSpeed,
            speed: speed,
            state: currentState,
            recentGain: recentGain,
            recentDrop: recentDrop
        )
        
        handleLiftAccuracyBoostIfNeeded(now: now)
        handlePendingRestAccuracyBoostIfNeeded(now: now)
    }

    private func updateGPSAltitudeSmoothing(with location: CLLocation) {
        let rawAltitude = location.altitude
        if let lastRaw = gpsRawAltitudeHistory.last, abs(rawAltitude - lastRaw) > gpsOutlierThreshold {
            gpsAltitudeOutlierCount += 1
            appendBarometerLog(note: "GPS 고도 아웃라이어 제거: Δ\(String(format: "%.2f", abs(rawAltitude - lastRaw)))m")
            return
        }
        
        gpsRawAltitudeHistory.append(rawAltitude)
        if gpsRawAltitudeHistory.count > gpsSmoothingWindow {
            gpsRawAltitudeHistory.removeFirst(gpsRawAltitudeHistory.count - gpsSmoothingWindow)
        }
        
        let smoothed = gpsRawAltitudeHistory.reduce(0, +) / Double(max(1, gpsRawAltitudeHistory.count))
        previousSmoothedGPSAltitude = lastSmoothedGPSAltitude
        lastSmoothedGPSAltitude = smoothed
        
        gpsSmoothedAltitudeHistory.append(smoothed)
        if gpsSmoothedAltitudeHistory.count > 12 {
            gpsSmoothedAltitudeHistory.removeFirst()
        }
        
        altitudeHistory = gpsSmoothedAltitudeHistory
        
        recentGPSAltitudeSamples.append((time: location.timestamp, altitude: smoothed))
        let gpsCutoff = location.timestamp.addingTimeInterval(-recentLocationWindow)
        recentGPSAltitudeSamples.removeAll { $0.time < gpsCutoff }
    }

    private func routeAltitudeValue(for location: CLLocation) -> Double {
        if isUsingBarometer, let baroAltitude = lastBaroAltitude {
            let baseAltitude = sessionStartSmoothedAltitude ?? lastSmoothedGPSAltitude ?? location.altitude
            return baseAltitude + baroAltitude
        }

        let smoothed = lastSmoothedGPSAltitude ?? location.altitude
        let raw = location.altitude
        if abs(raw - smoothed) <= gpsOutlierThreshold {
            return raw
        }
        return smoothed
    }
    
    private func updateRecentLocations(with location: CLLocation) {
        recentLocations.append(location)
        let cutoff = location.timestamp.addingTimeInterval(-recentLocationWindow)
        recentLocations.removeAll { $0.timestamp < cutoff }
    }
    
    private func recentBaroCumulativeDrop(since cutoff: Date) -> Double? {
        let samples = recentBaroSamples.filter { $0.time >= cutoff }
        guard samples.count >= 2 else { return nil }
        var drop = 0.0
        for i in 1..<samples.count {
            let delta = samples[i - 1].altitude - samples[i].altitude
            if delta > baroMinVerticalDelta {
                drop += delta
            }
        }
        return drop
    }

    private func recentAltitudeNetChange(
        window: TimeInterval,
        minSpan: TimeInterval,
        useBarometer: Bool
    ) -> (gain: Double, drop: Double)? {
        let samples = useBarometer ? recentBaroSamples : recentGPSAltitudeSamples
        guard let last = samples.last else { return nil }
        let cutoff = last.time.addingTimeInterval(-window)
        let windowSamples = samples.filter { $0.time >= cutoff }
        guard windowSamples.count >= 2 else { return nil }
        guard let first = windowSamples.first, let lastSample = windowSamples.last else { return nil }
        let span = lastSample.time.timeIntervalSince(first.time)
        guard span >= minSpan else { return nil }
        let gain = max(0, lastSample.altitude - first.altitude)
        let drop = max(0, first.altitude - lastSample.altitude)
        return (gain, drop)
    }
    
    private func recentBaroCumulativeDrop(within window: TimeInterval, now: Date) -> Double? {
        let cutoff = now.addingTimeInterval(-window)
        return recentBaroCumulativeDrop(since: cutoff)
    }
    
    private func handleLiftAccuracyBoostIfNeeded(now: Date) {
        guard isTracking, currentState == .onLift, isUsingBarometer else { return }
        
        if let until = liftAccuracyBoostUntil, now >= until {
            liftAccuracyBoostUntil = nil
        }
        
        if let lastBoost = lastLiftAccuracyBoostTime,
           now.timeIntervalSince(lastBoost) < liftAccuracyBoostCooldown {
            updateLocationAccuracy(for: .onLift)
            return
        }
        
        let cutoff = now.addingTimeInterval(-liftDescentWindow)
        if let drop = recentBaroCumulativeDrop(since: cutoff), drop >= liftDescentThreshold {
            liftAccuracyBoostUntil = now.addingTimeInterval(liftAccuracyBoostDuration)
            lastLiftAccuracyBoostTime = now
            appendBarometerLog(note: "리프트 하강 감지: GPS 정확도 임시 상승 (drop=\(String(format: "%.2f", drop))m)")
        }
        
        updateLocationAccuracy(for: .onLift)
    }
    
    private func handlePendingRestAccuracyBoostIfNeeded(now: Date) {
        guard isTracking, currentState == .riding, pendingRestStartTime != nil, isUsingBarometer else { return }
        
        if let until = pendingRestBoostUntil, now >= until {
            pendingRestBoostUntil = nil
        }
        
        if let lastBoost = lastPendingRestBoostTime,
           now.timeIntervalSince(lastBoost) < pendingRestBoostCooldown {
            updateLocationAccuracy(for: .riding)
            return
        }
        
        if let drop = recentBaroCumulativeDrop(within: pendingRestDescentWindow, now: now),
           drop >= pendingRestDescentThreshold {
            pendingRestBoostUntil = now.addingTimeInterval(pendingRestBoostDuration)
            lastPendingRestBoostTime = now
            appendBarometerLog(note: "Pending Rest 하강 감지: GPS 정확도 임시 상승 (drop=\(String(format: "%.2f", drop))m)")
        }
        
        updateLocationAccuracy(for: .riding)
    }
    
    private func computeRecentLinearityRatio() -> Double? {
        guard recentLocations.count >= 5 else { return nil }
        guard let first = recentLocations.first, let last = recentLocations.last else { return nil }
        
        var totalDistance: Double = 0.0
        for i in 1..<recentLocations.count {
            totalDistance += recentLocations[i].distance(from: recentLocations[i - 1])
        }
        guard totalDistance >= minLinearityDistance else { return nil }
        let straightDistance = last.distance(from: first)
        guard straightDistance > 0 else { return nil }
        return straightDistance / totalDistance
    }
    
    private func computeRecentCourseStdDev() -> Double? {
        let validCourses = recentLocations.compactMap { location -> Double? in
            guard location.course >= 0 else { return nil }
            guard location.speed >= minCourseSpeed else { return nil }
            return location.course
        }
        guard validCourses.count >= 5 else { return nil }
        
        let radians = validCourses.map { $0 * Double.pi / 180.0 }
        let sinSum = radians.reduce(0.0) { $0 + sin($1) }
        let cosSum = radians.reduce(0.0) { $0 + cos($1) }
        let n = Double(radians.count)
        let r = sqrt((sinSum / n) * (sinSum / n) + (cosSum / n) * (cosSum / n))
        let clampedR = max(min(r, 1.0), 0.000001)
        let stdRad = sqrt(-2.0 * log(clampedR))
        return stdRad * 180.0 / Double.pi
    }

    // MARK: - Pending Riding (Pre-roll)
    
    private func startPendingRiding(at location: CLLocation, startIndex: Int) {
        pendingRidingStartTime = location.timestamp
        pendingRidingStartIndex = startIndex
        pendingRidingLocations = [location]
    }
    
    private func updatePendingRiding(with location: CLLocation) {
        guard pendingRidingStartTime != nil else { return }
        pendingRidingLocations.append(location)
    }
    
    private func shouldConfirmPendingRiding() -> Bool {
        guard let startTime = pendingRidingStartTime else { return false }
        let elapsed = Date().timeIntervalSince(startTime)
        guard elapsed >= pendingRidingDuration else { return false }
        
        let avgSpeed = pendingAverageSpeedKmH()
        let distance = pendingHorizontalDistance()
        let drop = pendingVerticalDrop()
        
        guard let avgSpeed, let distance, let drop else { return false }
        return avgSpeed >= pendingRidingMinAvgSpeed
            && distance >= pendingRidingMinDistance
            && drop >= pendingRidingMinDrop
    }

    private func shouldResetPendingRiding() -> Bool {
        guard let startTime = pendingRidingStartTime else { return false }
        return Date().timeIntervalSince(startTime) >= pendingRidingDuration
    }
    
    private func resetPendingRiding() {
        pendingRidingStartTime = nil
        pendingRidingStartIndex = nil
        pendingRidingLocations.removeAll()
    }
    
    // MARK: - Pending Rest (Idle Check)
    
    private func startPendingRest(at location: CLLocation) {
        pendingRestStartTime = recentLocations.first?.timestamp ?? location.timestamp
        pendingRestStartIndex = routeSpeeds.count
        pendingRestFinalizeTime = nil
        pendingRestFinalizeIndex = nil
        onLiftStartCandidates.removeAll()
        FlowScoreAnalyzer.shared.updatePendingRest(isActive: true)
    }
    
    private func resetPendingRest() {
        pendingRestStartTime = nil
        pendingRestStartIndex = nil
        pendingRestFinalizeTime = nil
        pendingRestFinalizeIndex = nil
        pendingRestBoostUntil = nil
        lastPendingRestBoostTime = nil
        FlowScoreAnalyzer.shared.updatePendingRest(isActive: false)
    }
    
    private func shouldResumeFromPendingRest(stateSpeedKmH: Double, isDescending: Bool) -> Bool {
        guard stateSpeedKmH >= pendingRestResumeSpeedThreshold else { return false }
        let netDrop = recentNetDropMeters()
        let hasDrop = (netDrop ?? 0) >= pendingRestResumeDropThreshold || isDescending
        return hasDrop
    }
    
    private func pendingAverageSpeedKmH() -> Double? {
        guard pendingRidingLocations.count >= 3 else { return nil }
        let speeds = pendingRidingLocations.map { max(0, $0.speed * 3.6) }
        let sum = speeds.reduce(0, +)
        return sum / Double(speeds.count)
    }
    
    private func pendingHorizontalDistance() -> Double? {
        guard pendingRidingLocations.count >= 2 else { return nil }
        guard let first = pendingRidingLocations.first, let last = pendingRidingLocations.last else { return nil }
        return last.distance(from: first)
    }
    
    private func pendingVerticalDrop() -> Double? {
        guard let startTime = pendingRidingStartTime else { return nil }
        if isUsingBarometer {
            let values = recentBaroSamples
                .filter { $0.time >= startTime }
                .map { $0.altitude }
            guard let first = values.first, let last = values.last else { return nil }
            return max(0, first - last)
        }
        let values = recentGPSAltitudeSamples
            .filter { $0.time >= startTime }
            .map { $0.altitude }
        guard let first = values.first, let last = values.last else { return nil }
        return max(0, first - last)
    }

    private func shouldTransitionToRestingFromRiding() -> Bool {
        guard let speedMax = recentMaxSpeedKmH() else { return false }
        guard speedMax <= ridingRestSpeedThreshold else { return false }
        
        let netDrop = recentNetDropMeters()
        guard let netDrop else { return false }
        return netDrop <= ridingRestDropThreshold
    }
    
    private func recentMaxSpeedKmH() -> Double? {
        guard recentLocations.count >= 5 else { return nil }
        let speeds = recentLocations.map { max(0, $0.speed * 3.6) }
        return speeds.max()
    }
    
    private func recentAverageSpeedKmH() -> Double? {
        guard recentLocations.count >= 3 else { return nil }
        let speeds = recentLocations.map { max(0, $0.speed * 3.6) }
        let sum = speeds.reduce(0, +)
        return sum / Double(speeds.count)
    }

    private func recentHorizontalDisplacement() -> Double? {
        guard recentLocations.count >= 2 else { return nil }
        guard let first = recentLocations.first, let last = recentLocations.last else { return nil }
        return last.distance(from: first)
    }

    private func shouldAllowRestingToOnLift(stateSpeedKmH: Double) -> Bool {
        let hasSpeed = stateSpeedKmH >= restToLiftMinSpeedKmH
        let horizontalDistance = recentHorizontalDisplacement() ?? 0
        let hasMove = horizontalDistance >= restToLiftMinHorizontalDistance
        return hasSpeed || hasMove
    }
    
    private func recentNetDropMeters() -> Double? {
        let values: [Double]
        if isUsingBarometer {
            values = recentBaroSamples.map { $0.altitude }
        } else {
            values = recentGPSAltitudeSamples.map { $0.altitude }
        }
        
        guard values.count >= 5, let first = values.first, let last = values.last else { return nil }
        return max(0, first - last)
    }
    
    private func verticalRange(from values: [Double]) -> Double? {
        guard values.count >= 5 else { return nil }
        guard let minValue = values.min(), let maxValue = values.max() else { return nil }
        return maxValue - minValue
    }

    private func updateBarometerDriftUsingGPSIfNeeded() {
        guard isUsingBarometer, currentState == .resting else { return }
        guard let startAltitude = sessionStartSmoothedAltitude, let currentAltitude = recentSmoothedGPSAltitude() else { return }
        guard let baroAltitude = lastBaroAltitude else { return }
        
        let gpsRelative = currentAltitude - startAltitude
        let error = baroAltitude - gpsRelative
        
        guard abs(error) >= baroDriftUpdateThreshold else { return }
        
        let correction = error * baroDriftUpdateGain
        baroDriftOffset += correction
        baroDriftCorrection += correction
        baroDriftUpdateCount += 1
        applyBaroOffsetShift(correction)
        
        appendBarometerLog(note: "휴식 구간 드리프트 보정: Δ\(String(format: "%.2f", correction))m, err=\(String(format: "%.2f", error))m")
    }

    private func recentSmoothedGPSAltitude() -> Double? {
        guard !gpsSmoothedAltitudeHistory.isEmpty else { return nil }
        let window = min(gpsDriftSmoothingWindow, gpsSmoothedAltitudeHistory.count)
        let recent = gpsSmoothedAltitudeHistory.suffix(window)
        let sum = recent.reduce(0, +)
        return sum / Double(window)
    }
    
    private func applyBaroOffsetShift(_ delta: Double) {
        if let last = lastBaroAltitude {
            lastBaroAltitude = last - delta
        }
        if let prev = previousBaroAltitude {
            previousBaroAltitude = prev - delta
        }
        if !baroRawHistory.isEmpty {
            baroRawHistory = baroRawHistory.map { $0 - delta }
        }
        if !baroAltitudeHistory.isEmpty {
            baroAltitudeHistory = baroAltitudeHistory.map { $0 - delta }
        }
    }

    // MARK: - 바리오 로그 내보내기
    
    func exportBarometerLog(startTime: Date, endTime: Date) -> URL? {
        guard barometerAvailable, baroSampleCount > 0 else { return nil }
        
        let baselineDelay = baroBaselineSetTime.map { $0.timeIntervalSince(startTime) }
        let summary = BarometerLogPayload.Summary(
            startTime: startTime,
            endTime: endTime,
            baroAvailable: barometerAvailable,
            baroSampleCount: baroSampleCount,
            baroGainTotal: baroGainTotal,
            baroDropTotal: baroDropTotal,
            baroDriftCorrection: baroDriftCorrection,
            baroDriftOffset: baroDriftOffset,
            baroOutlierCount: baroOutlierCount,
            gpsAltitudeOutlierCount: gpsAltitudeOutlierCount,
            driftUpdateCount: baroDriftUpdateCount,
            baselineSampleWindow: baroBaselineSampleWindow,
            baselineDelay: baselineDelay
        )
        
        let logs = barometerLogs.map {
            BarometerLogPayload.Entry(
                timestamp: $0.timestamp,
                baroAltitude: $0.baroAltitude,
                verticalSpeed: $0.verticalSpeed,
                speed: $0.speed,
                state: $0.state?.rawValue,
                recentGain: $0.recentGain,
                recentDrop: $0.recentDrop,
                note: $0.note
            )
        }
        
        do {
            return try BarometerLogExportService.export(summary: summary, logs: logs)
        } catch {
            return nil
        }
    }
    
    private func applyBarometerDriftCorrectionIfNeeded() {
        guard isUsingBarometer, !baroDriftApplied else { return }
        guard let lastAltitude = lastBaroAltitude else { return }
        guard let startLocation = sessionStartLocation, let endLocation = lastLocation else {
            appendBarometerLog(note: "드리프트 보정 스킵: 시작/종료 위치 없음")
            baroDriftApplied = true
            return
        }
        
        let startAltitude = sessionStartSmoothedAltitude ?? startLocation.altitude
        let endAltitude = recentSmoothedGPSAltitude() ?? lastSmoothedGPSAltitude ?? endLocation.altitude
        let distanceFromStart = endLocation.distance(from: startLocation)
        let gpsAltitudeDelta = abs(endAltitude - startAltitude)
        
        guard distanceFromStart <= gpsDriftDistanceThreshold, gpsAltitudeDelta <= gpsDriftAltitudeThreshold else {
            appendBarometerLog(note: "드리프트 보정 스킵: 거리=\(Int(distanceFromStart))m, GPSΔ=\(String(format: "%.2f", gpsAltitudeDelta))m")
            baroDriftApplied = true
            return
        }
        
        let drift = lastAltitude // 기준점 대비 최종 오프셋 (m)
        guard abs(drift) >= baroDriftThreshold else {
            baroDriftApplied = true
            appendBarometerLog(note: "드리프트 보정 없음: drift=\(String(format: "%.2f", drift))m")
            return
        }
        
        if drift > 0 {
            // 기준점 대비 상승(드리프트) → 상승량에서 보정
            let correction = min(drift, baroGainTotal)
            baroGainTotal = max(0, baroGainTotal - correction)
            baroDriftCorrection += correction
            appendBarometerLog(note: "드리프트 보정 적용(상승): -\(String(format: "%.2f", correction))m")
        } else {
            // 기준점 대비 하강(드리프트) → 하강량에서 보정
            let correction = min(abs(drift), baroDropTotal)
            baroDropTotal = max(0, baroDropTotal - correction)
            if isUsingBarometer {
                verticalDrop = max(0, verticalDrop - correction)
            }
            baroDriftCorrection -= correction
            appendBarometerLog(note: "드리프트 보정 적용(하강): -\(String(format: "%.2f", correction))m")
        }
        
        baroDriftApplied = true
    }
    
    // MARK: - 상태 기반 GPS 정확도 조절 (배터리 최적화)
    
    private func updateLocationAccuracy(for state: RidingState) {
        switch state {
        case .riding:
            // 활강 중: 기본 최고 정확도, Pending Rest 상태에서는 낮춤 + 부스트
            if pendingRestStartTime != nil {
                if let until = pendingRestBoostUntil, Date() < until {
                    locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
                } else {
                    locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
                }
            } else {
                locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            }
        case .onLift:
            // 리프트: 기본은 저전력, 하차 감지 시 일시적으로 고정밀
            if let until = liftAccuracyBoostUntil, Date() < until {
                locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            } else {
                locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            }
        case .resting:
            // 휴식: 리프트 탑승 대기 중일 수 있으므로 10m 정확도 유지
            // 기존 100m 설정은 리프트 탑승 직후 저속 구간에서 위치 업데이트가 멈추는(Speed 0) 원인이 됨
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        }
    }
    
    // MARK: - 상태 전환 로직
    
    private func determineState(currentLocation: CLLocation, previousLocation: CLLocation?) -> RidingState {
        let currentSpeedKmH = max(0, currentLocation.speed * 3.6)
        let stateSpeedKmH = recentAverageSpeedKmH() ?? currentSpeedKmH
        
        let useBarometerSignals = isUsingBarometer && !baroAltitudeHistory.isEmpty
        
        // 고도 변화 계산 및 트렌드 분석 (GPS/Barometer 선택)
        let altitudeChange: Double
        if useBarometerSignals {
            if let prev = previousBaroAltitude, let current = lastBaroAltitude {
                altitudeChange = prev - current // 양수 = 하강
            } else {
                altitudeChange = 0
            }
        } else if let prev = previousSmoothedGPSAltitude, let current = lastSmoothedGPSAltitude {
            altitudeChange = prev - current // 양수 = 하강
        } else {
            altitudeChange = 0
        }
        
        let history = useBarometerSignals ? baroAltitudeHistory : altitudeHistory
        
        // Robust Descent Detection (안정적인 하강 감지)
        // 로직: 순간적인 변화(0.5m) 또는 최근 샘플 기준 누적 1.5m 이상 하강
        let isDescending: Bool
        if let first = history.first, let last = history.last, history.count >= 3 {
             isDescending = (first - last) > 1.5
        } else {
             isDescending = altitudeChange > 0.5
        }
        
        let altitudeTrend = recentAltitudeNetChange(
            window: altitudeTrendWindow,
            minSpan: altitudeTrendMinSpan,
            useBarometer: useBarometerSignals
        )
        let recentGain = altitudeTrend?.gain ?? 0
        let recentDrop = altitudeTrend?.drop ?? 0
        
        // Robust Ascent Detection (리프트 탑승 감지)
        // 로직: 최근 10초간 5m 이상 상승 (최소 span 6초)
        // Issue #5 수정: 리프트 초기 저속 구간 대응을 위해 임계값 완화 (8m → 5m)
        let isClimbing = recentGain > 5.0
        
        // Riding에서 리프트 전환용 상향 기준 (노이즈 방지, 완화 적용)
        let isClimbingStrict = recentGain > 7.0
        
        // Robust Strong Descent (강력한 하강 감지 - 리프트 오인식 방지용)
        // 로직: 최근 10초간 5m 이상 하강 (최소 span 6초)
        // 10m(초보자 인식 불가) -> 5m(초보자 10km/h 인식 가능)로 완화
        let isStrongDescent = recentDrop > 5.0
        
        // 슬로프 좌표는 상태 판정에 사용하지 않고 태깅/표시에만 사용
        // (필요 시 리조트 영역 게이트는 별도 구현 예정)
        
        // 상태 판정 로직
        switch currentState {
        case .resting:
            // RESTING → RIDING: 속도↑ + 하강 중 (슬로프 판정 의존 완화)
            if stateSpeedKmH > ridingSpeedThreshold && isDescending {
                if pendingRidingStartTime == nil {
                    startPendingRiding(at: currentLocation, startIndex: routeCoordinates.count)
                } else {
                    updatePendingRiding(with: currentLocation)
                }
                
                if shouldConfirmPendingRiding() {
                    return .riding
                }
                
                if shouldResetPendingRiding() {
                    resetPendingRiding()
                }
            } else {
                resetPendingRiding()
            }
            // RESTING → ON_LIFT: 상승 트렌드 + 느슨한 이동/속도 게이트
            // 휴식 중 기압 변동만으로 리프트로 튀는 케이스를 완화
            if isClimbing && shouldAllowRestingToOnLift(stateSpeedKmH: stateSpeedKmH) {
                resetPendingRiding()
                return .onLift
            }
            return .resting
            
        case .riding:
            // RIDING → ON_LIFT: 상승 트렌드가 확실하면 리프트로 간주 (노이즈 방지 상향 기준)
            if isClimbingStrict {
                if pendingRestStartTime != nil {
                    pendingRestFinalizeTime = pendingRestStartTime
                    pendingRestFinalizeIndex = pendingRestStartIndex
                }
                return .onLift
            }
            
            if pendingRestStartTime != nil {
                if shouldResumeFromPendingRest(stateSpeedKmH: stateSpeedKmH, isDescending: isDescending) {
                    resetPendingRest()
                    updateLocationAccuracy(for: .riding)
                    return .riding
                }
                if let start = pendingRestStartTime, Date().timeIntervalSince(start) >= pendingRestTimeout {
                    pendingRestFinalizeTime = pendingRestStartTime
                    pendingRestFinalizeIndex = pendingRestStartIndex
                    return .resting
                }
                return .riding
            }
            
            // RIDING → RESTING (보류): 최근 20초 동안 저속 + 하강량 제한이면 일단 보류 상태 진입
            if shouldTransitionToRestingFromRiding() {
                startPendingRest(at: currentLocation)
                updateLocationAccuracy(for: .riding)
                return .riding
            }
            
            return .riding
            
        case .onLift:
            // ON_LIFT 상태 유지 (접착성 강화):
            // 리프트가 도중에 멈추거나 완만해져도 계속 리프트로 간주.
            // 오직 '활강(하강)'하거나 '완전히 내려서 쉴 때'만 해제.
            
            // 1. 활강 감지 (확실한 하강 + 속도) -> RIDING
            let linearityRatio = computeRecentLinearityRatio()
            let courseStdDev = computeRecentCourseStdDev()
            let isLikelyLiftLinear = (linearityRatio ?? 0.0) >= liftLinearityThreshold
                && (courseStdDev ?? 180.0) <= liftCourseStdThreshold
            
            if stateSpeedKmH > ridingSpeedThreshold && isStrongDescent && !isLikelyLiftLinear {
                liftStationaryStartTime = nil
                return .riding
            }
            
            // 2. 하차 후 대기 감지 (평지 + 저속) -> RESTING
            // 리프트에서 내려서 짐 정리하거나 화장실 가는 경우.
            // 단순히 리프트가 멈춘 것과 구별하기 위해 60초 이상 지속되어야 함.
            if stateSpeedKmH < 1.5 && !isClimbing && !isStrongDescent {
                if liftStationaryStartTime == nil {
                    liftStationaryStartTime = Date()
                } else if let start = liftStationaryStartTime, Date().timeIntervalSince(start) > 60.0 {
                    liftStationaryStartTime = nil
                    return .resting
                }
            } else {
                // 다시 움직이면 타이머 리셋 (리프트 재가동)
                liftStationaryStartTime = nil
            }
            
            return .onLift
        }
    }
    
    /// 상태 전환 debounce 체크
    private func canChangeState() -> Bool {
        if stateChangeTime == nil {
            stateChangeTime = Date()
            return false
        }
        return Date().timeIntervalSince(stateChangeTime!) >= stateChangeDebounce
    }
    
    /// 상태 전환 처리
    private func handleStateChange(from oldState: RidingState, to newState: RidingState, currentLocation: CLLocation) {
        // 상태가 변경되었을 때만 처리
        guard oldState != newState else { return }
        
        // 타임라인 이벤트 기록
        let now = Date()
        let timelineOldState = timelineState(oldState)
        let timelineNewState = timelineState(newState)
        let transitionTime: Date
        if oldState == .resting, newState == .riding, let pendingTime = pendingRidingStartTime {
            transitionTime = pendingTime
        } else if oldState == .riding, (newState == .resting || newState == .onLift), let finalizeTime = pendingRestFinalizeTime {
            // Pending Rest 시작 시점을 타임라인에도 반영 (런 스탯과 정합)
            transitionTime = finalizeTime
        } else {
            transitionTime = now
        }
        
        if timelineOldState != timelineNewState {
            if let start = currentTimelineEventStart {
                var detail = timelineOldState.displayLabel
                let duration = transitionTime.timeIntervalSince(start)
                
                // 짧은 리프트 이벤트는 휴식으로 병합 (타임라인 정리용)
                if timelineOldState == .onLift,
                   timelineNewState == .resting,
                   duration < shortOnLiftMergeThreshold {
                    if let lastIndex = timelineEvents.indices.last,
                       timelineEvents[lastIndex].type == .rest,
                       timelineEvents[lastIndex].endTime == start {
                        timelineEvents[lastIndex].endTime = transitionTime
                        print("⏱️ 짧은 리프트 병합: 휴식 이벤트 연장 (\(Int(duration))초)")
                    } else {
                        let event = RunSession.TimelineEvent(type: .rest, startTime: start, endTime: transitionTime, detail: "휴식")
                        timelineEvents.append(event)
                        print("⏱️ 짧은 리프트 병합: 휴식 이벤트 생성 (\(Int(duration))초)")
                    }
                } else {
                    if timelineOldState == .riding {
                        // 이 시점에서는 아직 visitedSlopeCounts가 초기화되지 않았으므로 calculateBestSlope 호출 가능
                        // 다만 calculateBestSlope는 무거운 연산일 수 있으므로 주의.
                        // handleStateChange 내부 로직상 resting으로 갈때만 calculateBestSlope를 호출하긴 함.
                        // 여기서는 간단히 currentSlope 쓰거나 calculateBestSlope 사용
                        if let best = calculateBestSlope() {
                            detail = best.name
                        } else {
                            detail = "알 수 없는 슬로프"
                        }
                    } else if timelineOldState == .onLift {
                        detail = "리프트 이동"
                    } else if timelineOldState == .resting {
                        detail = "휴식"
                    }
                    
                    // RunSession.TimelineEvent 생성
                    let type = mapStateToEventType(timelineOldState)
                    let event = RunSession.TimelineEvent(type: type, startTime: start, endTime: transitionTime, detail: detail)
                    timelineEvents.append(event)
                    print("⏱️ 타임라인 이벤트 추가: \(detail) (\(Int(now.timeIntervalSince(start)))초)")
                }
            }
            currentTimelineEventStart = transitionTime
        }
        
        // GPS 정확도 조절
        updateLocationAccuracy(for: newState)
        
        // 점수 분석기 상태 동기화
        FlowScoreAnalyzer.shared.updateState(newState)
        RidingMetricAnalyzer.shared.updateState(newState)
        
        // 런 시작: RIDING 진입 시 1회만 기록
        // NOTE: 리프트 점선 연결을 위해 실제 런 시작 시점만 인덱스 기록
        if newState == .riding {
            if currentRunStartTime == nil {
                currentRunStartTime = transitionTime
                currentRunDistance = 0.0
                currentRunVerticalDrop = 0.0
                // 새로운 런 시작: 현재 좌표 배열의 끝을 시작 인덱스로 기록
                // (단, 첫 런(0)은 이미 초기화 시 들어가있으므로, 좌표가 쌓인 상태에서 다시 riding 될 때만 추가)
                if let pendingIndex = pendingRidingStartIndex {
                    if pendingIndex > 0 {
                        runStartIndices.append(pendingIndex)
                        print("🛤️ 새로운 런 시작 인덱스 기록(Pending): \(pendingIndex)")
                    }
                } else if !routeCoordinates.isEmpty {
                    runStartIndices.append(routeCoordinates.count)
                    print("🛤️ 새로운 런 시작 인덱스 기록: \(routeCoordinates.count)")
                }
            }
            
            // 리프트 부스트로 기록된 Start 후보를 라이딩 시작 위치에서 검증 후 반영
            if !onLiftStartCandidates.isEmpty {
                let coordinate = currentLocation.coordinate
                for slopeName in onLiftStartCandidates {
                    if let slope = SlopeDatabase.shared.findSlope(byName: slopeName),
                       slope.contains(coordinate) {
                        visitedSlopeStartHits.insert(slopeName)
                        print("🚩 Start Point Merge(Boost): \(slopeName)")
                    }
                }
                onLiftStartCandidates.removeAll()
            }
        }

        if oldState == .riding && (newState == .resting || newState == .onLift) {
            let finalizeTime = pendingRestFinalizeTime ?? now
            let finalizeIndex = pendingRestFinalizeIndex
            finalizeCurrentRun(at: finalizeTime, endIndex: finalizeIndex)
        }
        
        // debounce 타이머 리셋
        stateChangeTime = nil
        resetPendingRiding()
        resetPendingRest()
        
        // ON_LIFT에서 벗어나면 부스트 Start 후보는 폐기
        if oldState == .onLift && newState != .onLift {
            onLiftStartCandidates.removeAll()
        }
        
        if newState != .onLift {
            liftAccuracyBoostUntil = nil
            lastLiftAccuracyBoostTime = nil
        }
        
        print("🎿 상태 전환: \(oldState.displayLabel) → \(newState.displayLabel)")
    }
    
    // MARK: - 평균 속도 계산
    
    private func calculateAvgSpeed() {
        guard !speedSamples.isEmpty else {
            avgSpeed = 0.0
            return
        }
        avgSpeed = speedSamples.reduce(0, +) / Double(speedSamples.count)
    }
    
    /// 현재 런에서 가장 적합한 슬로프 반환 (Start/Finish 완주 > 난이도 > Dwell Time)
    private func calculateBestSlope() -> Slope? {
        guard !visitedSlopeCounts.isEmpty else { return currentSlope }
        
        // 1. 후보군 추출 (최소 방문 횟수 필터링)
        let maxCount = visitedSlopeCounts.values.max() ?? 0
        let threshold = Double(maxCount) * 0.1
        let candidates = visitedSlopeCounts.filter { Double($0.value) >= threshold }.keys
        let slopes = candidates.compactMap { SlopeDatabase.shared.findSlope(byName: $0) }
        
        // 2. 완주한 슬로프(Start & Finish 모두 통과) 필터링
        let completedSlopes = slopes.filter {
            visitedSlopeStartHits.contains($0.name) && visitedSlopeFinishHits.contains($0.name)
        }
        
        // 3. 우선순위 결정
        if !completedSlopes.isEmpty {
            // 완주한 슬로프가 있다면, 난이도가 높은 순서대로 우선순위 부여
            return completedSlopes.sorted { $0.difficulty.priority > $1.difficulty.priority }.first
        } else {
            // 완주한 슬로프가 없다면, 기존 방식(면적이 작은 순서 -> 상세한 슬로프) 사용
            return slopes.sorted {
                if abs($0.polygonArea - $1.polygonArea) > 0.0000001 {
                    return $0.polygonArea < $1.polygonArea
                }
                return $0.difficulty.priority > $1.difficulty.priority
            }.first
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }
        
        // GPS 정확도 필터링 (50m 이상 오차는 무시)
        guard newLocation.horizontalAccuracy <= 50 else {
            print("⚠️ GPS 정확도 낮음: \(newLocation.horizontalAccuracy)m")
            return
        }
        
        // 현재 속도 업데이트
        if newLocation.speed >= 0 {
            let currentSpeedKmH = newLocation.speed * 3.6
            self.speed = currentSpeedKmH
        } else {
            self.speed = 0.0
        }
        
        self.location = newLocation
        self.altitude = newLocation.altitude
        
        // GPS 고도 스무딩 업데이트 (항상 수행)
        updateGPSAltitudeSmoothing(with: newLocation)
        updateRecentLocations(with: newLocation)
        
        // 세션 시작점 기록 (첫 위치 기준)
        if isTracking && sessionStartLocation == nil {
            sessionStartLocation = newLocation
            sessionStartSmoothedAltitude = lastSmoothedGPSAltitude ?? newLocation.altitude
        }
        
        // 경사각 계산 (바리오 우선, 없으면 GPS)
        let horizontalSpeedMS = max(0, newLocation.speed)
        let verticalSpeedMS: Double
        if isUsingBarometer {
            verticalSpeedMS = baroVerticalSpeed
        } else if let prev = lastLocation, let prevAlt = previousSmoothedGPSAltitude, let currentAlt = lastSmoothedGPSAltitude {
            let dt = newLocation.timestamp.timeIntervalSince(prev.timestamp)
            if dt > 0 {
                verticalSpeedMS = (currentAlt - prevAlt) / dt
            } else {
                verticalSpeedMS = 0.0
            }
        } else {
            verticalSpeedMS = 0.0
        }
        
        if horizontalSpeedMS > 0.8 { // 약 3km/h 이상에서만 계산
            slopeAngle = atan(abs(verticalSpeedMS) / horizontalSpeedMS) * 180.0 / Double.pi
        } else {
            slopeAngle = 0.0
        }
        
        // 트래킹 중일 때만 상세 처리
        guard isTracking else {
            lastLocation = newLocation
            return
        }
        
        // 1. 상태 결정
        let newState = determineState(currentLocation: newLocation, previousLocation: lastLocation)
        if newState != currentState {
            handleStateChange(from: currentState, to: newState, currentLocation: newLocation)
            currentState = newState
        }
        
        // 휴식 구간에서만 GPS 기반 드리프트 보정 업데이트
        updateBarometerDriftUsingGPSIfNeeded()
        
        // 점수 분석기 위치 업데이트 (상태는 내부에서 필터링)
        RidingMetricAnalyzer.shared.updateLocation(newLocation)
        FlowScoreAnalyzer.shared.updateLocation(newLocation)
        
        // 2. 경로 및 메트릭 기록
        if isTracking, let previous = lastLocation {
            // 거리 누적 (RIDING 상태만)
            let distance = newLocation.distance(from: previous)
            if currentState == .riding {
                totalDistance += distance
                currentRunDistance += distance
                
                // Vertical Drop 누적 (GPS 경로는 Barometer 비활성 시에만 사용)
                if !isUsingBarometer {
                    let altitudeDiff = (previousSmoothedGPSAltitude ?? previous.altitude) - (lastSmoothedGPSAltitude ?? newLocation.altitude)
                    if altitudeDiff > minVerticalDrop {
                        verticalDrop += altitudeDiff
                        currentRunVerticalDrop += altitudeDiff
                    }
                }
                
                // 최고 속도 갱신 (속도 정확도 엄격 필터 적용)
                let isSpeedAccurateForMax = newLocation.speedAccuracy >= 0 && newLocation.speedAccuracy <= 2.0
                if isSpeedAccurateForMax && speed > maxSpeed {
                    maxSpeed = speed
                }
                
                // 평균 속도 샘플 수집
                if speed > ridingSpeedThreshold {
                    speedSamples.append(speed)
                    calculateAvgSpeed()
                }
            }
            
            // GPS 경로 수집 (상태별 거리 필터 차등 적용 + 시간 기반 보강)
            // Riding: 5m (정밀), Lift/Resting: 20m (배터리 절약)
            let filterDistance: Double = (currentState == .riding) ? 5.0 : 20.0
            let lastTimestamp = routeTimestamps.last ?? newLocation.timestamp.timeIntervalSince1970
            let timeSinceLastSample = max(0, newLocation.timestamp.timeIntervalSince1970 - lastTimestamp)
            let shouldRecordByTime = timeSinceLastSample >= routeTimeSampleInterval
            
            if distance >= filterDistance || routeCoordinates.isEmpty || shouldRecordByTime {
                let coordinate = newLocation.coordinate
                let altitudeValue = routeAltitudeValue(for: newLocation)
                let cumulativeDistance: Double
                if let lastCoord = routeCoordinates.last {
                    let lastLocation = CLLocation(latitude: lastCoord[0], longitude: lastCoord[1])
                    let previousTotal = routeDistances.last ?? 0
                    cumulativeDistance = previousTotal + lastLocation.distance(from: newLocation)
                } else {
                    cumulativeDistance = 0
                }
                
                let timelineState = timelineState(currentState)
                routeCoordinates.append([coordinate.latitude, coordinate.longitude])
                routeSpeeds.append(max(0, newLocation.speed * 3.6))
                routeTimestamps.append(newLocation.timestamp.timeIntervalSince1970)
                routeAltitudes.append(altitudeValue)
                routeDistances.append(cumulativeDistance)
                routeStates.append(mapStateToEventType(timelineState))
                routeSpeedAccuracies.append(newLocation.speedAccuracy)
            }
        }

        
        // 3. 슬로프 인식 및 Start/Finish 감지 (배터리 최적화: 일정 거리 이동 시마다)
        // Issue #6 수정: 출발 지점 대기 중(Resting)에도 Start Point를 인식할 수 있도록 조건 완화
        if (currentState == .riding || currentState == .resting) && shouldCheckSlope(at: newLocation) {
            
            // A. 슬로프 내부 판정 (Dwell Time)
            if let slope = SlopeDatabase.shared.findSlope(at: newLocation) {
                // RESTING 상태라도 슬로프 안에 있다면 현재 슬로프로 갱신 (대기 중 위치 파악)
                if currentSlope?.id != slope.id {
                    currentSlope = slope
                    print("📍 슬로프 인식: \(slope.name)")
                }
                
                // RIDING 중이면 방문 카운트 증가
                if currentState == .riding {
                    visitedSlopeCounts[slope.name, default: 0] += 1
                }
            }
            
            // B. Start/Finish 지점 통과 감지
            let checkSlopes = SlopeDatabase.shared.operatingSlopes
            for slope in checkSlopes {
                // Start(Top) Check: Riding, Resting 모두 허용 (출발 전 대기 포함)
                if let top = slope.topPoint,
                   CLLocation(latitude: top.latitude, longitude: top.longitude).distance(from: newLocation) <= pointHitRadius {
                    if !visitedSlopeStartHits.contains(slope.name) {
                        print("🚩 Start Point Hit: \(slope.name) (State: \(currentState))")
                        visitedSlopeStartHits.insert(slope.name)
                    }
                }
                // Finish(Bottom) Check: Riding 상태에서만 허용 (오탐지 방지)
                if currentState == .riding {
                    if let bottom = slope.bottomPoint,
                       CLLocation(latitude: bottom.latitude, longitude: bottom.longitude).distance(from: newLocation) <= pointHitRadius {
                        if !visitedSlopeFinishHits.contains(slope.name) {
                            print("🏁 Finish Point Hit: \(slope.name)")
                            visitedSlopeFinishHits.insert(slope.name)
                        }
                    }
                }
            }
            
            lastSlopeCheckLocation = newLocation
        }
        
        // ON_LIFT 부스트 구간에서 Start 후보만 수집 (실제 반영은 RIDING 시작 시점에 검증)
        if currentState == .onLift,
           let until = liftAccuracyBoostUntil,
           newLocation.timestamp < until,
           shouldCheckSlope(at: newLocation) {
            let checkSlopes = SlopeDatabase.shared.operatingSlopes
            for slope in checkSlopes {
                if let top = slope.topPoint,
                   CLLocation(latitude: top.latitude, longitude: top.longitude).distance(from: newLocation) <= pointHitRadius {
                    if !onLiftStartCandidates.contains(slope.name) {
                        onLiftStartCandidates.insert(slope.name)
                        print("🚩 Start Point Candidate(Boost): \(slope.name)")
                    }
                }
            }
            lastSlopeCheckLocation = newLocation
        }
        
        lastLocation = newLocation
    }
    
    /// 슬로프 체크 필요 여부 (배터리 최적화)
    private func shouldCheckSlope(at location: CLLocation) -> Bool {
        guard let lastCheck = lastSlopeCheckLocation else { return true }
        return location.distance(from: lastCheck) >= slopeCheckDistance
    }
    
    /// 현재 런 확정 및 메트릭 저장
    private func finalizeCurrentRun(at endTime: Date, endIndex: Int? = nil) {
        guard currentRunStartTime != nil else { return }
        let runStartTime = currentRunStartTime ?? endTime
        let duration = endTime.timeIntervalSince(runStartTime)
        
        // 노이즈 런 필터: 40초 이하 + 하강고도 30m 이하
        if duration <= 40.0 && currentRunVerticalDrop <= 30.0 {
            let drop = currentRunVerticalDrop
            lastRunWasAccepted = false
            if runStartIndices.count > 1 {
                runStartIndices.removeLast()
            }
            currentRunDistance = 0.0
            currentRunVerticalDrop = 0.0
            currentRunStartTime = nil
            visitedSlopeCounts.removeAll()
            visitedSlopeStartHits.removeAll()
            visitedSlopeFinishHits.removeAll()
            print("🚫 노이즈 런 제외: \(Int(duration))초, 하강 \(Int(drop))m")
            return
        }
        
        lastRunWasAccepted = true
        runCount += 1
        completedRunDistances.append(currentRunDistance)
        completedRunVerticalDrops.append(currentRunVerticalDrop)
        let safeEndIndex = min(endIndex ?? routeSpeeds.count, routeSpeeds.count)
        completedRunEndIndices.append(safeEndIndex)
        completedRunStartTimes.append(runStartTime)
        completedRunEndTimes.append(endTime)
        currentRunDistance = 0.0
        currentRunVerticalDrop = 0.0
        currentRunStartTime = nil
        
        // 런 종료 시, 방문했던 슬로프 중 가장 우선순위가 높은 슬로프를 최종 슬로프로 확정
        if let bestSlope = calculateBestSlope() {
            print("🏁 런 종료. 최종 슬로프 확정: \(bestSlope.name)")
            currentSlope = bestSlope
            
            // 세션 통계에 추가
            sessionSlopeCounts[bestSlope.name, default: 0] += 1
            completedRunSlopeNames.append(bestSlope.name)
        } else {
            completedRunSlopeNames.append(currentSlope?.name ?? "알 수 없는 슬로프")
        }
        visitedSlopeCounts.removeAll()
        visitedSlopeStartHits.removeAll()
        visitedSlopeFinishHits.removeAll()
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            print("위치 권한 허용됨")
        case .denied, .restricted:
            print("위치 권한 거부됨")
        case .notDetermined:
            print("위치 권한 미결정")
        @unknown default:
            break
        }
    }
    // MARK: - Helper Methods
    
    private func mapStateToEventType(_ state: RidingState) -> RunSession.TimelineEvent.EventType {
        switch state {
        case .riding: return .riding
        case .onLift: return .lift
        case .resting: return .rest
        }
    }
    
    /// 타임라인 표기용 상태 보정
    private func timelineState(_ state: RidingState) -> RidingState {
        return state
    }
}
