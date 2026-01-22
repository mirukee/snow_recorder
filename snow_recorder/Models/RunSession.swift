import Foundation
import SwiftData

/// 스키/보드 주행 기록을 저장하는 데이터 모델
@Model
final class RunSession {
    var id: UUID
    var startTime: Date
    var endTime: Date
    var duration: TimeInterval
    var distance: Double        // 활강 거리 (m) - RIDING 상태에서만 측정됨
    var maxSpeed: Double        // 최고 속도 (km/h)
    var avgSpeed: Double        // 평균 속도 (km/h) - RIDING 상태에서만 측정됨
    var verticalDrop: Double    // 총 하강 고도 (m)
    var runCount: Int           // 런 횟수
    var slopeName: String?      // 주행한 슬로프 이름 (대표 슬로프)
    var riddenSlopes: [String: Int] // 세션 동안 탄 슬로프 목록 (이름: 횟수)
    var locationName: String    // 스키장 이름 (예: HIGH1 RESORT)
    var routeCoordinates: [[Double]] // GPS 경로 좌표 [[lat, lon], ...] - 지도 폴리라인용
    
    init(
        startTime: Date,
        endTime: Date,
        duration: TimeInterval,
        distance: Double,
        maxSpeed: Double,
        avgSpeed: Double = 0.0,
        verticalDrop: Double = 0.0,
        runCount: Int = 0,
        slopeName: String? = nil,
        riddenSlopes: [String: Int] = [:],
        locationName: String = "HIGH1 RESORT",
        routeCoordinates: [[Double]] = []
    ) {
        self.id = UUID()
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.distance = distance
        self.maxSpeed = maxSpeed
        self.avgSpeed = avgSpeed
        self.verticalDrop = verticalDrop
        self.runCount = runCount
        self.slopeName = slopeName
        self.riddenSlopes = riddenSlopes
        self.locationName = locationName
        self.routeCoordinates = routeCoordinates
    }
}
