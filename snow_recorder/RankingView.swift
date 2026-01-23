import SwiftUI
import SwiftData

struct RankingView: View {
    // MARK: - Colors
    let neonGreen = Color(red: 107/255, green: 249/255, blue: 6/255) // #6bf906
    let backgroundDark = Color.black
    let surfaceDark = Color(white: 0.05)
    let glassDark = Color.white.opacity(0.05)
    
    // MARK: - State
    @State private var selectedScope: RankingScope = .individual
    @State private var selectedResort: String = "All Resorts"
    @State private var selectedSlope: String = "All Slopes" // New Slope Filter
    @State private var selectedMetric: RankingMetric = .runCount
    @State private var selectedCycle: RankingCycle = .season
    @ObservedObject private var rankingService = RankingService.shared
    @Query(sort: \RunSession.startTime, order: .reverse) private var sessions: [RunSession]
    
    // MARK: - Models (Using RankingModels.swift)
    
    // Mock Data (Resorts)
    let resorts = ["All Resorts", "High1", "Yongpyong", "Phoenix", "Vivaldi"]
    
    // Slopes Data Helper
    var availableSlopes: [String] {
        if selectedResort == "High1" {
            var slopes = ["All Slopes"]
            slopes.append(contentsOf: SlopeDatabase.shared.slopes.map { $0.name })
            return slopes
        } else {
            return ["All Slopes"]
        }
    }
    
    var filteredRankings: [LeaderboardEntry] {
        let slopeFilter = selectedSlope == "All Slopes" ? nil : selectedSlope
        return rankingService.getLeaderboard(cycle: selectedCycle, metric: selectedMetric, scope: selectedScope, slope: slopeFilter)
    }
    
    var body: some View {
        ZStack {
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
                            
                            scopeSwitcher
                                .padding(.horizontal, 24)
                                .padding(.bottom, 16)
                            
                            // Filters Container
                            VStack(spacing: 16) {
                                resortFilterScroll
                                
                                // Show Slope Filter only if a specific resort is selected (e.g., High1)
                                if selectedResort != "All Resorts" {
                                    slopeFilterScroll
                                        .transition(.move(edge: .top).combined(with: .opacity))
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
        .preferredColorScheme(.dark)
        .onAppear {
            // 앱 시작 시 또는 뷰 진입 시 기존 데이터를 기반으로 랭킹 통계 재계산
            rankingService.recalculateStats(from: sessions)
        }
        .onChange(of: sessions) { _, newSessions in
            rankingService.recalculateStats(from: newSessions)
        }
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
                
                Button(action: {}) {
                    Image(systemName: "gearshape") // Moved actual logic to ProfileView
                        .foregroundColor(.white.opacity(0.3)) // Dimmed here
                        .font(.system(size: 20, weight: .semibold))
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
    
    private var scopeSwitcher: some View {
        HStack(spacing: 0) {
            scopeButton(title: "INDIVIDUAL", scope: .individual)
            scopeButton(title: "CREW", scope: .crew)
        }
        .padding(4)
        .background(Color.white.opacity(0.05))
        .cornerRadius(30)
        .overlay(
            RoundedRectangle(cornerRadius: 30)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func scopeButton(title: String, scope: RankingScope) -> some View {
        Button(action: {
            withAnimation(.spring()) {
                selectedScope = scope
            }
        }) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .tracking(1)
                .foregroundColor(selectedScope == scope ? .black : .gray)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(
                    selectedScope == scope ? neonGreen : Color.clear
                )
                .cornerRadius(20)
                .shadow(color: selectedScope == scope ? neonGreen.opacity(0.4) : .clear, radius: 5)
        }
    }
    
    private var resortFilterScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(resorts, id: \.self) { resort in
                    Button(action: {
                        withAnimation {
                            selectedResort = resort
                            selectedSlope = "All Slopes" // Reset slope on resort change
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
    
    private var slopeFilterScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableSlopes, id: \.self) { slope in
                    Button(action: {
                        withAnimation { selectedSlope = slope }
                    }) {
                        Text(slope)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                selectedSlope == slope ? neonGreen.opacity(0.2) : Color.white.opacity(0.05)
                            )
                            .foregroundColor(
                                selectedSlope == slope ? neonGreen : .gray
                            )
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(selectedSlope == slope ? neonGreen.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }
    
    private var metricTabs: some View {
        HStack(spacing: 20) {
            metricTabButton(title: "RUNS", icon: "figure.run", metric: .runCount)
            metricTabButton(title: "DIST", icon: "chart.xyaxis.line", metric: .distance)
            metricTabButton(title: "EDGE", icon: "arrow.triangle.merge", metric: .edge)
            metricTabButton(title: "FLOW", icon: "wind", metric: .flow)
        }
        .padding(.horizontal, 24)
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
        let topThree = Array(filteredRankings.prefix(3))
        // Ensure we have at least 3 items for the podium to look good, otherwise handle gracefully
        // For mock data, we have enough.
        
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
        let valueStr = formattedValue(entry.value, metric: selectedMetric)
        
        return VStack(spacing: 8) {
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
    
    private var rankingListView: some View {
        LazyVStack(spacing: 12) {
            let rankings = filteredRankings
            if rankings.count > 3 {
                ForEach(3..<rankings.count, id: \.self) { index in
                    rankingRow(rank: index + 1, entry: rankings[index])
                }
            }
        }
        .padding(.horizontal, 24)
    }
    
    private func rankingRow(rank: Int, entry: LeaderboardEntry) -> some View {
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
                Text(formattedValueOnly(entry.value, metric: entry.metric))
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
                    Text(rankingService.myProfile.getRank(for: selectedMetric, cycle: selectedCycle).replacingOccurrences(of: "TOP ", with: "").replacingOccurrences(of: "%", with: ""))
                        .font(.system(size: 18, weight: .black, design: .monospaced))
                        .foregroundColor(.black)
                )
                .shadow(color: neonGreen.opacity(0.5), radius: 10)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("YOU")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(.white)
                Text(rankingService.myProfile.getRank(for: selectedMetric, cycle: selectedCycle))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(neonGreen)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 0) {
                // Real Data Integration from Service
                let myValue = rankingService.myProfile.getValue(for: selectedMetric, cycle: selectedCycle)
                
                Text(formattedValueOnly(myValue, metric: selectedMetric))
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
    
    // MARK: - Format Helpers
    
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
    
    // Enums are now in RankingModels.swift
}

#Preview {
    RankingView()
}
