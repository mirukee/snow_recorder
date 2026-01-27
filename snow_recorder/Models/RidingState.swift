import Foundation

/// 사용자의 현재 활동 상태를 나타내는 열거형
/// 상태에 따라 측정 로직이 달라짐
enum RidingState: String, Codable {
    /// 슬로프 활강 중 - verticalDrop, distance, speed 측정 활성화
    case riding = "RIDING"
    
    /// 리프트 탑승 중 - 모든 측정 중지
    case onLift = "ON_LIFT"
    
    /// 슬로프 외부 휴식 - 런 종료 시 런 카운트 증가
    case resting = "RESTING"
    
    /// UI 표시용 한글 라벨
    var displayLabel: String {
        switch self {
        case .riding: return "활강 중"
        case .onLift: return "리프트"
        case .resting: return "대기 중"
        }
    }
    
    /// 상태별 아이콘 (SF Symbols)
    var iconName: String {
        switch self {
        case .riding: return "figure.skiing.downhill"
        case .onLift: return "cablecar.fill"
        case .resting: return "cup.and.saucer.fill"
        }
    }
    
    // 이전 버전의 PAUSED 값을 안전하게 RESTING으로 매핑
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self)) ?? ""
        switch rawValue {
        case "RIDING":
            self = .riding
        case "ON_LIFT":
            self = .onLift
        case "RESTING":
            self = .resting
        case "PAUSED":
            self = .resting
        default:
            self = .resting
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}
