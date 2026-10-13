import Foundation

/// Wandelt eine Aufnahme (16 kHz mono) in arabischen Text um.
///
/// Phase 3 liefert die echte Umsetzung (WhisperKit + Tarteel-Modell).
/// Die Oberfläche hängt nur an diesem Protokoll.
nonisolated protocol RecitationRecognizer: Sendable {
    /// Kurzname für Einstellungen/Lizenzen, z. B. "Tarteel Whisper base".
    var displayName: String { get }
    func transcribe(samples: [Float], sampleRate: Double) async throws -> String
}

nonisolated enum RecognitionError: LocalizedError, Equatable {
    case notAvailable
    case tooShort
    case noSpeech

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Die Spracherkennung ist noch nicht eingebaut (Phase 3). Zum Testen: „Text eingeben“."
        case .tooShort:
            return "Die Aufnahme ist zu kurz. Bitte mindestens 2 Sekunden aufnehmen."
        case .noSpeech:
            return "In der Aufnahme wurde keine Rezitation erkannt."
        }
    }
}

/// Platzhalter bis Phase 3.
nonisolated struct UnavailableRecognizer: RecitationRecognizer {
    let displayName = "noch nicht eingebaut"

    func transcribe(samples: [Float], sampleRate: Double) async throws -> String {
        throw RecognitionError.notAvailable
    }
}
