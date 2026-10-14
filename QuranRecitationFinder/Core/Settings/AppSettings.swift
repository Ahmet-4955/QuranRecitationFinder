import Foundation
import Combine

/// Benutzereinstellungen, dauerhaft gespeichert in UserDefaults.
final class AppSettings: ObservableObject {
    private enum Keys {
        static let language = "settings.translationLanguage"
        static let maxRecording = "settings.maxRecordingSeconds"
        static let autoStop = "settings.autoStopOnSilence"
        static let early = "settings.earlyRecognition"
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

    /// Aufnahme endet von selbst, wenn die Rezitation aufhört.
    @Published var autoStopOnSilence: Bool {
        didSet { defaults.set(autoStopOnSilence, forKey: Keys.autoStop) }
    }

    /// Schon während der Aufnahme erkennen und bei sicherem Ergebnis vorzeitig beenden.
    @Published var earlyRecognition: Bool {
        didSet { defaults.set(earlyRecognition, forKey: Keys.early) }
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
        autoStopOnSilence = defaults.object(forKey: Keys.autoStop) as? Bool ?? true
        earlyRecognition = defaults.object(forKey: Keys.early) as? Bool ?? true
    }
}
