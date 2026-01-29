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
    
    private init() {
        self.user = Auth.auth().currentUser
        if self.user == nil {
            self.isGuest = true
        }
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
                            // Sync with Firestore after profile update
                            self?.checkAndCreateFirestoreUser()
                        }
                    } else {
                        self?.checkAndCreateFirestoreUser()
                    }
                } else {
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
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
    
    // MARK: - Firestore Sync
    private func checkAndCreateFirestoreUser() {
        guard let user = user else { return }
        let db = Firestore.firestore()
        let userRef = db.collection("rankings").document(user.uid)
        
        userRef.getDocument { document, error in
            if let document = document, document.exists {
                // User info exists, maybe update last login?
                userRef.updateData([
                    "lastLogin": FieldValue.serverTimestamp()
                ])
            } else {
                // Create new user entry
                let userData: [String: Any] = [
                    "nickname": user.displayName ?? "Skier_\(String(user.uid.prefix(4)))",
                    "createdAt": FieldValue.serverTimestamp(),
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
