import SwiftUI
import SwiftData
import AuthenticationServices

struct RankingView: View {
    // MARK: - Colors
    let neonGreen = Color(red: 107/255, green: 249/255, blue: 6/255) // #6bf906
    let backgroundDark = Color.black
    let surfaceDark = Color(white: 0.05)
    let glassDark = Color.white.opacity(0.05)
    
    // MARK: - Enums (Local)
    enum RankingMode {
        case technical
        case mileage
    }

    // MARK: - State
    @State private var rankingMode: RankingMode = .technical // Default to Technical
    @State private var selectedScope: RankingScope = .individual
    @State private var selectedResort: String = "전체"
    @State private var selectedMetric: RankingMetric = .runCount
    @State private var selectedCycle: RankingCycle = .season
    @ObservedObject private var rankingService = RankingService.shared
    @StateObject private var authManager = AuthenticationManager.shared
    @Query(sort: \RunSession.startTime, order: .reverse) private var sessions: [RunSession]
    let isActive: Bool
    
    // MARK: - Models (Using RankingModels.swift)
    
    // Mock Data (Resorts)
    let resorts = ["전체", "하이원", "용평", "휘닉스", "비발디"]
    
    @State private var showingScoreInfo = false
    @State private var selectedUser: LeaderboardEntry? = nil
    @State private var showSyncHelp = false
    
    var body: some View {
        Group {
            if authManager.isGuest {
                guestRankingView
            } else {
                ZStack {
                    // ... (rest of background)
                    // Background
                    backgroundDark.ignoresSafeArea()
                    
                    // Grid Effect (Optional subtle background)
                    VStack {
                        Spacer()
                        HStack { Spacer() }
                    }
                    .background(
                        GeometryReader { geometry in
                            Path { path in
                                let step: CGFloat = 40
                                for x in stride(from: 0, to: geometry.size.width, by: step) {
                                    path.move(to: CGPoint(x: x, y: 0))
                                    path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                                }
                                for y in stride(from: 0, to: geometry.size.height, by: step) {
                                    path.move(to: CGPoint(x: 0, y: y))
                                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                                }
                            }
                            .stroke(Color.white.opacity(0.03), lineWidth: 1)
                        }
                    )
                    .mask(LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .ignoresSafeArea()
                    
                    VStack(spacing: 0) {
                        // MARK: - Main Content with Collapsing Header
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                                
                                // 1. Scrollable Header Content (Filters)
                                VStack(spacing: 0) {
                                    headerView
                                    
                                    modeSwitcher
                                        .padding(.top, 10)
                                        .padding(.bottom, 20)
                                    
                                    // Filters Container
                                    VStack(spacing: 16) {
                                        // Resort Filter (Only for Mileage Mode)
                                        if rankingMode == .mileage {
                                            resortFilterScroll
                                                .transition(.move(edge: .top).combined(with: .opacity))
                                            
                                            if let updatedAt = rankingService.lastLeaderboardUpdatedAt {
                                                Text("UPDATED \(formattedUpdateTime(updatedAt))")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundColor(.gray)
                                            }
                                            
                                        } else {
                                            // Technical Mode: Show Global Label or nothing (clean look)
                                            VStack(spacing: 4) {
                                                Text("NATIONAL RANKING")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .tracking(2)
                                                    .foregroundColor(neonGreen.opacity(0.7))
                                                
                                                if let updatedAt = rankingService.lastLeaderboardUpdatedAt {
                                                    Text("UPDATED \(formattedUpdateTime(updatedAt))")
                                                        .font(.system(size: 9, weight: .bold))
                                                        .foregroundColor(.gray)
                                                }
                                            }
                                            .padding(.bottom, 8)
                                        }
                                        
                                        metricTabs
                                    }
                                    .padding(.bottom, 24)
                                }
                                
                                // 2. Section with Sticky Header (My Ranking)
                                Section(header: stickyHeader) {
                                    VStack(spacing: 0) {
                                        // Podium
                                        podiumSection
                                            .padding(.top, 24)
                                            .padding(.bottom, 32)
                                        
                                        // Ranking List
                                        rankingListView
                                            .padding(.bottom, 40)
                                    }
                                }
                            }
                        }
                    }
                }
                
                if rankingService.isLoadingLeaderboard {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: neonGreen))
                        .scaleEffect(1.5)
                }
                
