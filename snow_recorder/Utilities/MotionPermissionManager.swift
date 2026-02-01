import CoreMotion
import Foundation

/// 모션/피트니스 권한 트리거용 매니저
final class MotionPermissionManager {
    static let shared = MotionPermissionManager()
    private let activityManager = CMMotionActivityManager()
    private let activityQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "MotionPermissionManager.queue"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    
    private init() {}
    
    /// 모션 권한 요청 트리거 (가능한 경우에만)
    func requestIfNeeded() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        
        let status = CMMotionActivityManager.authorizationStatus()
        guard status == .notDetermined else { return }
        
        let now = Date()
        activityManager.queryActivityStarting(from: now, to: now, to: activityQueue) { [weak self] _, _ in
            // 1회 호출로 권한 다이얼로그 트리거 후 즉시 정리
            self?.activityManager.stopActivityUpdates()
        }
    }
}
