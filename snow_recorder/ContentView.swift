import SwiftUI
import SwiftData

/// 메인 진입점 뷰 (Custom Floating Tab Bar 적용)
struct ContentView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @Environment(\.modelContext) var modelContext
    @State private var selection = 0
    
    // 네온 그린 컬러 (#6bf906)
    let neonGreen = Color(red: 107/255, green: 249/255, blue: 6/255)
    
    // 탭바 숨기기 위한 초기화
    init() {
        UITabBar.appearance().isHidden = true
    }
    
    var body: some View {
        Group {
            if authManager.user != nil || authManager.isGuest {
                mainTabView
                    .onAppear {
                        // Inject context
                        authManager.modelContext = modelContext
                    }
            } else {
                LoginView()
            }
        }
    }
    
    var mainTabView: some View {
        ZStack(alignment: .bottom) {
            // 1. 메인 컨텐츠 (TabView)
            TabView(selection: $selection) {
                DashboardView()
                    .tag(0)
                
                HistoryView()
                    .tag(1)
                
                RankingView(isActive: selection == 2)
                    .tag(2)
                
                ProfileView(isActive: selection == 3)
                    .tag(3)
            }
            .ignoresSafeArea() // 전체 화면 사용
            
            // 2. Custom Floating Tab Bar
            HStack(spacing: 8) {
                // Tab 0: Record (Dashboard)
                TabButton(icon: "record.circle", isSelected: selection == 0) {
                    selection = 0
                }
                
                // Tab 1: Feed (History)
                TabButton(icon: "list.bullet", isSelected: selection == 1) { // grid_view 대용
                    selection = 1
                }
                
                // Tab 2: Ranking
                TabButton(icon: "trophy", isSelected: selection == 2) {
                    selection = 2
                }
                
                // Tab 3: Profile (Settings)
                TabButton(icon: "person", isSelected: selection == 3) {
                    selection = 3
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                Color(red: 23/255, green: 35/255, blue: 15/255).opacity(0.9) // #17230f
            )
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
            .padding(.bottom, 30) // 화면 하단에서 띄움
        }
        .onAppear {
            // 프로 기능 임시 활성화 (런칭 전 제거)
            FeatureFlags.proFeaturesEnabled = true
        }
    }
    
}

/// 커스텀 탭 버튼
struct TabButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    let neonGreen = Color(red: 107/255, green: 249/255, blue: 6/255)
    
    var body: some View {
        Button(action: action) {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(neonGreen)
                        .frame(width: 50, height: 50)
                        .shadow(color: neonGreen.opacity(0.4), radius: 10)
                }
                
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? .black : .white.opacity(0.5))
            }
            .frame(width: 50, height: 50)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: RunSession.self, inMemory: true)
}
