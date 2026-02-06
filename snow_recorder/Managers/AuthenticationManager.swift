import SwiftUI
import FirebaseAuth
import GoogleSignIn
import FirebaseFirestore
import AuthenticationServices
import CryptoKit
import Combine
import FirebaseCore
import SwiftData

class AuthenticationManager: ObservableObject {
    @Published var user: User?
    @Published var isGuest: Bool = false
    @Published var errorMessage: String = ""
    
    static let shared = AuthenticationManager()

    private let featuredBadgesUploadDelay: TimeInterval = 6
    private var featuredBadgesUploadWorkItem: DispatchWorkItem?
    
    private init() {
        self.user = Auth.auth().currentUser
        if self.user == nil {
            self.isGuest = true
        }
        syncNicknameFromAuthIfNeeded()
    }
    
    // MARK: - Sign In with Google
    func signInWithGoogle() {
        guard let clientID = FirebaseApp.app()?.options.clientID else { return }
        
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else { return }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { [weak self] result, error in
            if let error = error {
                self?.errorMessage = error.localizedDescription
                return
            }
            
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else { return }
            
            let credential = GoogleAuthProvider.credential(withIDToken: idToken,
                                                           accessToken: user.accessToken.tokenString)
            
            Auth.auth().signIn(with: credential) { authResult, error in
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    return
                }
                self?.user = authResult?.user
                self?.isGuest = false
                self?.syncNicknameFromAuthIfNeeded()
                self?.checkAndCreateFirestoreUser()
                // Link local sessions (Guest Data) to this user
                self?.linkLocalSessionsToUser()
            }
        }
    }
    
    // MARK: - Sign In with Apple
    func signInWithApple(authorization: ASAuthorization) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            guard let nonce = currentNonce else {
                fatalError("Invalid state: A login callback was received, but no login request was sent.")
            }
            
            guard let appleIDToken = appleIDCredential.identityToken else {
                print("Unable to fetch identity token")
                return
            }
            
            guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                print("Unable to serialize token string from data: \(appleIDToken.debugDescription)")
                return
            }
            
            // Use the .apple enum case for AuthProviderID
            let credential = OAuthProvider.credential(providerID: .apple,
                                                      idToken: idTokenString,
                                                      rawNonce: nonce)
            
            Auth.auth().signIn(with: credential) { [weak self] (authResult, error) in
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    return
                }
                
                guard let user = authResult?.user else { return }
                self?.user = user
                self?.isGuest = false
                
                // Apple Login only returns fullName on the FIRST login.
                // We must capture it and update the Firebase Profile.
                if let fullName = appleIDCredential.fullName {
                    let givenName = fullName.givenName ?? ""
                    let familyName = fullName.familyName ?? ""
                    let displayName = "\(givenName) \(familyName)".trimmingCharacters(in: .whitespaces)
                    
                    if !displayName.isEmpty {
                        let changeRequest = user.createProfileChangeRequest()
                        changeRequest.displayName = displayName
                        changeRequest.commitChanges { error in
                            if let error = error {
                                print("Error updating display name: \(error)")
                            }
                            self?.syncNicknameFromAuthIfNeeded()
                            // Sync with Firestore after profile update
                            self?.checkAndCreateFirestoreUser()
                        }
                    } else {
                        self?.syncNicknameFromAuthIfNeeded()
                        self?.checkAndCreateFirestoreUser()
                    }
                } else {
                    self?.syncNicknameFromAuthIfNeeded()
                    self?.checkAndCreateFirestoreUser()
                }
                
                // Link local sessions (Guest Data) to this user
                self?.linkLocalSessionsToUser()
            }
        }
    }
    
    // MARK: - Guest Logic
    func continueAsGuest() {
        self.isGuest = true
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            self.user = nil
            self.isGuest = true
            featuredBadgesUploadWorkItem?.cancel()
            featuredBadgesUploadWorkItem = nil
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func deleteAccount(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "No authenticated user."])))
            return
        }
        let uid = user.uid
        let db = Firestore.firestore()
        let userRef = db.collection("rankings").document(uid)
        
        userRef.delete { [weak self] error in
            if let error {
                completion(.failure(error))
                return
            }
            user.delete { error in
                if let error {
                    completion(.failure(error))
                    return
                }
                self?.user = nil
                self?.isGuest = true
                self?.featuredBadgesUploadWorkItem?.cancel()
                self?.featuredBadgesUploadWorkItem = nil
                completion(.success(()))
            }
        }
    }

    // MARK: - 닉네임 동기화

    func updateDisplayName(to name: String, completion: ((Bool) -> Void)? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion?(false)
            return
        }
        guard let user = Auth.auth().currentUser else {
            completion?(false)
            return
        }
        if user.displayName == trimmed {
            syncNicknameFromAuthIfNeeded()
            completion?(true)
            return
        }
        let changeRequest = user.createProfileChangeRequest()
        changeRequest.displayName = trimmed
        changeRequest.commitChanges { [weak self] error in
            if let error = error {
                print("❌ Failed to update display name: \(error)")
                completion?(false)
                return
            }
            self?.user = Auth.auth().currentUser
            self?.syncNicknameFromAuthIfNeeded()
            self?.syncNicknameToRankingIfNeeded(displayName: trimmed)
            completion?(true)
        }
    }

    private func syncNicknameFromAuthIfNeeded() {
        guard let name = Auth.auth().currentUser?.displayName, !name.isEmpty else { return }
        let profile = GamificationService.shared.profile
        if profile.nickname != name {
            GamificationService.shared.updateProfileInfo(
                nickname: name,
                bio: profile.bio,
                instagramId: profile.instagramId
            )
        }
        RankingService.shared.updateUserNameIfNeeded(name)
    }

    private func syncNicknameToRankingIfNeeded(displayName: String) {
        guard let user = user else { return }
        guard RankingService.shared.isRankingEnabled else { return }
        let db = Firestore.firestore()
        let userRef = db.collection("rankings").document(user.uid)
        userRef.setData(["nickname": displayName], merge: true)
    }

    func scheduleFeaturedBadgesUploadIfNeeded() {
        guard let user = user else { return }
        guard GamificationService.shared.isFeaturedBadgesUploadPending else { return }
        featuredBadgesUploadWorkItem?.cancel()
        let titles = GamificationService.shared.featuredBadgeTitles
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let db = Firestore.firestore()
            let userRef = db.collection("rankings").document(user.uid)
            userRef.setData(["featured_badges": titles], merge: true) { error in
                if let error {
                    print("❌ Featured badges upload failed: \(error)")
                    return
                }
                GamificationService.shared.clearFeaturedBadgesUploadPending()
            }
        }
        featuredBadgesUploadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + featuredBadgesUploadDelay, execute: workItem)
    }

    private func currentJoinYear() -> Int {
        if let creationDate = user?.metadata.creationDate {
            return Calendar.current.component(.year, from: creationDate)
        }
        return Calendar.current.component(.year, from: Date())
    }
    
    // MARK: - Firestore Sync
    private func checkAndCreateFirestoreUser() {
        guard let user = user else { return }
        let db = Firestore.firestore()
        let userRef = db.collection("rankings").document(user.uid)

        guard RankingService.shared.isRankingEnabled else {
            userRef.delete { error in
                if let error {
                    print("❌ 랭킹 비참여 상태 삭제 실패: \(error)")
                }
            }
            return
        }
        
        userRef.getDocument { document, error in
            if let document = document, document.exists {
                let nickname = user.displayName ?? "skier"
                let joinYear = self.currentJoinYear()
                // 기존 유저: 마지막 로그인 + 닉네임 미러 동기화
                userRef.updateData([
                    "lastLogin": FieldValue.serverTimestamp(),
                    "nickname": nickname,
                    "joined_year": joinYear
                ])
            } else {
                let joinYear = self.currentJoinYear()
                // Create new user entry
                let userData: [String: Any] = [
                    "nickname": user.displayName ?? "skier",
                    "createdAt": FieldValue.serverTimestamp(),
                    "joined_year": joinYear,
                    "totalDistance": 0.0,
                    "maxSpeed": 0.0,
                    "runCount": 0,
                    "tier": "Bronze", // Default tier
                    "platform": "iOS"
                ]
                userRef.setData(userData)
            }
        }
    }

    /// 앱 시작 시 랭킹 비참여 상태면 서버 랭킹 문서를 정리
    func ensureRankingOptOutCleanup() {
        guard let user = user else { return }
        guard !isGuest else { return }
        guard !RankingService.shared.isRankingEnabled else { return }
        let db = Firestore.firestore()
        let userRef = db.collection("rankings").document(user.uid)
        userRef.delete { error in
            if let error {
                print("❌ 랭킹 비참여 상태 정리 실패: \(error)")
            }
        }
    }
    
    // MARK: - Apple Sign In Helpers
    // Unhashed nonce.
    private var currentNonce: String?

    func startSignInWithAppleFlow() -> String {
        let nonce = randomNonceString()
        currentNonce = nonce
        return sha256(nonce)
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: Array<Character> =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }

            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }

                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            return String(format: "%02x", $0)
        }.joined()

        return hashString
    }
    
    // MARK: - Data Synchronization (Guest -> User)
    var modelContext: ModelContext?
    
    private func linkLocalSessionsToUser() {
        guard let user = user, let context = modelContext else { return }
        print("🔗 Linking local sessions to user: \(user.uid)")
        
        do {
            // Fetch all sessions with nil userID
            let descriptor = FetchDescriptor<RunSession>(predicate: #Predicate { $0.userID == nil })
            let sessions = try context.fetch(descriptor)
            
            if !sessions.isEmpty {
                print("Found \(sessions.count) guest sessions. Updating userID...")
                for session in sessions {
                    session.userID = user.uid
                }
                try context.save()
                print("✅ Successfully linked \(sessions.count) sessions to \(user.displayName ?? "User").")
            } else {
                print("No guest sessions found to link.")
            }
        } catch {
            print("❌ Error linking sessions: \(error)")
        }
    }
}
