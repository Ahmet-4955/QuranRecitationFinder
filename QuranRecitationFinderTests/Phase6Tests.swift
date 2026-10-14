import Foundation
import Testing
@testable import QuranRecitationFinder

/// Tests Phase 6: Stille-Erkennung, Früherkennung, Teilen (laufen auch unter Linux).
struct SilenceDetectorTests {
    /// Pegelverlauf in 50-ms-Schritten abspielen; Rückgabe: Zeitpunkt des Stopps oder nil.
    private func run(_ segments: [(seconds: Double, level: Float)]) -> TimeInterval? {
        var detector = SilenceDetector()
        var t: TimeInterval = 0
        for segment in segments {
            let end = t + segment.seconds
            while t < end - 1e-9 {
                if detector.update(level: segment.level, at: t) { return t }
                t += 0.05
            }
        }
        return nil
    }

    @Test func stopsAfterRecitationAndSilence() throws {
        let stop = try #require(run([(4, 0.7), (4, 0.15)]))
        #expect(stop > 6.4 && stop < 6.7)  // 4 s Rezitation + 2,5 s Ruhe
    }

    @Test func breathingPausesDoNotStop() {
        // Rezitation mit 1,5-s-Atempausen (Waqf) darf nicht abbrechen
        #expect(run([(3, 0.7), (1.5, 0.1), (3, 0.7), (1.5, 0.1), (3, 0.7)]) == nil)
    }

    @Test func silenceBeforeRecitationDoesNotStop() {
        // Nutzer tippt Start, Rezitation beginnt erst nach 4 s
        #expect(run([(4, 0.1), (2, 0.7)]) == nil)
    }

    @Test func tooLittleRecitationDoesNotStop() {
        #expect(run([(1.5, 0.7), (5, 0.1)]) == nil)
    }

    @Test func longInterruptionIsIgnored() {
        // App 5 s im Hintergrund: weder als Rezitation noch als Stille zählen
        var detector = SilenceDetector()
        _ = detector.update(level: 0.7, at: 0)
        _ = detector.update(level: 0.7, at: 5)
        #expect(detector.speechSeconds == 0)
        _ = detector.update(level: 0.7, at: 5.8)
        #expect(abs(detector.speechSeconds - 0.8) < 1e-9)
    }

    @Test func steadyBackgroundNoiseNeverStops() {
        // z. B. Auto: Pegel dauerhaft zwischen den Schwellen → Höchstdauer greift
        #expect(run([(4, 0.7), (10, 0.48)]) == nil)
    }
}

struct EarlyRecognitionPolicyTests {
    private func match(_ surah: Int, _ ayah: Int, score: Float, index: Int) -> VerseMatch {
        VerseMatch(range: VerseRange(VerseID(surah: surah, ayah: ayah)), score: score, matchedWords: 8,
                   startVerseIndex: index, endVerseIndex: index)
    }

    @Test func attemptSchedule() {
        var policy = EarlyRecognitionPolicy()
        #expect(!policy.shouldAttempt(elapsed: 4.9))
        #expect(policy.shouldAttempt(elapsed: 5.0))
        policy.didAttempt(at: 5.0)
        #expect(!policy.shouldAttempt(elapsed: 7.9))
        #expect(policy.shouldAttempt(elapsed: 8.0))
    }

