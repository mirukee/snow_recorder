import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var storeManager: StoreManager
    @Environment(\.locale) private var locale
    @AppStorage("preferred_language") private var preferredLanguage: String = "system"
    
    // Theme Colors
    private let neonGreen = Color(red: 107/255, green: 249/255, blue: 6/255) // #6bf906
    private let bgDark = Color(red: 5/255, green: 5/255, blue: 5/255) // #050505
    private let cardDark = Color(red: 18/255, green: 18/255, blue: 18/255) // #121212
    private let bgLight = Color(red: 247/255, green: 248/255, blue: 245/255) // #f7f8f5
    
    @State private var selectedPlan: Plan = .annual
    @State private var isPurchasing: Bool = false
    @State private var purchaseErrorMessage: String? = nil
    
    private var preferredLocale: Locale {
        switch preferredLanguage {
        case "ko":
            return Locale(identifier: "ko")
        case "en":
            return Locale(identifier: "en")
        default:
            return locale
        }
    }

    private func localizedBundleString(_ key: String) -> String {
        let language: String?
        switch preferredLanguage {
        case "ko": language = "ko"
        case "en": language = "en"
        default: language = nil
        }

        if let language,
           let path = Bundle.main.path(forResource: language, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle.localizedString(forKey: key, value: key, table: nil)
        }
        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    private func locString(_ key: String) -> String {
        localizedBundleString(key)
    }
    
    private enum Plan: String, CaseIterable {
        case annual
        case lifetime
    }
    
    var body: some View {
        ZStack {
            // Background
            bgDark.ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Header (Close & Restore)
                    headerView
                        .padding(.horizontal)
                        .padding(.top)
                    
                    // Hero Section
                    heroSection
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    
                    // Headline
                    VStack(spacing: 8) {
                        Text("paywall.headline_go_pro")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("paywall.headline_unlock_potential")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(neonGreen)
                            .shadow(color: neonGreen.opacity(0.4), radius: 10, x: 0, y: 0)
                        
                        Text("paywall.subtitle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                    .padding(.bottom, 32)
                    
                    // Feature Grid
                    featureGrid
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    
                    // Pricing Cards
                    if storeManager.products.isEmpty {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text(storeManager.statusMessage)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.bottom, 120)
                    } else {
                        pricingSection
                            .padding(.horizontal)
                            .padding(.bottom, 180) // Space for fixed footer
                    }
                }
            }
            
            // Sticky Footer
            VStack {
                Spacer()
                footerView
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if storeManager.products.isEmpty {
                Task { await storeManager.requestProducts() }
            }
            // 로딩된 상품 기준으로 기본 선택값 보정
            if product(for: selectedPlan) == nil {
                selectedPlan = firstAvailablePlan ?? .annual
            }
        }
        .onChange(of: storeManager.products) { _, _ in
            if product(for: selectedPlan) == nil {
                selectedPlan = firstAvailablePlan ?? .annual
            }
        }
        .onChange(of: storeManager.isPro) { _, isPro in
            if isPro {
                dismiss()
            }
        }
        .alert("paywall.purchase_fail_title", isPresented: Binding(get: {
            purchaseErrorMessage != nil
        }, set: { _ in
            purchaseErrorMessage = nil
        })) {
            Button("paywall.alert_ok", role: .cancel) {}
        } message: {
            if let message = purchaseErrorMessage {
                Text(message)
            } else {
                Text("paywall.purchase_fail_default")
            }
        }
        .id(preferredLocale.identifier)
    }
    
    // MARK: - Components
    
    private var headerView: some View {
        HStack {
            Spacer()
            
            Button(action: {
                dismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Circle())
            }
        }
    }
    
    private var heroSection: some View {
        ZStack {
            // 4:3 Aspect Ratio Container
            Color.black
                .aspectRatio(4/3, contentMode: .fit)
                .overlay(
                    AsyncImage(url: URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuBiDfGsX2-6XA1ej4XB5X0qUkmf_jHKFFGZRlqsQx84UeAzGkZxHDXp6Cpx4iFajqB59eccjdEdpmQMtPt9SH4zkG9178b2skxQnN_UVUXHdYLvSdEao6HTYs5QtWy0y2JzF_ANd_V2UreU9tycIqEIyux_KwRisj6mWuZtizqGj9AQxYF7VXBpo01_7JOig0u7ib-VVTXZ14aknAo3Rj5Z3JCLmjMQHwReM-fOJM4SJlEVCSAN07xORmNDVDBwZVBAs1x21mDtRfM")) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .opacity(0.9)
                        case .empty, .failure:
                            Color.gray.opacity(0.1)
                        @unknown default:
                            EmptyView()
                        }
                    }
                )
                .overlay(
                    // Wireframe Grid Overlay
                    GeometryReader { geo in
                        Path { path in
                            let step: CGFloat = 20
                            for x in stride(from: 0, to: geo.size.width, by: step) {
                                path.move(to: CGPoint(x: x, y: 0))
                                path.addLine(to: CGPoint(x: x, y: geo.size.height))
                            }
                            for y in stride(from: 0, to: geo.size.height, by: step) {
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: geo.size.width, y: y))
                            }
                        }
                        .stroke(neonGreen.opacity(0.1), lineWidth: 1)
                    }
                )
                .overlay(hudOverlays)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
        }
    }
    
    private var hudOverlays: some View {
        ZStack {
            // HUD Corners
            // Top Left
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    Rectangle().fill(neonGreen.opacity(0.3)).frame(width: 64, height: 1)
                    Spacer()
                }
                Rectangle().fill(neonGreen.opacity(0.3)).frame(width: 1, height: 16)
                Spacer()
            }
            .padding(12)
            
            // Bottom Right
            VStack(alignment: .trailing, spacing: 0) {
                Spacer()
                Rectangle().fill(neonGreen.opacity(0.3)).frame(width: 1, height: 16)
                HStack(alignment: .bottom, spacing: 0) {
                    Spacer()
                    Rectangle().fill(neonGreen.opacity(0.3)).frame(width: 64, height: 1)
                }
            }
            .padding(12)
            
            // Bottom HUD Text
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SYSTEM ONLINE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(neonGreen)
                            .tracking(2)
                        
                        // Loading Bar
                        ZStack(alignment: .leading) {
                            Capsule()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 96, height: 4)
                            Capsule()
                            .fill(neonGreen)
                            .frame(width: 64, height: 4)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "view.3d") // view_in_ar equivalent
                        .foregroundColor(neonGreen)
                        .font(.system(size: 20))
                }
                .padding(16)
            }
            
            // Gradient Overlay
            LinearGradient(
                colors: [.clear, .clear, bgDark.opacity(0.9)],
                startPoint: .top,
                    endPoint: .bottom
            )
        }
    }
    
    private var featureGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            featureCard(icon: "brain.head.profile", titleKey: "paywall.feature_ai_analysis")
            featureCard(icon: "map", titleKey: "paywall.feature_3d_replay")
            featureCard(icon: "star.fill", titleKey: "paywall.feature_flex_cards")
            featureCard(icon: "infinity", titleKey: "paywall.feature_sync")
        }
    }
    
    private func featureCard(icon: String, titleKey: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(neonGreen)
            
            Text(titleKey)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    private var pricingSection: some View {
        VStack(spacing: 12) {
            // 1. Annual (Hero)
            if let annual = product(for: .annual) {
                annualPricingCard(annual)
            }
            
            // 3. Lifetime (Normal)
            if let lifetime = product(for: .lifetime) {
                pricingRow(
                    title: locString("paywall.plan_founders"),
                    subtitleKey: "paywall.founders_subtitle",
                    price: lifetime.displayPrice,
                    plan: .lifetime
                )
            }
        }
    }
    
    private func annualPricingCard(_ product: Product) -> some View {
        Button(action: { selectedPlan = .annual }) {
            AnnualCardContent(
                product: product,
                isSelected: selectedPlan == .annual,
                neonGreen: neonGreen,
                cardDark: cardDark,
                checkmarkView: planCheckmark(plan: .annual),
                badgeView: bestValueBadge,
                yearlySubtitle: String(format: locString("paywall.billing_yearly_format"), product.displayPrice)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private struct AnnualCardContent<Checkmark: View, Badge: View>: View {
        let product: Product
        let isSelected: Bool
        let neonGreen: Color
        let cardDark: Color
        let checkmarkView: Checkmark
        let badgeView: Badge
        let yearlySubtitle: String
        
        var body: some View {
            ZStack(alignment: .top) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("paywall.plan_annual")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                        Text(verbatim: yearlySubtitle)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(verbatim: product.displayPrice)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    checkmarkView
                }
                .padding(16)
                .background(cardDark)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? neonGreen : Color.clear, lineWidth: 1)
                )
                
                badgeView
            }
            .padding(1)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? neonGreen.opacity(0.5) : Color.clear)
                    .blur(radius: 4)
            )
        }
        
        // 연간 플랜은 월 환산 표시 제거
    }
    
    private var bestValueBadge: some View {
        Text("BEST VALUE")
            .font(.system(size: 10, weight: .bold))
            .tracking(1)
            .foregroundColor(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(neonGreen)
            .clipShape(Capsule())
            .offset(y: -10)
    }
    
    private func planCheckmark(plan: Plan) -> some View {
        Group {
            if selectedPlan == plan {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 24, height: 24)
                    .background(neonGreen)
                    .clipShape(Circle())
                    .padding(.leading, 12)
            } else {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    .frame(width: 24, height: 24)
                    .padding(.leading, 12)
            }
        }
    }
    
    private func pricingRow(title: String, subtitleKey: LocalizedStringKey, price: String, plan: Plan) -> some View {
        Button(action: { selectedPlan = plan }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(selectedPlan == plan ? .white : .white.opacity(0.9))
                    Text(subtitleKey)
                        .font(.system(size: 12))
                        .foregroundColor(selectedPlan == plan ? .white.opacity(0.5) : .white.opacity(0.4))
                }
                
                Spacer()
                
                Text(verbatim: price)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(selectedPlan == plan ? .white : .white.opacity(0.9))
                
                
                planCheckmark(plan: plan)
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(selectedPlan == plan ? Color.white.opacity(0.6) : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var footerView: some View {
        VStack(spacing: 0) {
            // Gradient separation
            LinearGradient(colors: [bgDark.opacity(0), bgDark], startPoint: .top, endPoint: .bottom)
                .frame(height: 30)
            
            VStack(spacing: 16) {
                Button(action: {
                    // Purchase Action
                    Task {
                        guard let product = product(for: selectedPlan) else { return }
                        isPurchasing = true
                        defer { isPurchasing = false }
                        do {
                            try await storeManager.purchase(product)
                        } catch {
                            purchaseErrorMessage = error.localizedDescription
                        }
                    }
                }) {
                    HStack {
                        Text(verbatim: ctaTitle)
                            .font(.system(size: 18, weight: .black))
                        
                        Image(systemName: "arrow.right")
                            .font(.system(size: 18, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(neonGreen)
                    .cornerRadius(28)
                    .shadow(color: neonGreen.opacity(0.5), radius: 15, x: 0, y: 5)
                }
                .disabled(isPurchasing || product(for: selectedPlan) == nil)
                
                VStack(spacing: 8) {
                    Text("paywall.footer_social_proof")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                    
                    HStack(spacing: 16) {
                        Button(action: {
                            Task {
                                await storeManager.restorePurchases()
                            }
                        }) {
                            Text("paywall.restore")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.5))
                                .underline()
                        }
                        
                        Link("paywall.terms", destination: URL(string: "https://actually-hamster-aa2.notion.site/Snow-Record-Terms-of-Service-2f95e95d9ec180c4848adb22faecef63")!)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.3))
                            .underline()
                        
                        Link("paywall.privacy", destination: URL(string: "https://actually-hamster-aa2.notion.site/Snow-Record-Privacy-Policy-2f95e95d9ec180a795c2e7620227c213")!)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.3))
                            .underline()
                    }
                }
            }
            .padding(16)
            .background(bgDark)
        }
    }
    
    private var firstAvailablePlan: Plan? {
        Plan.allCases.first { product(for: $0) != nil }
    }
    
    private func product(for plan: Plan) -> Product? {
        switch plan {
        case .annual:
            return storeManager.products.first { $0.id == "com.mirukee.snowrecord.pro.annual" }
        case .lifetime:
            return storeManager.products.first { $0.id == "com.mirukee.snowrecord.founderspack" }
        }
    }
    
    private var ctaTitle: String {
        guard let product = product(for: selectedPlan) else {
            return locString("paywall.cta_start_pro")
        }
        if selectedPlan == .lifetime {
            return locString("paywall.cta_forever")
        }
        if let intro = product.subscription?.introductoryOffer {
            return String(
                format: locString("paywall.cta_trial_format"),
                introPeriodText(intro.period)
            )
        }
        return locString("paywall.cta_start_pro")
    }
    
    private func introPeriodText(_ period: Product.SubscriptionPeriod) -> String {
        let value = period.value
        switch period.unit {
        case .day:
            return String(format: locString("paywall.trial_day_format"), value)
        case .week:
            return String(format: locString("paywall.trial_week_format"), value)
        case .month:
            return String(format: locString("paywall.trial_month_format"), value)
        case .year:
            return String(format: locString("paywall.trial_year_format"), value)
        @unknown default:
            return "\(value)"
        }
    }
}

#Preview {
    PaywallView()
        .environmentObject(StoreManager.shared)
}
