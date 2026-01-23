import Foundation
import CoreLocation
import Combine

/// 위치 정보 및 속도를 관리하는 매니저 클래스 (Singleton)
/// 상태 기반 측정 시스템으로 배터리 효율 최적화
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    
    private let locationManager = CLLocationManager()
    
    // MARK: - Published Properties (실시간 데이터)
    @Published var speed: Double = 0.0              // 현재 속도 (km/h)
    @Published var altitude: Double = 0.0           // 현재 고도 (m)
    @Published var totalDistance: Double = 0.0      // 누적 활강 거리 (m) - RIDING 상태에서만
    @Published var maxSpeed: Double = 0.0           // 최고 속도 (km/h)
    @Published var location: CLLocation?            // 현재 위치 좌표
    
    // MARK: - 추가된 메트릭
    @Published var verticalDrop: Double = 0.0       // 총 하강 고도 (m) - RIDING 상태에서만
    @Published var currentSlope: Slope?             // 현재 인식된 슬로프
    @Published var currentState: RidingState = .resting  // 현재 활동 상태
    @Published var avgSpeed: Double = 0.0           // 평균 속도 (km/h)
    @Published var runCount: Int = 0                // 런 횟수
    @Published var sessionSlopeCounts: [String: Int] = [:] // 세션 동안 탄 슬로프별 횟수
    @Published var routeCoordinates: [[Double]] = [] // GPS 경로 좌표 [[lat, lon], ...]
    @Published var routeSpeeds: [Double] = [] // GPS 경로별 속도 (km/h)
    @Published var runStartIndices: [Int] = [0] // 각 런 시작 인덱스
    @Published var timelineEvents: [RunSession.TimelineEvent] = [] // 타임라인 이벤트 목록
    
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
    
    // MARK: - 상태 전환 임계값 (튜닝 가능)
    private let ridingSpeedThreshold: Double = 5.0      // 활강 판정 최소 속도 (km/h)
    private let pauseSpeedThreshold: Double = 3.0       // 정지 판정 속도 (km/h)
    private let stateChangeDebounce: TimeInterval = 5.0 // 상태 전환 debounce (초)
    private let slopeCheckDistance: Double = 50.0       // 슬로프 체크 최소 이동 거리 (m)
    private let pointHitRadius: Double = 50.0           // 시작/종료점 통과 판정 반경 (m)
    private let minVerticalDrop: Double = 1.0           // 최소 하강 고도 (GPS 노이즈 필터)
    private let longRestDuration: TimeInterval = 300.0  // 5분 이상 정지 시 강제 RESTING
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    /// 위치 매니저 초기 설정
    private func setupLocationManager() {
        locationManager.delegate = self
        // 초기 정확도: 절전 모드
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // 백그라운드 위치 업데이트 허용 (스키 탈 때 주머니에 넣을 수 있음)
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false // 자동 일시정지 방지
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
    }
    
    /// 트래킹 일시 정지 (데이터 유지)
    func pauseTracking() {
        isTracking = false
        locationManager.stopUpdatingLocation()
    }
    
    /// 트래킹 재개 (데이터 유지)
    func resumeTracking() {
        isTracking = true
        locationManager.startUpdatingLocation()
    }
    
    /// 트래킹 종료
    func stopTracking() {
        isTracking = false
        locationManager.stopUpdatingLocation()
        speed = 0.0
        
        // 마지막 런이 진행 중이었다면 카운트 및 슬로프 확정
        if currentState == .riding {
            runCount += 1
            if let bestSlope = calculateBestSlope() {
                print("🏁 트래킹 종료로 인한 최종 슬로프 확정: \(bestSlope.name)")
                currentSlope = bestSlope
                sessionSlopeCounts[bestSlope.name, default: 0] += 1
            }
            visitedSlopeCounts.removeAll()
            visitedSlopeStartHits.removeAll()
            visitedSlopeFinishHits.removeAll()
        }
        
        // 평균 속도 최종 계산
        calculateAvgSpeed()
        
        // 마지막 이벤트 기록
        if let start = currentTimelineEventStart {
            let now = Date()
            var detail = currentState.displayLabel
            if currentState == .riding {
               detail = currentSlope?.name ?? "알 수 없는 슬로프"
            }
            let event = RunSession.TimelineEvent(type: mapStateToEventType(currentState), startTime: start, endTime: now, detail: detail)
            timelineEvents.append(event)
        }
        currentTimelineEventStart = nil
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
        runStartIndices = [0]
        timelineEvents.removeAll()
        currentTimelineEventStart = nil
    }
    
    // MARK: - 상태 기반 GPS 정확도 조절 (배터리 최적화)
    
    private func updateLocationAccuracy(for state: RidingState) {
        switch state {
        case .riding:
            // 활강 중: 최고 정확도 필요
            locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        case .paused:
            // 슬로프 내 휴식: 중간 정확도
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        case .onLift:
            // 리프트: 저전력 모드
            locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        case .resting:
            // 휴식: 기본적으론 최저 전력이지만, 슬로프 출발 지점 대기일 수 있으므로
            // 슬로프 내부라면 중간 정확도 유지
            if let loc = location, SlopeDatabase.shared.isInsideAnySlope(loc) {
                locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            } else {
                locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            }
        }
    }
    
    // MARK: - 상태 전환 로직
    
    private func determineState(currentLocation: CLLocation, previousLocation: CLLocation?) -> RidingState {
        let currentSpeedKmH = max(0, currentLocation.speed * 3.6)
        let isInsideSlope = SlopeDatabase.shared.isInsideAnySlope(currentLocation)
        let isNearLift = SlopeDatabase.shared.isNearLiftLine(currentLocation)
        
        // 고도 변화 계산 및 트렌드 분석
        altitudeHistory.append(currentLocation.altitude)
        if altitudeHistory.count > 12 { // 최근 12개의 샘플 유지 (약 10~15초)
            altitudeHistory.removeFirst()
        }
        
        let altitudeChange: Double
        if let prev = previousLocation {
            altitudeChange = prev.altitude - currentLocation.altitude // 양수 = 하강
        } else {
            altitudeChange = 0
        }
        
        // Robust Descent Detection (안정적인 하강 감지)
        // 로직: 순간적인 변화(0.5m) 또는 최근 샘플 기준 누적 1.5m 이상 하강
        let isDescending: Bool
        if let first = altitudeHistory.first, let last = altitudeHistory.last, altitudeHistory.count >= 3 {
             isDescending = (first - last) > 1.5
        } else {
             isDescending = altitudeChange > 0.5
        }
        
        // Robust Ascent Detection (리프트 탑승 감지)
        // 로직: 최근 10초간 5m 이상 상승 (약 0.5m/s 이상 수직 상승)
        // Issue #5 수정: 리프트 초기 저속 구간 대응을 위해 임계값 완화 (8m → 5m)
        let isClimbing: Bool
        if let first = altitudeHistory.first, let last = altitudeHistory.last, altitudeHistory.count >= 10 {
            isClimbing = (last - first) > 5.0
        } else {
            isClimbing = false
        }
        
        // Robust Strong Descent (강력한 하강 감지 - 리프트 오인식 방지용)
        // 로직: 최근 10초간 5m 이상 하강 (리프트 꿀렁임 무시 + 초보자 인식 가능)
        // 10m(초보자 인식 불가) -> 5m(초보자 10km/h 인식 가능)로 완화
        let isStrongDescent: Bool
        if let first = altitudeHistory.first, let last = altitudeHistory.last, altitudeHistory.count >= 10 {
            isStrongDescent = (first - last) > 5.0
        } else {
            isStrongDescent = false
        }
        
        // 슬로프 이탈 타이머 관리
        if isInsideSlope {
            outOfSlopeStartTime = nil
        } else if outOfSlopeStartTime == nil {
            outOfSlopeStartTime = Date()
        }
        
        // 슬로프 이탈 지속 시간 계산
        let outOfSlopeDuration: TimeInterval
        if let start = outOfSlopeStartTime {
            outOfSlopeDuration = Date().timeIntervalSince(start)
        } else {
            outOfSlopeDuration = 0
        }
        
        // 30초 이상 이탈 시 강제 종료
        let isLongOutOfSlope = outOfSlopeDuration > 30.0
        
        // 상태 판정 로직
        switch currentState {
        case .resting:
            // RESTING → RIDING: 슬로프 내부 + 속도↑ + 하강 중
            if isInsideSlope && currentSpeedKmH > ridingSpeedThreshold && isDescending {
                return .riding
            }
            // RESTING → ON_LIFT: 리프트 라인 근처 OR 확실한 상승 중
            // (좌표 데이터가 없어도 물리적인 상승 트렌드로 감지)
            if (isNearLift && altitudeChange < -1.0) || (currentSpeedKmH > 3.0 && isClimbing) {
                return .onLift
            }
            return .resting
            
        case .riding:
            // RIDING → PAUSED: 슬로프 내부 + 저속 (debounce 적용)
            if isInsideSlope && currentSpeedKmH < pauseSpeedThreshold {
                if canChangeState() {
                    return .paused
                }
            } else {
                // 속도가 다시 올라가면 debounce 리셋
                stateChangeTime = nil
            }
            // RIDING → RESTING: 슬로프 외부 30초 이상 지속
            if isLongOutOfSlope {
                 return .resting
            }
            return .riding
            
        case .paused:
            // PAUSED → RIDING: 속도 증가
            if currentSpeedKmH > ridingSpeedThreshold {
                stateChangeTime = nil
                return .riding
            }
            // PAUSED → RESTING: 슬로프 외부 30초 이상 지속
            if isLongOutOfSlope {
                return .resting
            }
            // 5분 이상 정지 시 강제 RESTING
            if let changeTime = stateChangeTime,
               Date().timeIntervalSince(changeTime) > longRestDuration {
                return .resting
            }
            return .paused
            
        case .onLift:
            // ON_LIFT → RESTING: 리프트 정상 도착
            // Issue #3/#4 수정: !isNearLift 조건 제거 (좌표 데이터 없음), !isClimbing 조건 추가
            // 조건: 저속 + 상승 중이 아님 (리프트 하차 완료)
            if currentSpeedKmH < pauseSpeedThreshold && !isClimbing {
                if canChangeState() {
                    return .resting
                }
            } else {
                // 속도 또는 상승 중이면 debounce 리셋
                stateChangeTime = nil
            }
            // ON_LIFT → RIDING: 리프트에서 바로 활강 시작 (드문 경우)
            // 리프트의 일시적 하강 구간 오인식 방지를 위해 isStrongDescent(5m 하강) 적용
            if isInsideSlope && currentSpeedKmH > ridingSpeedThreshold && isStrongDescent {
                return .riding
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
    private func handleStateChange(from oldState: RidingState, to newState: RidingState) {
        // 상태가 변경되었을 때만 처리
        guard oldState != newState else { return }
        
        // 타임라인 이벤트 기록
        let now = Date()
        if let start = currentTimelineEventStart {
            var detail = oldState.displayLabel
            if oldState == .riding {
                // 이 시점에서는 아직 visitedSlopeCounts가 초기화되지 않았으므로 calculateBestSlope 호출 가능
                // 다만 calculateBestSlope는 무거운 연산일 수 있으므로 주의.
                // handleStateChange 내부 로직상 resting으로 갈때만 calculateBestSlope를 호출하긴 함.
                // 여기서는 간단히 currentSlope 쓰거나 calculateBestSlope 사용
                if let best = calculateBestSlope() {
                    detail = best.name
                } else {
                    detail = "알 수 없는 슬로프"
                }
            } else if oldState == .onLift {
                detail = "리프트 이동"
            } else if oldState == .resting {
                detail = "휴식"
            }
            
            // RunSession.TimelineEvent 생성
            // EventType 매핑 필요
            let type = mapStateToEventType(oldState)
            let event = RunSession.TimelineEvent(type: type, startTime: start, endTime: now, detail: detail)
            timelineEvents.append(event)
            print("⏱️ 타임라인 이벤트 추가: \(detail) (\(Int(now.timeIntervalSince(start)))초)")
        }
        currentTimelineEventStart = now
        
        // GPS 정확도 조절
        updateLocationAccuracy(for: newState)
        
        // 점수 분석기 상태 동기화
        RidingMetricAnalyzer.shared.updateState(newState)
        FlowScoreAnalyzer.shared.updateState(newState)
        
        // 런 카운트: RIDING → (RESTING) 전환 시 +1
        // NOTE: 리프트 탑승 로직 개선(점선 표시)을 위해, RIDING이 시작될 때 인덱스를 기록해야 함.
        if newState == .riding {
             // 새로운 런 시작: 현재 좌표 배열의 끝을 시작 인덱스로 기록
             // (단, 첫 런(0)은 이미 초기화 시 들어가있으므로, 좌표가 쌓인 상태에서 다시 riding 될 때만 추가)
             if !routeCoordinates.isEmpty {
                 runStartIndices.append(routeCoordinates.count)
                 print("🛤️ 새로운 런 시작 인덱스 기록: \(routeCoordinates.count)")
             }
        }

        if oldState == .riding && newState == .resting {
            runCount += 1
            // 런 종료 시, 방문했던 슬로프 중 가장 우선순위가 높은 슬로프를 최종 슬로프로 확정
            if let bestSlope = calculateBestSlope() {
                print("🏁 런 종료. 최종 슬로프 확정: \(bestSlope.name)")
                currentSlope = bestSlope
                
                // 세션 통계에 추가
                sessionSlopeCounts[bestSlope.name, default: 0] += 1
            }
            visitedSlopeCounts.removeAll()
            visitedSlopeStartHits.removeAll()
            visitedSlopeFinishHits.removeAll()
        }
        
        // debounce 타이머 리셋
        stateChangeTime = nil
        
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
        
        // 트래킹 중일 때만 상세 처리
        guard isTracking else {
            lastLocation = newLocation
            return
        }
        
        // 1. 상태 결정
        let newState = determineState(currentLocation: newLocation, previousLocation: lastLocation)
        if newState != currentState {
            handleStateChange(from: currentState, to: newState)
            currentState = newState
        }
        
        // 점수 분석기 위치 업데이트 (상태는 내부에서 필터링)
        RidingMetricAnalyzer.shared.updateLocation(newLocation)
        FlowScoreAnalyzer.shared.updateLocation(newLocation)
        
        // 2. RIDING 상태에서만 메트릭 측정
        if currentState == .riding, let previous = lastLocation {
            // 거리 누적
            let distance = newLocation.distance(from: previous)
            totalDistance += distance
            
            // Vertical Drop 누적 (하강만, 최소 1m 이상)
            let altitudeDiff = previous.altitude - newLocation.altitude
            if altitudeDiff > minVerticalDrop {
                verticalDrop += altitudeDiff
            }
            
            // 최고 속도 갱신
            if speed > maxSpeed {
                maxSpeed = speed
            }
            
            // 평균 속도 샘플 수집
            if speed > ridingSpeedThreshold {
                speedSamples.append(speed)
                calculateAvgSpeed()
            }
            
            // GPS 경로 수집 (5m마다 - 배터리/데이터 최적화)
            if distance >= 5.0 || routeCoordinates.isEmpty {
                routeCoordinates.append([newLocation.coordinate.latitude, newLocation.coordinate.longitude])
                routeSpeeds.append(max(0, newLocation.speed * 3.6)) // 속도 함께 저장
            }
        }

        
        // 3. 슬로프 인식 및 Start/Finish 감지 (배터리 최적화: 일정 거리 이동 시마다)
        // Issue #6 수정: 출발 지점 대기 중(Resting/Paused)에도 Start Point를 인식할 수 있도록 조건 완화
        // 단, Finish Point는 활강 중에만 인식하는 것이 안전함.
        if (currentState == .riding || currentState == .paused || currentState == .resting) && shouldCheckSlope(at: newLocation) {
            
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
                // Start(Top) Check: Riding, Paused, Resting 모두 허용 (출발 전 대기 포함)
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
        
        lastLocation = newLocation
    }
    
    /// 슬로프 체크 필요 여부 (배터리 최적화)
    private func shouldCheckSlope(at location: CLLocation) -> Bool {
        guard let lastCheck = lastSlopeCheckLocation else { return true }
        return location.distance(from: lastCheck) >= slopeCheckDistance
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
        case .paused: return .pause
        }
    }
}
