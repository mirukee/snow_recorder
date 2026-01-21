import Foundation
import CoreLocation
import Combine

/// 위치 정보 및 속도를 관리하는 매니저 클래스 (Singleton)
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    
    private let locationManager = CLLocationManager()
    
    @Published var speed: Double = 0.0          // 현재 속도 (km/h)
    @Published var altitude: Double = 0.0       // 현재 고도 (m)
    @Published var totalDistance: Double = 0.0  // 누적 이동 거리 (m)
    @Published var maxSpeed: Double = 0.0       // 최고 속도 (km/h)
    @Published var location: CLLocation?        // 현재 위치 좌표
    
    private var lastLocation: CLLocation?
    private var isTracking = false
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    /// 위치 매니저 초기 설정
    private func setupLocationManager() {
        locationManager.delegate = self
        // 스키 활강 시 정확한 속도 측정을 위해 높은 정확도 사용
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        // 백그라운드 위치 업데이트 허용 (스키 탈 때 주머니에 넣을 수 있음)
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false // 자동 일시정지 방지
    }
    
    /// 위치 권한 요청
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    /// 트래킹 시작
    func startTracking() {
        isTracking = true
        totalDistance = 0.0
        maxSpeed = 0.0
        lastLocation = nil
        speed = 0.0
        locationManager.startUpdatingLocation()
    }
    
    /// 트래킹 종료
    func stopTracking() {
        isTracking = false
        locationManager.stopUpdatingLocation()
        // 속도 초기화
        speed = 0.0
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }
        
        // 유효하지 않은 속도는 무시 (음수)
        if newLocation.speed >= 0 {
            // m/s -> km/h 변환
            let currentSpeedKmH = newLocation.speed * 3.6
            self.speed = currentSpeedKmH
            
            // 최고 속도 갱신 (트래킹 중일 때만)
            if isTracking && currentSpeedKmH > maxSpeed {
                maxSpeed = currentSpeedKmH
            }
        } else {
            self.speed = 0.0
        }
        
        self.altitude = newLocation.altitude
        self.location = newLocation
        
        // 트래킹 중일 때만 거리 계산
        if isTracking, let previous = lastLocation {
            let distance = newLocation.distance(from: previous)
            totalDistance += distance
        }
        
        lastLocation = newLocation
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
}
