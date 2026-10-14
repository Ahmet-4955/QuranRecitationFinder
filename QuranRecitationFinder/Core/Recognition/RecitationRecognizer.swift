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
            return String(format: NSLocalizedString("Speech recognition not available (phase 3): %@ For testing: “Enter text”.", comment: ""), reason)
        case .tooShort:
            return NSLocalizedString("The recording is too short. Please record at least 2 seconds.", comment: "")
        case .noSpeech:
            return NSLocalizedString("No recitation was recognized in the recording.", comment: "")
        case .unsupportedSampleRate:
            return NSLocalizedString("Internal error: recording is not 16 kHz.", comment: "")
        }
    }
}

/// Platzhalter, solange WhisperKit oder das Modell fehlt.
nonisolated struct UnavailableRecognizer: RecitationRecognizer {
    let reason: String

    init(reason: String = NSLocalizedString("Not built in yet.", comment: "")) {
        self.reason = reason
    }

    var displayName: String { NSLocalizedString("not available", comment: "") }

    func transcribe(samples: [Float], sampleRate: Double) async throws -> String {
        throw RecognitionError.notAvailable(reason)
    }
}
