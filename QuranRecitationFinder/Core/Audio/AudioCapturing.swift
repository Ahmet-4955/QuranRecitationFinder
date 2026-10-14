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
            return "Kein Mikrofonzugriff. Bitte in Einstellungen → Datenschutz → Mikrofon erlauben."
        case .formatUnavailable:
            return "Das Mikrofon liefert kein nutzbares Audioformat."
        case .engineFailed(let error):
            return "Aufnahme konnte nicht gestartet werden: \(error.localizedDescription)"
        }
    }
}
