import SwiftUI
import UIKit

/// 햅틱 피드백을 간편하게 관리하는 싱글톤 클래스
class HapticManager {
    static let shared = HapticManager()
    
    private init() {}
    
    /// 알림 피드백 (성공, 경고, 에러)
    func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }
    
    /// 임팩트 피드백 (가벼움, 중간, 무거움 등)
    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
    
    /// 선택 피드백 (가장 가벼운 느낌 - 휠 돌릴 때 등)
    func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}
