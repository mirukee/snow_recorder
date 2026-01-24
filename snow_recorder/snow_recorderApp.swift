//
//  snow_recorderApp.swift
//  snow_recorder
//
//  Created by 김도윤 on 1/21/26.
//

import SwiftUI
import SwiftData
import FirebaseCore
import GoogleSignIn

class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    FirebaseApp.configure()
    return true
  }

  func application(_ app: UIApplication,
                   open url: URL,
                   options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    return GIDSignIn.sharedInstance.handle(url)
  }
}

@main
struct snow_recorderApp: App {
    // register app delegate for Firebase setup
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: RunSession.self, isAutosaveEnabled: true, isUndoEnabled: false) { result in
            switch result {
            case .success(let container):
                print("✅ SwiftData 컨테이너 로드 성공")
            case .failure(let error):
                print("❌ SwiftData 오류: \(error)")
            }
        }
    }
}

