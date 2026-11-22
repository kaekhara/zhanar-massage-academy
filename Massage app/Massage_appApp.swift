//
//  Massage_appApp.swift
//  Massage app
//
//  Created by Beibarys Yermakhan on 05.11.2026.
//

import SwiftUI

@main
struct Massage_appApp: App {
    @StateObject private var languageSettings = LanguageSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(languageSettings)
                .environment(\.locale, languageSettings.locale)
        }
    }
}
