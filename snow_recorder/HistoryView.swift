import SwiftUI
import SwiftData

/// 라이딩 기록 리스트 뷰 (Tab 2) - Riding History Feed Design
struct HistoryView: View {
    let neonGreen = Color(red: 107/255, green: 249/255, blue: 6/255)
    
    // SwiftData Query (최신순 정렬)
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RunSession.startTime, order: .reverse) private var sessions: [RunSession]
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 전체 배경
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // [Header]
                HStack {
                    Text("SNOW RECORD")
                        .font(.system(size: 20, weight: .black))
                        .italic()
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // Test Data Button (Debug)
                    Button(action: {
                        RunSession.createMockSession(context: modelContext)
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.trailing, 16)
                    
                    // Profile Image (Dummy)
                    Circle()
                        .fill(Color.gray)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                }
                .padding(.horizontal, 24)
                .padding(.top, 60) // 상단 여백 (SafeArea 고려)
                .padding(.bottom, 20)
                .background(Color.black.opacity(0.8)) // 헤더 배경
                
                // [Feed List]
                List {
                    if sessions.isEmpty {
                        // Empty State
                        VStack(spacing: 20) {
                            Image(systemName: "figure.skiing.downhill")
                                .font(.system(size: 60))
                                .foregroundColor(.white.opacity(0.2))
                            Text("NO RECORDS YET")
                                .font(.headline)
                                .foregroundColor(.gray)
                                .tracking(2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                            ZStack {
                                NavigationLink(destination: RunDetailView(session: session)) {
                                    EmptyView()
                                }
                                .opacity(0) // Hide default arrow
                                
                                HistoryCard(
                                    date: formatDate(session.startTime),
                                    location: session.locationName,
                                    value: String(format: "%.1f", session.maxSpeed),
                                    unit: "KM/H",
                                    imageColor: colors[index % colors.count],
                                    rotation: Double((index % 3) - 1) * 2.0, // -2, 0, 2 rotation
                                    neonGreen: neonGreen
                                )
                            }
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteSession(session)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    deleteSession(session)
                                } label: {
                                    Label("삭제하기", systemImage: "trash")
                                }
                            }
                        }
                        
                        // End of Season
                        Text("END OF LIST")
                            .font(.caption)
                            .fontWeight(.bold)
                            .tracking(2)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 20)
                            .padding(.bottom, 100)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden) // Remove default list background
                .background(Color.black)
            }
        }
        .ignoresSafeArea(.all, edges: .top) // 헤더가 상단까지 덮도록
        }
    }
    
    // 카드 배경색 팔레트
    let colors: [Color] = [.blue, .cyan, .purple, .indigo, .teal]
    
    // 날짜 포맷 헬퍼
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d" // "DEC 24"
        return formatter.string(from: date).uppercased()
    }
    
    // 삭제 함수
    private func deleteSession(_ session: RunSession) {
        withAnimation {
            modelContext.delete(session)
        }
    }
}

/// 개별 라이딩 기록 카드
struct HistoryCard: View {
    let date: String
    let location: String
    let value: String
    let unit: String
    let imageColor: Color // 실제 앱에선 ImageName or URL
    let rotation: Double
    let neonGreen: Color
    var isSession: Bool = false
    
    var body: some View {
        ZStack {
            // 1. Background Image (Placeholder)
            Rectangle()
                .fill(imageColor)
                .overlay(
                    LinearGradient(
                        colors: [.black.opacity(0.9), .clear, .black.opacity(0.2)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
            
            // 2. Content Overlay
            VStack {
                // Top Row
                HStack(alignment: .top) {
                    // Date Badge (Rotated)
                    Text(date)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .rotationEffect(.degrees(rotation))
                        .shadow(radius: 5)
                    
                    Spacer()
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        CircleButton(icon: "heart.fill")
                        if !isSession {
                            CircleButton(icon: "square.and.arrow.up")
                        }
                    }
                }
                
                Spacer()
                
                // Bottom Row
                VStack(alignment: .leading, spacing: 12) {
                    // Location Badge (Rotated)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LOCATION")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.gray)
                        Text(location)
                            .font(.system(size: 16, weight: .heavy)) // 상단보다 굵게
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(12)
                    .rotationEffect(.degrees(rotation * -1)) // 반대 방향 회전으로 재미 요소
                    
                    // Stats
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        if isSession {
                            Text("SESSION:")
                                .font(.system(size: 10, weight: .bold)) // Reduced
                                .foregroundColor(.gray)
                            Text(value)
                                .font(.system(size: 32, weight: .black)) // Reduced from 40
                                .italic()
                                .foregroundColor(neonGreen)
                        } else {
                            Text(value)
                                .font(.system(size: 48, weight: .black)) // Reduced from 60
                                .italic()
                                .tracking(-2)
                                .foregroundColor(neonGreen)
                            Text(unit)
                                .font(.system(size: 16, weight: .bold)) // Reduced from 20
                                .foregroundColor(.white)
                        }
                    }
                    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16) // Reduced padding
        }
        .frame(height: 220) // Reduced height from 500 to 220 (~2.5 items per screen)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: neonGreen.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}

struct CircleButton: View {
    let icon: String
    
    var body: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .frame(width: 40, height: 40)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
            )
            .overlay(
                Circle().stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: RunSession.self, inMemory: true)
}
