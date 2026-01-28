import Foundation

/// 기능 플래그 관리 (런타임 토글)
struct FeatureFlags {
    private static let barometerEnabledKey = "feature.barometerEnabled"
    private static let proFeaturesEnabledKey = "feature.proFeaturesEnabled"
    
    /// 기압계 기반 로직 활성화 여부
    static var barometerEnabled: Bool {
        get {
            if let value = UserDefaults.standard.object(forKey: barometerEnabledKey) as? Bool {
                return value
            }
            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: barometerEnabledKey)
        }
    }
    
    /// 프로 기능(3D/히트맵 등) 임시 활성화 플래그
    static var proFeaturesEnabled: Bool {
        get {
            if let value = UserDefaults.standard.object(forKey: proFeaturesEnabledKey) as? Bool {
                return value
            }
            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: proFeaturesEnabledKey)
        }
    }
}
