import Foundation
import SwiftUI
import Combine

enum AppLanguageCode: String, CaseIterable, Identifiable {
    case kazakh = "kk"
    case russian = "ru"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .kazakh: "Қазақша"
        case .russian: "Русский"
        }
    }

    static var current: AppLanguageCode {
        if let saved = UserDefaults.standard.string(forKey: "app.language"),
           let language = AppLanguageCode(rawValue: saved) {
            return language
        }
        let deviceLanguage = Locale.current.language.languageCode?.identifier
        return deviceLanguage == AppLanguageCode.russian.rawValue ? .russian : .kazakh
    }

    func localized(_ key: String) -> String {
        guard let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }
}

@MainActor
final class LanguageSettings: ObservableObject {
    @Published private(set) var language: AppLanguageCode

    init() {
        self.language = .current
    }

    var locale: Locale { Locale(identifier: language.rawValue) }

    func select(_ language: AppLanguageCode) {
        guard self.language != language else { return }
        self.language = language
        UserDefaults.standard.set(language.rawValue, forKey: "app.language")
    }
}

struct AppLanguagePicker: View {
    @EnvironmentObject private var settings: LanguageSettings

    var body: some View {
        Picker("Тіл / Язык", selection: Binding(
            get: { settings.language },
            set: { settings.select($0) }
        )) {
            ForEach(AppLanguageCode.allCases) { language in
                Text(language.title).tag(language)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Тіл / Язык")
    }
}
