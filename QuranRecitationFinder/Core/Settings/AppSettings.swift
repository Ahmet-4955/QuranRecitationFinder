import Foundation
import Combine

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

/// Benutzereinstellungen, dauerhaft gespeichert in UserDefaults.
final class AppSettings: ObservableObject {
    private enum Keys {
        static let language = "settings.translationLanguage"
        static let maxRecording = "settings.maxRecordingSeconds"
    }

    static let recordingRange = 5...30
    static let defaultMaxRecordingSeconds = 12

    private let defaults: UserDefaults

    @Published var translationLanguage: TranslationLanguage {
        didSet { defaults.set(translationLanguage.rawValue, forKey: Keys.language) }
    }

    /// Aufnahme stoppt spätestens nach dieser Zeit (Whisper verarbeitet max. 30 s am Stück).
    @Published var maxRecordingSeconds: Int {
        didSet {
            let clamped = min(max(maxRecordingSeconds, Self.recordingRange.lowerBound), Self.recordingRange.upperBound)
            // Zuweisung in didSet löst didSet nicht erneut aus – daher direkt danach speichern
            if clamped != maxRecordingSeconds { maxRecordingSeconds = clamped }
            defaults.set(maxRecordingSeconds, forKey: Keys.maxRecording)
        }
    }

    init(defaults: UserDefaults = .standard, locale: Locale = .current) {
        self.defaults = defaults
        if let stored = defaults.string(forKey: Keys.language),
           let language = TranslationLanguage(rawValue: stored) {
            translationLanguage = language
        } else {
            translationLanguage = .preferred(for: locale)
        }
        let storedSeconds = defaults.integer(forKey: Keys.maxRecording)
        maxRecordingSeconds = Self.recordingRange.contains(storedSeconds) ? storedSeconds : Self.defaultMaxRecordingSeconds
    }
}
