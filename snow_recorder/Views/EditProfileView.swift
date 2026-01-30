import SwiftUI

struct EditProfileView: View {
    @Binding var isPresented: Bool
    
    // Form State
    @State private var nickname: String = ""
    @State private var bio: String = ""
    @State private var instagramId: String = ""
    
    // UI Constants
    let neonGreen = Color(red: 107/255, green: 249/255, blue: 6/255)
    let backgroundDark = Color.black
    let glassPanel = Color(white: 1.0, opacity: 0.05)
    
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
                                    
                                    // Status Indicator
                                    Circle()
                                        .fill(neonGreen)
                                        .frame(width: 8, height: 8)
                                        .padding(.trailing, 16)
                                        .shadow(color: neonGreen, radius: 5)
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
        }
    }
    
    private func saveProfile() {
        GamificationService.shared.updateProfileInfo(nickname: nickname, bio: bio, instagramId: instagramId)
        isPresented = false
    }
}

#Preview {
    EditProfileView(isPresented: .constant(true))
}
