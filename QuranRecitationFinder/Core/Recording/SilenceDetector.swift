import Foundation

/// Erkennt das Ende einer Rezitation am Aufnahmepegel (0…1, wie `AudioCapturing.level`).
///
/// Gestoppt wird erst, wenn vorher genug Rezitation lief und danach länger Ruhe ist,
/// als eine normale Atempause (Waqf) dauert.
nonisolated struct SilenceDetector: Sendable {
    nonisolated struct Configuration: Sendable, Equatable {
        /// Ab diesem Pegel gilt es als Rezitation (≈ −27 dB).
        var speechLevel: Float = 0.55
        /// Unter diesem Pegel gilt es als Ruhe (≈ −36 dB). Dazwischen: unverändert (Hysterese).
        var silenceLevel: Float = 0.40
        /// So viel Rezitation muss vorher gelaufen sein.
        var minimumSpeech: TimeInterval = 3.0
        /// So lange muss es danach ruhig sein (Atempausen beim Rezitieren: 1–2 s).
        var silenceDuration: TimeInterval = 2.5
    }

    let configuration: Configuration
    private(set) var speechSeconds: TimeInterval = 0
    private(set) var silenceSeconds: TimeInterval = 0
    private var lastTime: TimeInterval?

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Neuer Messwert. Rückgabe `true` = Aufnahme beenden.
    mutating func update(level: Float, at time: TimeInterval) -> Bool {
        defer { lastTime = time }
        guard let last = lastTime else { return false }
        // Lücken bis 1 s zählen voll (Gerät kurz ausgelastet); längere Unterbrechungen
        // (z. B. App im Hintergrund) werden ignoriert statt als Rezitation/Stille gezählt.
        let gap = time - last
        let dt = (gap > 0 && gap <= 1.0) ? gap : 0
        if level >= configuration.speechLevel {
            speechSeconds += dt
            silenceSeconds = 0
        } else if level < configuration.silenceLevel {
            silenceSeconds += dt
        }
        return speechSeconds >= configuration.minimumSpeech && silenceSeconds >= configuration.silenceDuration
    }

    mutating func reset() {
        speechSeconds = 0
        silenceSeconds = 0
        lastTime = nil
    }
}
