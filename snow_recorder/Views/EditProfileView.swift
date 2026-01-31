import SwiftUI

struct EditProfileView: View {
    @Binding var isPresented: Bool
    
    // Form State
    @State private var nickname: String = ""
    @State private var bio: String = ""
    @State private var instagramId: String = ""
    @State private var originalNickname: String = ""
    @State private var showNicknameCooldownAlert = false
    @State private var selectedBadgeTitles: [String] = []
    @State private var originalBadgeTitles: [String] = []
    @State private var showBadgeLimitAlert = false
    @State private var showBadgeCooldownAlert = false
    
    // UI Constants
    let neonGreen = Color(red: 107/255, green: 249/255, blue: 6/255)
    let backgroundDark = Color.black
    let glassPanel = Color(white: 1.0, opacity: 0.05)
    
    private let nicknameCooldownKey = "profile.nickname_last_changed_at"

    private func loc(_ key: String, _ comment: String) -> String {
        NSLocalizedString(key, comment: comment)
    }
    
    var body: some View {
        ZStack {
            backgroundDark.ignoresSafeArea()
            
            // Subtle Background Glows
            VStack {
                Circle()
                    .fill(neonGreen.opacity(0.15))
                    .frame(width: 300, height: 300)
                    .blur(radius: 100)
                    .offset(x: 0, y: -150)
                Spacer()
                Circle()
                    .fill(neonGreen.opacity(0.1))
                    .frame(width: 300, height: 300)
                    .blur(radius: 80)
                    .offset(x: -100, y: 100)
            }
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Drag Handle / Header
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: 40, height: 6)
                        .padding(.top, 12)
                    
                    Text("EDIT PROFILE")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(2)
                        .foregroundColor(neonGreen.opacity(0.9))
                        .padding(.bottom, 12)
                }
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.8))
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 32) {
                        
                        // Avatar Editor
                        VStack(spacing: 16) {
                            ZStack(alignment: .bottomTrailing) {
                                // Glow Ring
                                Circle()
                                    .strokeBorder(
                                        LinearGradient(colors: [neonGreen.opacity(0.2), neonGreen.opacity(0.0)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                        lineWidth: 2
                                    )
                                    .background(Circle().fill(neonGreen.opacity(0.05)))
                                    .frame(width: 150, height: 150)
                                    .blur(radius: 4)
                                
                                // Avatar Image
                                Circle()
                                    .fill(Color(white: 0.1))
                                    .frame(width: 140, height: 140)
                                    .overlay(
                                        Image(systemName: "person.fill") // Placeholder
                                            .resizable()
                                            .scaledToFit()
                                            .padding(30)
                                            .foregroundColor(.gray)
                                    )
                                    .overlay(
                                        Circle().stroke(neonGreen.opacity(0.6), lineWidth: 2)
                                    )
                                    .shadow(color: neonGreen.opacity(0.15), radius: 20, x: 0, y: 0)
                                
                                // Edit Button
                                Circle()
                                    .fill(Color.black)
                                    .frame(width: 40, height: 40)
                                    .overlay(Circle().stroke(neonGreen, lineWidth: 1))
                                    .overlay(
                                        Image(systemName: "pencil")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(neonGreen)
                                    )
                                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                                    .offset(x: 0, y: 0)
                            }
                            
                            Text("TAP TO UPDATE")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1.5)
                                .foregroundColor(.gray)
                        }
                        .padding(.top, 20)
                        
                        // Inputs
                        VStack(spacing: 24) {
                            
                            // Nickname Input
                            VStack(alignment: .leading, spacing: 10) {
                                Text("CODENAME")
                                    .font(.system(size: 11, weight: .bold))
                                    .tracking(1.5)
                                    .foregroundColor(.gray)
                                    .padding(.leading, 4)
                                
                                ZStack(alignment: .trailing) {
                                    TextField("", text: $nickname)
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding()
                                        .background(glassPanel)
                                        .cornerRadius(16)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                        )
                                        .disabled(!canEditNicknameNow)
                                    
                                    // Status Indicator
                                    Circle()
                                        .fill(neonGreen)
                                        .frame(width: 8, height: 8)
                                        .padding(.trailing, 16)
                                        .shadow(color: neonGreen, radius: 5)
                                }
                                
                                if let cooldownText = nicknameCooldownText {
                                    Text(cooldownText)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.gray)
                                        .padding(.leading, 4)
                                }
                            }
                            
                            // Bio Input
                            VStack(alignment: .leading, spacing: 10) {
                                Text("FLEX BIO")
                                    .font(.system(size: 11, weight: .bold))
                                    .tracking(1.5)
                                    .foregroundColor(.gray)
                                    .padding(.leading, 4)
                                
                                ZStack(alignment: .topLeading) {
                                    if bio.isEmpty {
                                        Text("Write something about yourself...")
                                            .foregroundColor(.white.opacity(0.2))
                                            .padding()
                                            .padding(.top, 4)
                                    }
                                    
                                    TextEditor(text: $bio)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                        .scrollContentBackground(.hidden) // Remove default background
                                        .padding(12)
                                        .frame(minHeight: 120)
                                        .background(glassPanel)
                                        .cornerRadius(16)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                        )
                                }
                            }
                            
                            // Instagram Input
                            VStack(alignment: .leading, spacing: 10) {
                                Text("LINK")
                                    .font(.system(size: 11, weight: .bold))
                                    .tracking(1.5)
                                    .foregroundColor(.gray)
                                    .padding(.leading, 4)
                                
                                HStack(spacing: 0) {
                                    ZStack {
                                        Rectangle()
                                            .fill(Color.white.opacity(0.05))
                                            .frame(width: 50)
                                        
                                        Image(systemName: "link")
                                            .font(.system(size: 20))
                                            .foregroundColor(.gray)
                                    }
                                    
                                    TextField("instagram.com/...", text: $instagramId)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(neonGreen)
                                        .padding()
                                }
                                .frame(height: 56)
                                .background(glassPanel)
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                                .overlay(
                                    HStack {
                                        Spacer()
                                        Divider().background(Color.white.opacity(0.1))
                                    }
                                    , alignment: .leading
                                )
                            }
                        }
                        .padding(.horizontal, 24)

                        // Featured Badges
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("FEATURED BADGES")
                                    .font(.system(size: 11, weight: .bold))
                                    .tracking(1.5)
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("\(selectedBadgeTitles.count)/3")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(neonGreen.opacity(0.8))
                            }
                            .padding(.horizontal, 4)
                            
                            if !earnedBadges.isEmpty {
                                VStack(spacing: 10) {
                                    ForEach(earnedBadges) { badge in
                                        Button(action: {
                                            toggleFeaturedBadge(badge)
                                        }) {
                                            HStack(spacing: 12) {
                                                Image(systemName: badge.iconName)
                                                    .frame(width: 22)
                                                    .foregroundColor(neonGreen)
                                                Text(badge.title)
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundColor(.white)
                                                Spacer()
                                                if selectedBadgeTitles.contains(badge.title) {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundColor(neonGreen)
                                                } else {
                                                    Image(systemName: "circle")
                                                        .foregroundColor(.white.opacity(0.2))
                                                }
                                            }
                                            .padding(.vertical, 10)
                                            .padding(.horizontal, 14)
                                            .background(glassPanel)
                                            .cornerRadius(14)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 14)
                                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(!canEditFeaturedBadgesNow)
                                    }
                                }
                            } else {
                                Text(loc("profile.featured_badges_empty", "획득한 뱃지 없음"))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.gray)
                            }
                            
                            if let badgeCooldownText = featuredBadgeCooldownText {
                                Text(badgeCooldownText)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.gray)
                                    .padding(.leading, 4)
                            }
                        }
                        .padding(.horizontal, 24)
                        
                        Spacer().frame(height: 100)
                    }
                }
                
                // Footer
                VStack(spacing: 12) {
                    Button(action: saveProfile) {
                        Text("SAVE CHANGES")
                        .font(.system(size: 16, weight: .black))
                        .tracking(1.5)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(neonGreen)
                        .cornerRadius(28)
                        .shadow(color: neonGreen.opacity(0.3), radius: 15, x: 0, y: 0)
                    }
                    
                    Button(action: { isPresented = false }) {
                        Text("CANCEL")
                            .font(.system(size: 12, weight: .bold))
                            .tracking(1.5)
                            .foregroundColor(.gray)
                            .padding(.vertical, 12)
                    }
                }
                .padding(24)
                .background(
                    LinearGradient(colors: [.black, .black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .top)
                        .ignoresSafeArea()
                )
            }
        }
        .onAppear {
            // Load current data from shared service
            let profile = GamificationService.shared.profile
            nickname = profile.nickname
            bio = profile.bio ?? ""
            instagramId = profile.instagramId ?? ""
            originalNickname = profile.nickname
            selectedBadgeTitles = profile.featuredBadgeTitles
            originalBadgeTitles = profile.featuredBadgeTitles
        }
        .alert(loc("profile.nickname_cooldown_title", "닉네임 변경 쿨타임 타이틀"), isPresented: $showNicknameCooldownAlert) {
            Button(loc("profile.nickname_cooldown_ok", "닉네임 쿨타임 확인"), role: .cancel) { }
        } message: {
            Text(nicknameCooldownAlertMessage)
        }
        .alert(loc("profile.featured_badges_limit_title", "뱃지 선택 제한 타이틀"), isPresented: $showBadgeLimitAlert) {
            Button(loc("profile.featured_badges_limit_ok", "뱃지 선택 제한 확인"), role: .cancel) { }
        } message: {
            Text(loc("profile.featured_badges_limit_message", "뱃지 선택 제한 메시지"))
        }
        .alert(loc("profile.featured_badges_cooldown_title", "뱃지 쿨타임 타이틀"), isPresented: $showBadgeCooldownAlert) {
            Button(loc("profile.featured_badges_limit_ok", "뱃지 선택 제한 확인"), role: .cancel) { }
        } message: {
            Text(featuredBadgesCooldownAlertMessage)
        }
    }
    
    private func saveProfile() {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.isEmpty ? "skier" : trimmed
        let originalTrimmed = originalNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNicknameChanged = normalized != originalTrimmed
        
        if isNicknameChanged && !canEditNicknameNow {
            showNicknameCooldownAlert = true
            return
        }
        
        GamificationService.shared.updateProfileInfo(nickname: normalized, bio: bio, instagramId: instagramId)
        if !AuthenticationManager.shared.isGuest {
            AuthenticationManager.shared.updateDisplayName(to: normalized)
        }
        
        if isNicknameChanged {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: nicknameCooldownKey)
        }
        
        let featuredChanged = selectedBadgeTitles != originalBadgeTitles
        if featuredChanged {
            if !GamificationService.shared.canChangeFeaturedBadges {
                showBadgeCooldownAlert = true
                selectedBadgeTitles = originalBadgeTitles
            } else {
                _ = GamificationService.shared.updateFeaturedBadges(selectedBadgeTitles)
                originalBadgeTitles = selectedBadgeTitles
            }
        }
        isPresented = false
    }
    
    private var canEditNicknameNow: Bool {
        guard let nextDate = nextNicknameChangeDate else { return true }
        return Date() >= nextDate
    }
    
    private var nextNicknameChangeDate: Date? {
        let interval = UserDefaults.standard.double(forKey: nicknameCooldownKey)
        guard interval > 0 else { return nil }
        let lastDate = Date(timeIntervalSince1970: interval)
        return Calendar.current.date(byAdding: .month, value: 1, to: lastDate)
    }
    
    private var nicknameCooldownText: String? {
        guard let remainingDays = nicknameRemainingDays else { return nil }
        return String(format: loc("profile.nickname_cooldown_remaining_format", "닉네임 변경 남은 일수 포맷"), remainingDays)
    }
    
    private var nicknameCooldownAlertMessage: String {
        if let remainingDays = nicknameRemainingDays {
            return String(format: loc("profile.nickname_cooldown_alert_remaining_format", "닉네임 쿨타임 경고 포맷"), remainingDays)
        }
        return loc("profile.nickname_cooldown_alert_fallback", "닉네임 쿨타임 기본 안내")
    }

    private var nicknameRemainingDays: Int? {
        guard let nextDate = nextNicknameChangeDate, !canEditNicknameNow else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: nextDate).day ?? 0
        return max(1, days)
    }

    private var earnedBadges: [Badge] {
        GamificationService.shared.profile.badges.filter { $0.isEarned }
    }

    private var canEditFeaturedBadgesNow: Bool {
        GamificationService.shared.canChangeFeaturedBadges
    }

    private var featuredBadgeCooldownText: String? {
        guard let remainingDays = GamificationService.shared.featuredBadgesRemainingDays else { return nil }
        return String(format: loc("profile.featured_badges_cooldown_remaining_format", "뱃지 변경 남은 일수 포맷"), remainingDays)
    }

    private var featuredBadgesCooldownAlertMessage: String {
        if let remainingDays = GamificationService.shared.featuredBadgesRemainingDays {
            return String(format: loc("profile.featured_badges_cooldown_alert_remaining_format", "뱃지 쿨타임 경고 포맷"), remainingDays)
        }
        return loc("profile.featured_badges_cooldown_fallback", "뱃지 쿨타임 기본 안내")
    }

    private func toggleFeaturedBadge(_ badge: Badge) {
        guard canEditFeaturedBadgesNow else {
            showBadgeCooldownAlert = true
            return
        }
        if let index = selectedBadgeTitles.firstIndex(of: badge.title) {
            selectedBadgeTitles.remove(at: index)
            return
        }
        guard selectedBadgeTitles.count < 3 else {
            showBadgeLimitAlert = true
            return
        }
        selectedBadgeTitles.append(badge.title)
    }
}

#Preview {
    EditProfileView(isPresented: .constant(true))
}
