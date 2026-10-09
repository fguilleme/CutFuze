import Foundation

/// Follows iOS' preferred supported app language. Never translates project content.
enum AppLocalization {
    static var languageCode: String {
        Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "en"
    }
    static var isFrench: Bool { languageCode.lowercased().hasPrefix("fr") }
    static func english(_ key: String) -> String? {
        Strings.english[key] ?? ExtraStrings.english[key] ?? EnglishCompletion.strings[key]
    }
    static func text(_ key: String, languageCode: String) -> String {
        languageCode.lowercased().hasPrefix("fr") ? key : (english(key) ?? key)
    }
    static func bilingual(_ french: String, _ english: String) -> String {
        isFrench ? french : (self.english(french) ?? english)
    }
}

func L(_ french: String) -> String { AppLocalization.text(french, languageCode: AppLocalization.languageCode) }
