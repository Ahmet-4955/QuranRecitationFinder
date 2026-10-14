import Foundation

/// Wandelt eine Aufnahme (16 kHz mono) in arabischen Text um.
/// Die Oberfläche hängt nur an diesem Protokoll.
nonisolated protocol RecitationRecognizer: Sendable {
    /// Kurzname für Einstellungen/Lizenzen, z. B. "Tarteel Whisper base".
    var displayName: String { get }
    /// Quellen-/Lizenzzeilen für „Quellen & Lizenzen“.
    var credits: [String] { get }
    /// Modell vorab laden (beim App-Start im Hintergrund), damit die erste Erkennung schnell ist.
    func prepare() async throws
    func transcribe(samples: [Float], sampleRate: Double) async throws -> String
}

extension RecitationRecognizer {
    nonisolated var credits: [String] { [] }
    nonisolated func prepare() async throws {}
}

nonisolated enum RecognitionError: LocalizedError, Equatable {
    case notAvailable(String)
    case tooShort
    case noSpeech
    case unsupportedSampleRate

    var errorDescription: String? {
        switch self {
        case .notAvailable(let reason):
            return "Spracherkennung nicht verfügbar (Phase 3): \(reason) Zum Testen: „Text eingeben“."
        case .tooShort:
            return "Die Aufnahme ist zu kurz. Bitte mindestens 2 Sekunden aufnehmen."
        case .noSpeech:
            return "In der Aufnahme wurde keine Rezitation erkannt."
        case .unsupportedSampleRate:
            return "Interner Fehler: Aufnahme nicht in 16 kHz."
        }
    }
}

/// Platzhalter, solange WhisperKit oder das Modell fehlt.
nonisolated struct UnavailableRecognizer: RecitationRecognizer {
    let reason: String

    init(reason: String = "Noch nicht eingebaut.") {
        self.reason = reason
    }

    var displayName: String { "nicht verfügbar" }

    func transcribe(samples: [Float], sampleRate: Double) async throws -> String {
        throw RecognitionError.notAvailable(reason)
    }
}
