import Foundation
import Combine
import SwiftData

/// 녹화 상태 및 타이머를 관리하는 매니저 클래스 (Singleton)
class RecordManager: ObservableObject {
    static let shared = RecordManager()
    
    @Published var isRecording: Bool = false       // 현재 녹화 중 여부
    @Published var elapsedTime: TimeInterval = 0   // 경과 시간 (초)
    
    private var timer: Timer?
    private var startTime: Date?
    
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
            self.elapsedTime = Date().timeIntervalSince(start)
        }
    }
    
    /// 녹화 종료 & 저장
    func stopRecording(context: ModelContext) {
        guard isRecording, let start = startTime else { return }
        
        let end = Date()
        let duration = elapsedTime
        let distance = LocationManager.shared.totalDistance
        let maxSpeed = LocationManager.shared.maxSpeed
        
        // 1. 데이터 저장
        let session = RunSession(
            startTime: start,
            endTime: end,
            duration: duration,
            distance: distance,
            maxSpeed: maxSpeed,
            locationName: "HIGH1 RESORT" // 추후 LocationManager에서 지오코딩으로 가져올 수 있음
        )
        
        context.insert(session)
        
        // 2. 상태 초기화
        isRecording = false
        timer?.invalidate()
        timer = nil
        startTime = nil
        
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
