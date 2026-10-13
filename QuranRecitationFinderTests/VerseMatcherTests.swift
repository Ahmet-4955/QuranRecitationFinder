import Foundation
import Testing
@testable import QuranRecitationFinder

/// Abnahmetests Phase 2: Verssuche.
/// Voraussetzung: Korantext im Bundle (Tools/data/build_resources.py).
enum SharedMatcher {
    /// Einmal aufbauen (Index über ~77.400 Wörter) und in allen Tests nutzen.
    static let result: Result<VerseMatcher, Error> = Result {
        try VerseMatcher(quran: QuranText.load(from: .main))
    }

    static func get() throws -> VerseMatcher {
        try result.get()
    }
}

/// Reproduzierbarer Zufall (SplitMix64), damit Testläufe vergleichbar bleiben.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct WordSimilarityTests {
    @Test func ratioMatchesRapidfuzz() {
        let u = WordSimilarity.units
        #expect(WordSimilarity.ratio(u("abc"), u("abc")) == 1)
        #expect(abs(WordSimilarity.ratio(u("abc"), u("abd")) - 2.0 / 3.0) < 1e-6)
        #expect(WordSimilarity.ratio(u("abc"), u("xyz")) == 0)
        #expect(WordSimilarity.ratio(u(""), u("abc")) == 0)
    }

    @Test func cutoffIsInclusiveAndExact() {
        let u = WordSimilarity.units
        // LCS 3, Gesamtlänge 8 → genau 75 %
        #expect(WordSimilarity.ratio(u("abcd"), u("abcx"), minimumPercent: 75) == 0.75)
        // LCS 2, Gesamtlänge 6 → 66,7 % < 75 %
        #expect(WordSimilarity.ratio(u("abc"), u("abx"), minimumPercent: 75) == nil)
    }
}

struct VerseMatcherTests {
    private func startRefs(_ matches: [VerseMatch]) -> [String] {
        matches.map(\.range.start.description)
    }

    @Test(arguments: [
        ("الله لا اله الا هو الحي القيوم لا تاخذه سنه ولا نوم", "2:255"),
        ("قل هو الله احد الله الصمد", "112:1"),
        ("والعصر ان الانسان لفي خسر", "103:1"),
        ("قل اعوذ برب الفلق من شر ما خلق", "113:1"),
    ])
    func knownPassages(text: String, expected: String) throws {
        let matcher = try SharedMatcher.get()
        guard case .recognized(let matches) = matcher.recognize(text) else {
            Issue.record("nicht erkannt: \(expected)")
            return
        }
        #expect(startRefs(matches).contains(expected))
        #expect((matches.first?.score ?? 0) > 0.8)
    }

    @Test(arguments: [
        "بسم الله الرحمن الرحيم ",
        "اعوذ بالله من الشيطان الرجيم بسم الله الرحمن الرحيم ",
        "اعوذ بلله من الشيطان الرجيم ",
    ])
    func openingFormulasDoNotLowerScore(prefix: String) throws {
        let matcher = try SharedMatcher.get()
        let best = try #require(matcher.match(prefix + "يس والقران الحكيم انك لمن المرسلين").first)
        #expect(best.range.start == VerseID(surah: 36, ayah: 1))
        #expect(best.score > 0.9)
    }

    @Test func fatihaWithBasmalaStartsAtFirstVerse() throws {
        let matcher = try SharedMatcher.get()
        let best = try #require(matcher.match("بسم الله الرحمن الرحيم الحمد لله رب العالمين الرحمن الرحيم").first)
        #expect(best.range.start == VerseID(surah: 1, ayah: 1))
    }

    @Test func basmalaAloneStillMatches() throws {
        let matcher = try SharedMatcher.get()
        #expect(startRefs(matcher.match("بسم الله الرحمن الرحيم", topK: 5)).contains("1:1"))
    }

    @Test func tooFewWordsAreOnlySuggestions() throws {
        let matcher = try SharedMatcher.get()
        if case .recognized = matcher.recognize("الحمد لله") {
            Issue.record("2 Wörter dürfen nicht als sicher erkannt gelten")
        }
    }

    @Test func excerptAcrossVerseBoundary() throws {
        let matcher = try SharedMatcher.get()
        let best = try #require(matcher.match("اهدنا الصراط المستقيم صراط الذين انعمت عليهم").first)
        #expect(best.range.start == VerseID(surah: 1, ayah: 6))
        #expect(best.range.end == VerseID(surah: 1, ayah: 7))
    }

