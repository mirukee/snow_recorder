import Foundation

/// 기능 플래그 관리 (런타임 토글)
struct FeatureFlags {
    private static let barometerEnabledKey = "feature.barometerEnabled"

    
    /// 기압계 기반 로직 활성화 여부
    static var barometerEnabled: Bool {
        get {
#if DEBUG
            if let value = UserDefaults.standard.object(forKey: barometerEnabledKey) as? Bool {
                return value
            }
            return false
#else
            return true
#endif
        }
        set {
#if DEBUG
            UserDefaults.standard.set(newValue, forKey: barometerEnabledKey)
#endif
        }
    }
    

}
