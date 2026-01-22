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
    
    private init() {}
    
    /// 녹화 시작
    func startRecording() {
        guard !isRecording else { return }
        
        isRecording = true
        elapsedTime = 0
        startTime = Date()
        
        // LocationManager 트래킹 시작
        LocationManager.shared.startTracking()
        
        // 1초 단위 타이머 시작
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.startTime else { return }
            
            if !self.isPaused {
                self.elapsedTime = Date().timeIntervalSince(start) - self.totalPausedDuration
            }
        }
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
        
        let end = Date()
        let duration = elapsedTime
        
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
        
        // 1. 데이터 저장
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
            routeCoordinates: routeCoordinates
        )
        
        context.insert(session)
        try? context.save()
        
        // 2. 상태 초기화
        isRecording = false
        isPaused = false
        timer?.invalidate()
        timer = nil
        startTime = nil
        pauseTime = nil
        totalPausedDuration = 0
        
        // LocationManager 트래킹 종료
        LocationManager.shared.stopTracking()
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
