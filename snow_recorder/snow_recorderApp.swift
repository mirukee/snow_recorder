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
        .modelContainer(for: RunSession.self)
    }
}