    @Test func identicalWordingIsReportedAsTie() throws {
        let matcher = try SharedMatcher.get()
        guard case .recognized(let matches) = matcher.recognize("فباي الاء ربكما تكذبان") else {
            Issue.record("nicht erkannt")
            return
        }
        #expect(matches.count >= 3)
        #expect(matches.allSatisfy { $0.range.start.surah == 55 })
    }

    @Test func unrelatedArabicIsNotRecognized() throws {
        let matcher = try SharedMatcher.get()
        switch matcher.recognize("هذا نص عربي حديث عن الهاتف والسيارة والحاسوب") {
        case .recognized(let matches):
            Issue.record("fälschlich erkannt: \(startRefs(matches))")
        case .uncertain, .nothing:
            break
        }
    }

    @Test func emptyOrNonArabicInput() throws {
        let matcher = try SharedMatcher.get()
        #expect(matcher.match("").isEmpty)
        #expect(matcher.match("hello world 123").isEmpty)
        if case .nothing = matcher.recognize("") {} else { Issue.record("leere Eingabe muss .nothing liefern") }
    }

    /// Typische Erkennungsfehler: Buchstabe vertauscht, Wort fehlt, fremdes Wort eingefügt
    /// (wie _corrupt in Tools/phase0/tests/test_matcher.py).
    private func corrupt(_ words: [String], rate: Double, vocabulary: [String], rng: inout SeededGenerator) -> [String] {
        let letters = Array("ابتثجحخدذرزسشصضطظعغفقكلمنهوي")
        var out: [String] = []
        for word in words {
            let r = Double.random(in: 0..<1, using: &rng)
            if r < rate / 3 { continue }
            var w = word
            if r < 2 * rate / 3, w.count > 2 {
                var chars = Array(w)
                chars[Int.random(in: 0..<chars.count, using: &rng)] = letters.randomElement(using: &rng)!
                w = String(chars)
            }
            out.append(w)
            if Double.random(in: 0..<1, using: &rng) < rate / 3 {
                out.append(vocabulary.randomElement(using: &rng)!)
            }
        }
        return out
    }

    /// Abnahmekriterium Phase 2: fehlerhafte Ausschnitte → richtiger Vers.
    @Test(arguments: [(6, 0.15, 0.85), (12, 0.2, 0.95), (20, 0.3, 0.95)])
    func randomExcerptsWithErrors(length: Int, rate: Double, minimumAccuracy: Double) throws {
        let matcher = try SharedMatcher.get()
        let index = matcher.index
        var rng = SeededGenerator(seed: UInt64(42 + length))
        let trials = 60  // Debug-Builds sind langsam; Python-Prototyp prüft 200 je Fall
        var hits = 0
        for _ in 0..<trials {
            let start = Int.random(in: 0..<(index.words.count - length), using: &rng)
            let trueStart = Int(index.wordVerse[start])
            let trueEnd = Int(index.wordVerse[start + length - 1])
            let noisy = corrupt(Array(index.words[start..<(start + length)]), rate: rate,
                                vocabulary: index.vocabulary, rng: &rng)
            let results = matcher.match(noisy.joined(separator: " "))
            guard let best = results.first else { continue }
            let tied = results.filter { $0.score >= best.score - matcher.configuration.tieMargin }
            if tied.contains(where: { $0.startVerseIndex <= trueEnd && trueStart <= $0.endVerseIndex }) {
                hits += 1
            }
        }
        let accuracy = Double(hits) / Double(trials)
        #expect(accuracy >= minimumAccuracy, "Länge \(length), Fehlerrate \(rate): \(accuracy)")
    }

    /// Swift und Python-Prototyp müssen dasselbe liefern (Fälle aus export_swift_fixtures.py).
    @Test(.enabled(if: !MatcherFixtures.cases.isEmpty, "MatcherFixtures noch nicht erzeugt"))
    func matchesPythonPrototype() throws {
        let matcher = try SharedMatcher.get()
        for fixture in MatcherFixtures.cases {
            let best = try #require(matcher.match(fixture.query, topK: 5).first, "kein Treffer: \(fixture.query)")
            #expect(abs(best.score - fixture.bestScore) < 0.005, "Score \(best.score) statt \(fixture.bestScore)")
            #expect(fixture.acceptableStarts.contains(best.range.start.description),
                    "\(best.range.start) nicht in \(fixture.acceptableStarts)")
        }
    }
}
