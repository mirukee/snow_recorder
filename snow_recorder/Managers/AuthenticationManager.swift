import SwiftUI
import FirebaseAuth
import GoogleSignIn
import FirebaseFirestore
import AuthenticationServices
import CryptoKit
import Combine
import FirebaseCore

class AuthenticationManager: ObservableObject {
    @Published var user: User?
    @Published var isGuest: Bool = false
    @Published var errorMessage: String = ""
    
    static let shared = AuthenticationManager()
    
    private init() {
        self.user = Auth.auth().currentUser
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
                
                self?.user = authResult?.user
                self?.isGuest = false
                self?.checkAndCreateFirestoreUser()
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
            self.isGuest = false
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
}
