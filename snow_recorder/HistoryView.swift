import SwiftUI
import SwiftData
import MapKit
import UIKit

/// 라이딩 기록 리스트 뷰 (Tab 2) - Riding History Feed Design
struct HistoryView: View {
    let neonGreen = Color(red: 107/255, green: 249/255, blue: 6/255)
    
    // Manual Data Fetching for Pagination
    @Environment(\.modelContext) private var modelContext
    @State private var sessions: [RunSession] = []
    @State private var offset: Int = 0
    @State private var hasMoreData: Bool = true
    @State private var isLoading: Bool = false
    private let pageSize = 10
    
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
                        if sessions.isEmpty && !isLoading {
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
                                        session: session,
                                        rotation: Double((index % 3) - 1) * 2.0, // -2, 0, 2 rotation
                                        neonGreen: neonGreen
                                    )
                                    .onAppear {
                                        // Load more if near end
                                        if index == sessions.count - 1 && hasMoreData {
                                            loadMoreData()
                                        }
                                    }
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
                                        Label("history.delete", systemImage: "trash")
                                    }
                                }
                            }
                            
                            // Loading Indicator or End of List
                            if hasMoreData {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: neonGreen))
                                    Spacer()
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            } else {
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
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden) // Remove default list background
                    .background(Color.black)
                    .refreshable {
                        resetAndReload()
                    }
                }
            }
            .ignoresSafeArea(.all, edges: .top) // 헤더가 상단까지 덮도록
            .onAppear {
                if sessions.isEmpty {
                    loadMoreData()
                }
            }
        }
    }
    
    // MARK: - Data Loading
    private func resetAndReload() {
        sessions.removeAll()
        offset = 0
        hasMoreData = true
        loadMoreData()
    }
    
    private func loadMoreData() {
        guard !isLoading && hasMoreData else { return }
        isLoading = true
        
        // Delayed fetch to prevent ui stutter
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let descriptor = FetchDescriptor<RunSession>(
                sortBy: [SortDescriptor(\.startTime, order: .reverse)]
            )
            // SwiftData usually fetches all, but we emulate pagination by fetching counts?
            // Actually SwiftData DOES support fetchLimit and fetchOffset.
            // But we need to define descriptor inside.
            
            var fetchDescriptor = FetchDescriptor<RunSession>(
                sortBy: [SortDescriptor(\.startTime, order: .reverse)]
            )
            fetchDescriptor.fetchLimit = pageSize
            fetchDescriptor.fetchOffset = offset
            
            do {
                let newSessions = try modelContext.fetch(fetchDescriptor)
                if newSessions.count < pageSize {
                    hasMoreData = false
                }
                
                withAnimation {
                    sessions.append(contentsOf: newSessions)
                    offset += newSessions.count
                }
            } catch {
                print("❌ Fetch failed: \(error)")
            }
            
            isLoading = false
        }
    }
    
    // 삭제 함수
    private func deleteSession(_ session: RunSession) {
        withAnimation {
            if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions.remove(at: index)
            }
            modelContext.delete(session)
        }
        do {
            try modelContext.save()
        } catch {
            print("❌ RunSession 삭제 저장 실패: \(error)")
        }
        DispatchQueue.main.async {
            RankingService.shared.syncAfterLocalChange(sessions: sessions)
            GamificationService.shared.scheduleUpdateProfile(from: sessions)
        }
    }
}

/// 개별 라이딩 기록 카드
struct HistoryCard: View {
    let session: RunSession
    let rotation: Double
    let neonGreen: Color
    
    @State private var snapshotImage: UIImage? = nil
    @State private var isGenerating: Bool = false
    
    // Cached values
    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d" // "DEC 24"
        return formatter.string(from: session.startTime).uppercased()
    }
    
    var body: some View {
        ZStack {
            // 1. Map Background (Snapshot)
            Group {
                if let image = snapshotImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    // Placeholder while loading
                    Rectangle()
                        .fill(Color(white: 0.1))
                        .overlay(
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: neonGreen))
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .disabled(true) // Disable interaction
            .colorMultiply(Color(white: 0.8)) // Slightly darken map
            
            // 2. Dark Gradient Overlay (For Text Readability)
            LinearGradient(
                colors: [.black.opacity(0.95), .black.opacity(0.3), .black.opacity(0.4)],
                startPoint: .bottom,
                endPoint: .top
            )
            
            // 3. Content Overlay
            VStack {
                // Top Row
                HStack(alignment: .top) {
                    // Date Badge (Rotated)
                    Text(dateString)
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
                        CircleButton(icon: "arrow.right")
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
                        Text(session.locationName)
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(12)
                    .rotationEffect(.degrees(rotation * -1))
                    
                    // Stats (Distance)
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", session.distance / 1000.0))
                            .font(.system(size: 48, weight: .black))
                            .italic()
                            .tracking(-2)
                            .foregroundColor(neonGreen)
                        Text("KM")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: neonGreen.opacity(0.1), radius: 10, x: 0, y: 5)
        .onAppear {
            loadSnapshot()
        }
    }
    
    private func loadSnapshot() {
        // 1. Check Memory/Disk Cache
        if let cached = MapSnapshotManager.shared.loadSnapshot(for: session.id) {
            self.snapshotImage = cached
            return
        }
        
        // 2. Generate if needed
        guard !isGenerating else { return }
        isGenerating = true
        
        let coords = session.coordinates // Accessing this might be heavy if not faulted? SwiftData is lazy though.
        // Actually accessing computed property computing from routeCoordinates array.
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Pre-calculate region size based on view size (approx 350x220)
            let targetSize = CGSize(width: 360, height: 220)
            
            MapSnapshotManager.shared.generateSnapshot(coordinates: coords, routeStates: session.routeStates, size: targetSize, sessionID: session.id) { image in
                DispatchQueue.main.async {
                    self.snapshotImage = image
                    self.isGenerating = false
                }
            }
        }
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
