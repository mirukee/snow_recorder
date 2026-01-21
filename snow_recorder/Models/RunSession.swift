import Foundation
import SwiftData

/// 스키/보드 주행 기록을 저장하는 데이터 모델
@Model
final class RunSession {
    var id: UUID
    var startTime: Date
    var endTime: Date
    var duration: TimeInterval
    var distance: Double // 미터 단위
    var maxSpeed: Double // km/h 단위
    var locationName: String // 스키장 이름 (예: HIGH1 RESORT)
    
    init(startTime: Date, endTime: Date, duration: TimeInterval, distance: Double, maxSpeed: Double, locationName: String = "Unknown Resort") {
        self.id = UUID()
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.distance = distance
        self.maxSpeed = maxSpeed
        self.locationName = locationName
    }
}
