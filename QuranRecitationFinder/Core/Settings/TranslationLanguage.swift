import Foundation

/// Unterstützte Übersetzungssprachen.
nonisolated enum TranslationLanguage: String, CaseIterable, Identifiable, Sendable {
    case german = "de"
    case turkish = "tr"
    case english = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .german: return "Deutsch"
        case .turkish: return "Türkçe"
        case .english: return "English"
        }
    }

    /// Sprache passend zur Gerätesprache, sonst Englisch.
    static func preferred(for locale: Locale = .current) -> TranslationLanguage {
        let code = locale.language.languageCode?.identifier ?? "en"
        return TranslationLanguage(rawValue: code) ?? .english
    }
}