                // Debug / Empty State
                if let error = rankingService.lastErrorMessage {
                    VStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(10)
                } else if rankingService.leaderboard.isEmpty && !rankingService.isLoadingLeaderboard {
                    Text("NO DATA FOUND")
                        .font(.headline)
                        .foregroundColor(.gray)
                        .padding()
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // 앱 시작 시 또는 뷰 진입 시 기존 데이터를 기반으로 랭킹 통계 재계산 및 로드
            guard isActive, !authManager.isGuest else { return }
            rankingService.scheduleRecalculateStats(from: sessions)
            if rankingMode == .technical && (selectedMetric == .runCount || selectedMetric == .distance) {
                selectedMetric = .edge
            }
            rankingService.fetchLeaderboard(cycle: selectedCycle, metric: selectedMetric, scope: selectedScope, resortKey: selectedResortKey)
        }
        .onChange(of: sessions) { _, newSessions in
            guard isActive, !authManager.isGuest else { return }
            rankingService.scheduleRecalculateStats(from: newSessions)
        }
        .onChange(of: isActive) { _, active in
            guard active, !authManager.isGuest else { return }
            rankingService.scheduleRecalculateStats(from: sessions)
            if rankingMode == .technical && (selectedMetric == .runCount || selectedMetric == .distance) {
                selectedMetric = .edge
            }
            rankingService.fetchLeaderboard(cycle: selectedCycle, metric: selectedMetric, scope: selectedScope, resortKey: selectedResortKey)
        }
        // Filters Change Trigger
        .onChange(of: selectedCycle) { _, _ in fetch() }
        .onChange(of: selectedMetric) { _, _ in fetch() }
        .onChange(of: selectedResort) { _, _ in fetch() }
        .sheet(item: $selectedUser) { user in
            OtherUserProfileView(user: user)
        }
        .sheet(isPresented: $showSyncHelp) {
            syncHelpSheet
        }
        // .onChange(of: selectedScope) { _, _ in fetch() } // Removed
    }
    
    private func fetch() {
        guard isActive, !authManager.isGuest else { return }
        rankingService.fetchLeaderboard(cycle: selectedCycle, metric: selectedMetric, scope: selectedScope, resortKey: selectedResortKey)
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: {}) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.white)
                        .font(.system(size: 20, weight: .semibold))
                }
                
                Spacer()
                
                Text("LEADERBOARD")
                    .font(.system(size: 20, weight: .heavy))
                    .tracking(4)
                    .foregroundColor(.white)
                    .shadow(color: .white.opacity(0.5), radius: 10)
                
                Spacer()
                
                HStack(spacing: 12) {
                    let remainingSync = rankingService.manualSyncRemainingCount()
                    let canSync = remainingSync > 0
                    Text("\(remainingSync)/2")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(canSync ? neonGreen.opacity(0.9) : .gray)
                    Button(action: {
                        guard canSync else { return }
                        _ = rankingService.manualSync(
                            sessions: sessions,
                            cycle: selectedCycle,
                            metric: selectedMetric,
                            scope: selectedScope,
                            resortKey: selectedResortKey
                        )
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundColor(canSync ? neonGreen : .gray)
                            .font(.system(size: 20, weight: .bold))
                    }
                    .opacity(canSync ? 1 : 0.4)
                    
                    Button(action: {}) {
                        Image(systemName: "gearshape") // Moved actual logic to ProfileView
                            .foregroundColor(.white.opacity(0.3)) // Dimmed here
                            .font(.system(size: 20, weight: .semibold))
                    }
                }
            }
            
            // Cycle Switcher (Season / Weekly)
            HStack(spacing: 0) {
                ForEach(RankingCycle.allCases) { cycle in
                    Button(action: { withAnimation { selectedCycle = cycle } }) {
                        Text(cycle.displayName)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(selectedCycle == cycle ? .black : .gray)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(selectedCycle == cycle ? neonGreen : Color.clear)
                            .cornerRadius(12)
                    }
                }
            }
            .padding(2)
            .background(Color.white.opacity(0.1))
            .cornerRadius(14)
            .padding(.horizontal, 48)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 20)
    }
    
    private var resortFilterScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(resorts, id: \.self) { resort in
                    Button(action: {
                        withAnimation {
                            selectedResort = resort
                        }
                    }) {
                        Text(resort)
                            .font(.system(size: 12, weight: .bold))
                            .textCase(.uppercase)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                selectedResort == resort ? neonGreen : Color.white.opacity(0.05)
                            )
                            .foregroundColor(
                                selectedResort == resort ? .black : .gray
                            )
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }
    private var modeSwitcher: some View {
        HStack(spacing: 0) {
            modeButton(title: "TECHNICAL", mode: .technical, icon: "flame.fill")
            modeButton(title: "MILEAGE", mode: .mileage, icon: "figure.skiing.downhill")
        }
        .padding(4)
        .background(Color.white.opacity(0.1))
        .cornerRadius(16)
        .padding(.horizontal, 24)
    }
    
    private func modeButton(title: String, mode: RankingMode, icon: String) -> some View {
        Button(action: {
            withAnimation(.spring()) {
                rankingMode = mode
                // Set default metric for mode
                if mode == .technical {
                    selectedMetric = .edge
                    selectedResort = "전체" // Reset resort filter for technical
                } else {
                    selectedMetric = .runCount
                }
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 14, weight: .heavy))
            .foregroundColor(rankingMode == mode ? .black : .gray)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                rankingMode == mode ? neonGreen : Color.clear
            )
            .cornerRadius(12)
        }
    }
    
    private var metricTabs: some View {
        HStack(spacing: 20) {
            if rankingMode == .technical {
                HStack(spacing: 20) {
                    metricTabButton(title: "EDGE SCORE", icon: "arrow.triangle.merge", metric: .edge)
                    metricTabButton(title: "FLOW SCORE", icon: "wind", metric: .flow)
                }
                
                // Info Button
                Button(action: { showingScoreInfo = true }) {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundColor(neonGreen.opacity(0.8))
                        .font(.system(size: 20))
                }
            } else {
                metricTabButton(title: "RUNS", icon: "figure.run", metric: .runCount)
                metricTabButton(title: "DISTANCE", icon: "chart.xyaxis.line", metric: .distance)
            }
        }
        .padding(.horizontal, 24)
        .alert(isPresented: $showingScoreInfo) {
            Alert(
                title: Text("ranking.tech_guide_title"),
                message: Text("ranking.tech_guide_body"),
                dismissButton: .default(Text("ranking.tech_guide_ok"))
            )
        }
    }
    
    private func metricTabButton(title: String, icon: String, metric: RankingMetric) -> some View {
        Button(action: { selectedMetric = metric }) {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                    Text(title)
                }
                .font(.system(size: 10, weight: .bold)) // Slighly smaller to fit 4
                .foregroundColor(selectedMetric == metric ? neonGreen : .gray)
                
                // Active Indicator
                Rectangle()
                    .fill(selectedMetric == metric ? neonGreen : Color.clear)
                    .frame(height: 2)
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    private var podiumSection: some View {
        let topThree = Array(rankingService.leaderboard.prefix(3))
        // Ensure we have at least 3 items for the podium to look good, otherwise handle gracefully
        
        return HStack(alignment: .bottom, spacing: 16) {
            // Rank 2 (Left)
            if topThree.count >= 2 {
                podiumUser(rank: 2, entry: topThree[1], scale: 0.9)
            } else {
                 Spacer().frame(width: 100)
            }
            
            // Rank 1 (Center)
            if topThree.count >= 1 {
                podiumUser(rank: 1, entry: topThree[0], scale: 1.1)
                    .zIndex(1)
            }
            
            // Rank 3 (Right)
            if topThree.count >= 3 {
                podiumUser(rank: 3, entry: topThree[2], scale: 0.9)
            } else {
                 Spacer().frame(width: 100)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
    }
    
    private func podiumUser(rank: Int, entry: LeaderboardEntry, scale: CGFloat) -> some View {
        let color: Color = rank == 1 ? neonGreen : (rank == 2 ? .gray : Color(red: 205/255, green: 127/255, blue: 50/255))
        let valueStr = formattedLeaderboardValue(entry.value, metric: entry.metric)
        
        return Button(action: { selectedUser = entry }) {
            VStack(spacing: 8) {
                Text(rank == 1 ? "CHAMPION" : "RANK \(rank)")
                    .font(.system(size: 10, weight: .black))
                    .tracking(2)
                    .foregroundColor(color)
                
                ZStack {
                    if rank == 1 {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 28))
                            .foregroundColor(color)
                            .offset(y: -54)
                            .shadow(color: color, radius: 10)
                    }
                    
                    Circle()
                        .stroke(color, lineWidth: 3)
                        .background(Circle().fill(Color.black))
                        .frame(width: 80, height: 80)
                        .shadow(color: color.opacity(0.5), radius: 15)
                    
                    // Placeholder Avatar
                    Image(systemName: "person.fill")
                        .font(.system(size: 30))
                        .foregroundColor(color)
                    
                    if rank == 1 {
                         Capsule()
                            .fill(color)
                            .frame(width: 60, height: 20)
                            .overlay(
                                Text("RANK 01")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundColor(.black)
                            )
                            .offset(y: 36)
                    } else {
                        Capsule()
                            .fill(color)
                            .frame(width: 50, height: 18)
                            .overlay(
                                Text(rank == 2 ? "SILVER" : "BRONZE")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundColor(.black)
                            )
                            .offset(y: 36)
                            .rotationEffect(.degrees(-10))
                    }
                }
                .scaleEffect(scale)
                .padding(.bottom, 12)
                
                VStack(spacing: 2) {
                    Text(entry.userName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(valueStr)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(color)
                }
            }
            .frame(width: 100)
        }
        .buttonStyle(.plain)
    }
    
    private var rankingListView: some View {
        LazyVStack(spacing: 12) {
            let rankings = rankingService.leaderboard
            if rankings.count > 3 {
                ForEach(3..<rankings.count, id: \.self) { index in
                    rankingRow(rank: index + 1, entry: rankings[index])
                }
            }
        }
        .padding(.horizontal, 24)
    }
    
    private func rankingRow(rank: Int, entry: LeaderboardEntry) -> some View {
        Button(action: { selectedUser = entry }) {
            HStack(spacing: 16) {
                Text(String(format: "%02d", rank))
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                    .frame(width: 30)
                
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.gray)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.userName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    if let crew = entry.crewName {
                        Text("Crew: \(crew)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 0) {
                    Text(formattedLeaderboardValueOnly(entry.value, metric: entry.metric))
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text(entry.metric.unit)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.gray)
                        .textCase(.uppercase)
                }
            }
            .padding(12)
            .background(glassDark)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var stickyHeader: some View {
        VStack(spacing: 0) {
            myRankingBar
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .background(
                    backgroundDark.opacity(0.95) // High opacity to hide scrolling content behind
                        .shadow(color: .black.opacity(0.5), radius: 10, y: 5)
                )
        }
        .padding(.top, 8) // Small gap
    }
    
    private var myRankingBar: some View {
        HStack(spacing: 16) {
            // Rank Circle
            Circle()
                .fill(neonGreen)
                .frame(width: 48, height: 48)
                .overlay(
                    Text(rankingService.getMyRankString().replacingOccurrences(of: "RANK ", with: ""))
                        .font(.system(size: 18, weight: .black, design: .monospaced))
                        .foregroundColor(.black)
                )
                .shadow(color: neonGreen.opacity(0.5), radius: 10)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("YOU")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(.white)
                Text(rankingService.getMyRankString())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(neonGreen)
                HStack(spacing: 6) {
                    if rankingService.hasPendingUpload {
                        Text("ranking.sync_pending")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(neonGreen)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(neonGreen.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    Button(action: { showSyncHelp = true }) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 0) {
                let myValue = rankingService.myProfile.getValue(for: selectedMetric, cycle: selectedCycle, resortKey: selectedResortKey)
                let displayValue = formattedValueOnly(myValue, metric: selectedMetric)

                Text(displayValue)
                    .font(.system(size: 24, weight: .heavy, design: .monospaced))
                    .foregroundColor(neonGreen)
                    .shadow(color: neonGreen.opacity(0.3), radius: 5)
                
                Text("\(selectedMetric.unit) \(selectedCycle == .season ? "THIS SEASON" : "THIS WEEK")")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.gray)
            }
        }
        .padding(12)
        .padding(.trailing, 12)
        .background(
            Color.black.opacity(0.8)
                .background(.ultraThinMaterial)
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(neonGreen.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 10, y: 5)
    }
    
    private var selectedResortKey: String? {
        rankingService.resortKey(forDisplayName: selectedResort)
    }
    
    // MARK: - Format Helpers
    
    private func formattedUpdateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }
    
    private func formattedValue(_ value: Double, metric: RankingMetric) -> String {
        let valStr = formattedValueOnly(value, metric: metric)
        return "\(valStr) \(metric.unit)"
    }
    
    private func formattedValueOnly(_ value: Double, metric: RankingMetric) -> String {
        switch metric {
        case .runCount, .edge, .flow:
            return "\(Int(value))"
        case .distance:
            return String(format: "%.1f", value)
        }
    }
    
    private func formattedLeaderboardValue(_ value: Double, metric: RankingMetric) -> String {
        let valStr = formattedLeaderboardValueOnly(value, metric: metric)
        return "\(valStr) \(metric.unit)"
    }
    
    private func formattedLeaderboardValueOnly(_ value: Double, metric: RankingMetric) -> String {
        switch metric {
        case .runCount, .edge, .flow:
            return "\(Int(value))"
        case .distance:
            // 리더보드 값은 서버에 미터로 저장됨
            return String(format: "%.1f", value / 1000.0)
        }
    }
    
    // Enums are now in RankingModels.swift

    private var syncHelpSheet: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("ranking.sync_help_title")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundColor(.white)
                    .tracking(2)
                Text("ranking.sync_help_body")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 20)
                Button(action: { showSyncHelp = false }) {
                    Text("ranking.sync_help_ok")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(neonGreen)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 20)
            .background(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(neonGreen.opacity(0.4), lineWidth: 1)
            )
            .cornerRadius(20)
            .padding(.horizontal, 24)
        }
        .presentationDetents([.medium])
    }

    private var guestRankingView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "trophy.fill")
                    .font(.system(size: 56))
                    .foregroundColor(neonGreen)
                    .shadow(color: neonGreen.opacity(0.5), radius: 16)
                VStack(spacing: 12) {
                    Text("ranking.guest_title")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundColor(.white)
                    Text("ranking.guest_body")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 24)
                }
                Spacer()
                VStack(spacing: 16) {
                    Button(action: {
                        authManager.signInWithGoogle()
                    }) {
                        HStack {
                            Image(systemName: "g.circle.fill")
                                .resizable()
                                .frame(width: 20, height: 20)
                            Text("Sign in with Google")
                                .font(.headline)
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(12)
                    }
                    
                    SignInWithAppleButton(
                        onRequest: { request in
                            let nonce = authManager.startSignInWithAppleFlow()
                            request.requestedScopes = [.fullName, .email]
                            request.nonce = nonce
                        },
                        onCompletion: { result in
                            switch result {
                            case .success(let authorization):
                                authManager.signInWithApple(authorization: authorization)
                            case .failure(let error):
                                authManager.errorMessage = error.localizedDescription
                            }
                        }
                    )
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                Spacer()
            }
            .padding(.vertical, 40)
        }
    }
}

#Preview {
    RankingView(isActive: true)
}
