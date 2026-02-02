import Foundation
import StoreKit
import Combine

@MainActor
class StoreManager: ObservableObject {
    static let shared = StoreManager()
    
    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    @Published var isPro: Bool = false
    @Published var statusMessage: String = "Initializing..." // Debug message
    @Published var forceNonPro: Bool = false
    
    // Feature flag for forcing Pro (for debugging/demo)
    private let forcePro = false
    
    // Product IDs
    private let productDict: [String: String] = [
        "com.mirukee.snowrecord.pro.annual": "Annual",
        "com.mirukee.snowrecord.founderspack": "Founders Pack"
    ]
    
    var updateListenerTask: Task<Void, Error>? = nil
    
    init() {
        // 테스트용 비구독 강제 플래그 로드
        #if DEBUG
        forceNonPro = UserDefaults.standard.bool(forKey: "debug.force_non_pro")
        #else
        forceNonPro = false
        #endif
        // Start listening for transaction updates
        updateListenerTask = listenForTransactions()
        let storeKitConfigPath = ProcessInfo.processInfo.environment["STOREKIT_CONFIGURATION_PATH"] ?? "nil"
        print("StoreKit config path:", storeKitConfigPath)
        
        Task {
            await requestProducts()
            await updateCustomerProductStatus()
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    // MARK: - Purchasing
    
    func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    
                    // Transaction is verified, deliver content
                    await self.updateCustomerProductStatus()
                    
                    await transaction.finish()
                } catch {
                    print("Transaction failed verification")
                }
            }
        }
    }
    
    func requestProducts() async {
        do {
            #if DEBUG
            let storeKitConfigPath = ProcessInfo.processInfo.environment["STOREKIT_CONFIGURATION_PATH"] ?? "nil"
            NSLog("StoreKit config path: %@", storeKitConfigPath)
            let env = ProcessInfo.processInfo.environment
            let keys = env.keys.filter { key in
                key.lowercased().contains("storekit") || key.lowercased().contains("xcode")
            }.sorted()
            NSLog("Env keys (filtered): %@", keys.joined(separator: ", "))
            NSLog("Bundle ID: %@", Bundle.main.bundleIdentifier ?? "nil")
            #endif
            self.statusMessage = "Requesting products for: \(productDict.keys.joined(separator: ", "))..."
            let storeProducts = try await Product.products(for: productDict.keys)
            
            // Sort products by price to keep order consistent or custom sort
            // Annual -> Monthly -> Lifetime order for UI
            self.products = storeProducts.sorted { product1, product2 in
                return product1.price < product2.price // Simple sort by price
            }
            
            if self.products.isEmpty {
                print("⚠️ StoreManager: No products found. Check StoreKit configuration or App Store Connect.")
                self.statusMessage = "⚠️ No products found. Check StoreKit file."
            } else {
                self.statusMessage = "Loaded \(self.products.count) products."
            }
        } catch {
            print("Failed to request products: \(error)")
            self.statusMessage = "Error: \(error.localizedDescription)"
        }
    }
    
    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            
            await updateCustomerProductStatus()
            
            await transaction.finish()
            
        case .userCancelled, .pending:
            break
        @unknown default:
            break
        }
    }
    
    func restorePurchases() async {
        // App Store syncs entitlement automatically, but we can re-check logic.
        // In StoreKit 2, usually just syncing/refreshing receipt is enough?
        // Actually, just calling updateCustomerProductStatus iterates current entitlements.
        try? await AppStore.sync()
        await updateCustomerProductStatus()
    }
    
    // MARK: - Debug (Force Non-Pro)
    
    func setForceNonPro(_ enabled: Bool) {
        #if DEBUG
        forceNonPro = enabled
        UserDefaults.standard.set(enabled, forKey: "debug.force_non_pro")
        Task { await updateCustomerProductStatus() }
        #endif
    }
    
    // MARK: - Status Check
    
    func updateCustomerProductStatus() async {
        var purchased: Set<String> = []
        
        // Check current entitlements
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                
                // Check if product is one of ours
                if productDict.keys.contains(transaction.productID) {
                    purchased.insert(transaction.productID)
                }
                
            } catch {
                print("Failed update customer product status")
            }
        }
        
        self.purchasedProductIDs = purchased
        self.isPro = (!purchased.isEmpty || forcePro) && !forceNonPro
        
        // Debug
        print("StoreManager: User is Pro? \(self.isPro). Purchased: \(purchased)")
    }
    
    nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

}

enum StoreError: Error {
    case failedVerification
}
