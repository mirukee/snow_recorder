import SwiftUI
import AuthenticationServices
import GoogleSignIn
import GoogleSignInSwift

struct LoginView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // Background
            Color.black.edgesIgnoringSafeArea(.all)
            
            // TODO: Add Background Video or Image
            Image("login_bg_placeholder") // Placeholder
                .resizable()
                .scaledToFill()
                .edgesIgnoringSafeArea(.all)
                .overlay(Color.black.opacity(0.6))
            
            VStack(spacing: 30) {
                Spacer()
                
                // Title Area
                VStack(spacing: 10) {
                    Text("SNOW RECORD")
                        .font(.system(size: 40, weight: .heavy))
                        .foregroundColor(.white)
                        .italic()
                    
                    Text("Record your flow, Rank your flex.")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Buttons
                VStack(spacing: 16) {
                    // Google Sign In
                    Button(action: {
                        authManager.signInWithGoogle()
                    }) {
                        HStack {
                            Image(systemName: "g.circle.fill") // Custom Google Icon needed usually, using SF for now
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
                    
                    // Apple Sign In
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
                                print("Apple Sign In Error: \(error.localizedDescription)")
                            }
                        }
                    )
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)
                    .cornerRadius(12)
                    
                    // Guest Mode
                    Button(action: {
                        authManager.continueAsGuest()
                    }) {
                        Text("login.guest_mode")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .underline()
                    }
                    .padding(.top, 10)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
            }
        }
    }
}

#Preview {
    LoginView()
}
