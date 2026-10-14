import Foundation

/// Kalibrierte Einstellwerte der Verssuche (Resources/recognition-config.json).
///
/// Wird von Tools/phase5/calibrate.py aus den Messungen erzeugt – so ändert die
/// Kalibrierung nur eine Datei, keinen Code. Fehlt die Datei, gelten die Standardwerte.
nonisolated struct RecognitionConfig: Codable, Sendable, Equatable {
    var acceptThreshold: Float = 0.6
    var tieMargin: Float = 0.01
    var minimumWordsForRecognition = 3
    /// "simpleClean" oder "uthmani" – welche Schreibweise die Verssuche vergleicht.
    var edition: String = "simpleClean"
    /// Nachvollziehbarkeit: woher die Werte stammen.
    var calibratedAt: String?
    var calibrationNote: String?

    static let fileName = "recognition-config.json"

    var matcherEdition: QuranWordIndex.Edition {
        edition == "uthmani" ? .uthmani : .simpleClean
    }

    var matcherConfiguration: VerseMatcher.Configuration {
        var configuration = VerseMatcher.Configuration()
        configuration.acceptThreshold = acceptThreshold
        configuration.tieMargin = tieMargin
        configuration.minimumWordsForRecognition = minimumWordsForRecognition
        return configuration
    }

    /// Liest die Datei aus dem Bundle; bei Fehlen oder Fehlern Standardwerte.
    static func load(from bundle: Bundle = .main) -> RecognitionConfig {
        guard let url = try? ResourceLocator.url(for: fileName, in: bundle),
              let data = try? Data(contentsOf: url) else {
            return RecognitionConfig()
        }
        return (try? JSONDecoder().decode(RecognitionConfig.self, from: data)) ?? RecognitionConfig()
    }

    init() {}

    /// Fehlende Felder in der Datei → Standardwert (robust gegen ältere/kürzere Dateien).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = RecognitionConfig()
        acceptThreshold = try c.decodeIfPresent(Float.self, forKey: .acceptThreshold) ?? defaults.acceptThreshold
        tieMargin = try c.decodeIfPresent(Float.self, forKey: .tieMargin) ?? defaults.tieMargin
        minimumWordsForRecognition = try c.decodeIfPresent(Int.self, forKey: .minimumWordsForRecognition)
            ?? defaults.minimumWordsForRecognition
        edition = try c.decodeIfPresent(String.self, forKey: .edition) ?? defaults.edition
        calibratedAt = try c.decodeIfPresent(String.self, forKey: .calibratedAt)
        calibrationNote = try c.decodeIfPresent(String.self, forKey: .calibrationNote)
    }
}
