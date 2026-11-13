import Foundation

/// Centralizes app-language selection for SwiftUI views and non-view error messages.
enum LocusLocalization {
    static let languageKey = "locus.appLanguage"

    static var locale: Locale {
        switch UserDefaults.standard.string(forKey: languageKey) {
        case "zh-Hans": return Locale(identifier: "zh-Hans")
        case "en": return Locale(identifier: "en")
        default: return Locale(identifier: Bundle.main.preferredLocalizations.first ?? Locale.current.identifier)
        }
    }

    static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key, locale: locale)
    }
}
