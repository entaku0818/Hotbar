import SwiftUI

enum AppLanguage: String, CaseIterable {
    case system, japanese = "ja", english = "en"

    var title: String {
        switch self {
        case .system: return "System language"
        case .japanese: return "日本語"
        case .english: return "English"
        }
    }

    func resolvedCode(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        guard self == .system else { return rawValue }
        for language in preferredLanguages {
            let code = language.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first
            if code == "ja" { return "ja" }
            if code == "en" { return "en" }
        }
        return "en"
    }

    var locale: Locale { Locale(identifier: resolvedCode()) }
}

enum L10n {
    static func text(_ key: String, language: AppLanguage = AppSettings.shared.language) -> String {
        guard let path = Bundle.main.path(forResource: language.resolvedCode(), ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ value: CVarArg) -> String {
        String(format: text(key), locale: AppSettings.shared.language.locale, arguments: [value])
    }
}

struct LocalizedContent<Content: View>: View {
    @ObservedObject private var settings = AppSettings.shared
    @ViewBuilder var content: () -> Content

    var body: some View {
        content().environment(\.locale, settings.language.locale)
    }
}

extension Notification.Name {
    static let hotbarLanguageChanged = Notification.Name("hotbarLanguageChanged")
}
