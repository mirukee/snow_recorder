import Foundation
import SwiftUI
import Combine

/// 마이페이지 뷰모델
/// 유저 프로필 데이터 관리 및 더미 데이터 제공
class MyPageViewModel: ObservableObject {
    
    // UI와 바인딩될 유저 프로필 데이터 (GamificationProfile)
    @Published var userProfile: GamificationProfile
    
    private var cancellables = Set<AnyCancellable>()
    private var gamificationService = GamificationService.shared
    
    init() {
        // 초기값은 서비스의 현재 상태로 설정
        self.userProfile = gamificationService.profile
        
        // 서비스의 프로필 변경 사항 구독
        gamificationService.$profile
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newProfile in
                self?.userProfile = newProfile
            }
            .store(in: &cancellables)
    }
    
    /// SwiftData의 주행 기록을 바탕으로 통계 및 XP 업데이트
    /// - Parameter sessions: 저장된 주행 세션 리스트
    func updateStats(using sessions: [RunSession]) {
        // 서비스에 위임 (디바운스/백그라운드)
        gamificationService.scheduleUpdateProfile(from: sessions)
        // 랭킹 서비스에도 로컬 데이터 동기화 요청 (리더보드 기준 통계 재계산 및 업로드)
        RankingService.shared.syncAfterLocalChange(sessions: sessions)
    }
}