    @Test func needsTwoConsistentConfidentResults() {
        var policy = EarlyRecognitionPolicy()
        let first = MatchOutcome.recognized([match(36, 1, score: 0.9, index: 3705)])
        do { let decided = policy.evaluate(first, wordCount: 7, acceptThreshold: 0.6); #expect(!decided) }
        do { let decided = policy.evaluate(first, wordCount: 10, acceptThreshold: 0.6); #expect(decided) }
    }

    @Test func differentPlacesResetTheCount() {
        var policy = EarlyRecognitionPolicy()
        let yasin = MatchOutcome.recognized([match(36, 1, score: 0.9, index: 3705)])
        let baqara = MatchOutcome.recognized([match(2, 1, score: 0.9, index: 7)])
        do { let decided = policy.evaluate(yasin, wordCount: 7, acceptThreshold: 0.6); #expect(!decided) }
        do { let decided = policy.evaluate(baqara, wordCount: 9, acceptThreshold: 0.6); #expect(!decided) }
        do { let decided = policy.evaluate(baqara, wordCount: 11, acceptThreshold: 0.6); #expect(decided) }
    }

    @Test func refusesWeakShortOrAmbiguousResults() {
        var policy = EarlyRecognitionPolicy()
        let weak = MatchOutcome.recognized([match(36, 1, score: 0.65, index: 3705)])  // < 0,6 + 0,1
        do { let decided = policy.evaluate(weak, wordCount: 10, acceptThreshold: 0.6); #expect(!decided) }
        do { let decided = policy.evaluate(weak, wordCount: 10, acceptThreshold: 0.6); #expect(!decided) }
        let strong = MatchOutcome.recognized([match(36, 1, score: 0.95, index: 3705)])
        do { let decided = policy.evaluate(strong, wordCount: 4, acceptThreshold: 0.6); #expect(!decided) }  // zu wenige Wörter
        do { let decided = policy.evaluate(strong, wordCount: 4, acceptThreshold: 0.6); #expect(!decided) }
        let ties = MatchOutcome.recognized([match(55, 13, score: 1, index: 4914), match(55, 16, score: 1, index: 4917)])
        do { let decided = policy.evaluate(ties, wordCount: 8, acceptThreshold: 0.6); #expect(!decided) }
        do { let decided = policy.evaluate(ties, wordCount: 8, acceptThreshold: 0.6); #expect(!decided) }
        do { let decided = policy.evaluate(.uncertain([]), wordCount: 8, acceptThreshold: 0.6); #expect(!decided) }
    }
}

struct VerseRangeContainsTests {
    @Test func containsIsInclusive() {
        let range = VerseRange(start: VerseID(surah: 1, ayah: 6), end: VerseID(surah: 2, ayah: 1))
        #expect(range.contains(VerseID(surah: 1, ayah: 6)))
        #expect(range.contains(VerseID(surah: 1, ayah: 7)))
        #expect(range.contains(VerseID(surah: 2, ayah: 1)))
        #expect(!range.contains(VerseID(surah: 1, ayah: 5)))
        #expect(!range.contains(VerseID(surah: 2, ayah: 2)))
    }
}

struct PassageShareTextTests {
    @Test func containsArabicTranslationAndSources() throws {
        let quran = try QuranText.load(from: .main)
        let store = try TranslationStore(bundle: .main)
        let info = try #require(store.info(forLanguage: "de"))
        let translation = try store.translation(forKey: info.key)
        let range = VerseRange(start: VerseID(surah: 1, ayah: 6), end: VerseID(surah: 1, ayah: 7))

        let text = PassageShareText.make(range: range, quran: quran, translation: translation)
        #expect(text.contains("1:6–1:7"))
        #expect(text.contains("(1:6) "))
        #expect(text.contains(try #require(quran.displayText(VerseID(surah: 1, ayah: 7)))))
        #expect(text.contains(try #require(translation.text(for: VerseID(surah: 1, ayah: 6)))))
        #expect(text.contains("Tanzil.net"))
        #expect(text.contains(info.version))
    }

    @Test func worksWithoutTranslation() throws {
        let quran = try QuranText.load(from: .main)
        let text = PassageShareText.make(range: VerseRange(VerseID(surah: 112, ayah: 1)), quran: quran, translation: nil)
        #expect(!text.contains("(112:1)"))  // Einzelvers ohne Nummernpräfix
        #expect(text.hasSuffix("— Korantext: Tanzil.net"))
    }
}
