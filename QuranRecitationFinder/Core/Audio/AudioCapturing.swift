import Foundation

/// Aufnahmeformat für die Spracherkennung (Whisper erwartet 16 kHz mono).
nonisolated enum AudioFormat {
    static let sampleRate: Double = 16_000
}

/// Aufnahme-Schnittstelle (für Tests austauschbar).
protocol AudioCapturing: AnyObject {
    /// Pegel 0…1 für die Anzeige.
    var level: Float { get }
    /// Bisher aufgenommene Sekunden.
    var elapsed: TimeInterval { get }
    func requestPermission() async -> Bool
    func start() throws
    /// Bisherige Samples, ohne die Aufnahme zu beenden (für die Früherkennung).
    func snapshot() -> [Float]
    /// Beendet die Aufnahme und liefert die Samples (16 kHz, mono, Float32).
    func stop() -> [Float]
}

nonisolated enum AudioCaptureError: LocalizedError {
    case permissionDenied
    case formatUnavailable
    case engineFailed(Error)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return NSLocalizedString("No microphone access. Please allow it in Settings → Privacy & Security → Microphone.", comment: "")
        case .formatUnavailable:
            return NSLocalizedString("The microphone does not provide a usable audio format.", comment: "")
        case .engineFailed(let error):
            return String(format: NSLocalizedString("Recording could not be started: %@", comment: ""), error.localizedDescription)
        }
    }
}
