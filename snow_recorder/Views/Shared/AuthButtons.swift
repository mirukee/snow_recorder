import SwiftUI
import GoogleSignIn
import UIKit

struct GoogleLoginButton: View {
    let titleKey: LocalizedStringKey
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                googleLogo
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                Text(titleKey)
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundColor(.black)
            .frame(width: 312, height: 48)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
    
    private var googleLogo: Image {
        if let image = loadGoogleLogo() {
            return Image(uiImage: image)
        }
        return Image(systemName: "g.circle.fill")
    }
    
    // GoogleSignIn 리소스 번들에서 공식 로고를 로드한다.
    private func loadGoogleLogo() -> UIImage? {
        let bundleNames = ["GoogleSignIn_GoogleSignIn", "GoogleSignIn"]
        for bundleName in bundleNames {
            if let bundle = googleBundle(named: bundleName),
               let image = UIImage(named: "google", in: bundle, compatibleWith: nil) {
                return image
            }
        }
        return nil
    }
    
    private func googleBundle(named name: String) -> Bundle? {
        if let url = Bundle.main.url(forResource: name, withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        if let url = Bundle(for: GIDSignIn.self).url(forResource: name, withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return nil
    }
}
