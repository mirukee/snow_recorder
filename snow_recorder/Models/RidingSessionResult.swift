import Foundation

/// 라이딩 세션 종료 시 반환되는 분석 결과 모델
struct RidingSessionResult {
    /// 엣지 점수 (0~100)
    var edgeScore: Int
    /// 플로우 점수 (0~100)
    var flowScore: Int
    /// 세션 최대 G-포스 (G 단위)
    var maxGForce: Double
    /// 세션 평균 속도 (m/s 단위)
    var averageSpeed: Double
    /// 세션 최고 속도 (m/s 단위)
    var maxSpeed: Double
    /// 좌/우 턴 비율 (0.0~1.0)
    var leftTurnRatio: Double
    var rightTurnRatio: Double
}
