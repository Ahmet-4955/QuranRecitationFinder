import Foundation

/// Entscheidet, wann während der Aufnahme schon erkannt wird – und wann das Ergebnis
/// so sicher ist, dass die Aufnahme vorzeitig enden darf.
///
/// Strenger als die normale Anzeige: eindeutige Stelle, genug Wörter, Score deutlich über
/// der Schwelle und zweimal hintereinander dieselbe Stelle.
nonisolated struct EarlyRecognitionPolicy: Sendable {
    nonisolated struct Configuration: Sendable, Equatable {
        /// Erster Versuch nach so vielen Sekunden Aufnahme.
        var firstAttemptAfter: TimeInterval = 5
        /// Abstand zwischen den Versuchen.
        var interval: TimeInterval = 3
        /// Mindestanzahl erkannter Wörter (ohne Eröffnungsformeln).
        var minimumWords = 6
        /// So viel muss der Score über der normalen Schwelle liegen.
        var scoreMargin: Float = 0.1
        /// So oft hintereinander muss dieselbe Stelle herauskommen.
        var requiredConsecutive = 2
    }

    let configuration: Configuration
    private(set) var lastAttempt: TimeInterval?
    private(set) var consecutive = 0
    private var previousBest: VerseMatch?

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    func shouldAttempt(elapsed: TimeInterval) -> Bool {
        guard elapsed >= configuration.firstAttemptAfter else { return false }
        guard let last = lastAttempt else { return true }
        return elapsed - last >= configuration.interval
    }

    mutating func didAttempt(at elapsed: TimeInterval) {
        lastAttempt = elapsed
    }

    /// Wertet einen Zwischenstand aus. Rückgabe `true` = Ergebnis steht fest, Aufnahme beenden.
    mutating func evaluate(_ outcome: MatchOutcome, wordCount: Int, acceptThreshold: Float) -> Bool {
        guard case .recognized(let matches) = outcome,
              matches.count == 1,  // gleichlautende Stellen: weitere Wörter abwarten
              let best = matches.first,
              wordCount >= configuration.minimumWords,
              best.score >= acceptThreshold + configuration.scoreMargin else {
            consecutive = 0
            previousBest = nil
            return false
        }
        if let previous = previousBest, previous.overlaps(best) {
            consecutive += 1
        } else {
            consecutive = 1
        }
        previousBest = best
        return consecutive >= configuration.requiredConsecutive
    }

    mutating func reset() {
        lastAttempt = nil
        consecutive = 0
        previousBest = nil
    }
}
