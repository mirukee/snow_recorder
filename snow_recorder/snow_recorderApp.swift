//
//  snow_recorderApp.swift
//  snow_recorder
//
//  Created by 김도윤 on 1/21/26.
//

import SwiftUI
import SwiftData

@main
struct snow_recorderApp: App {
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

