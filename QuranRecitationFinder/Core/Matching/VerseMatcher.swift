import Foundation

/// Ein gefundener Koranabschnitt.
nonisolated struct VerseMatch: Hashable, Sendable {
    let range: VerseRange
    /// Trefferquote 0…1 (1 = jedes Wort exakt gefunden).
    let score: Float
    /// Anzahl erkannter Wörter, die (fast) exakt zum Koran passen.
    let matchedWords: Int
    /// Globale Versindizes (0…6235) für Überlappungsprüfungen.
    let startVerseIndex: Int
    let endVerseIndex: Int

    func overlaps(_ other: VerseMatch) -> Bool {
        startVerseIndex <= other.endVerseIndex && other.startVerseIndex <= endVerseIndex
    }
}

/// Ergebnis für die Oberfläche.
nonisolated enum MatchOutcome: Sendable {
    /// Sicher erkannt. Mehrere Einträge = gleichlautende Stellen (z. B. 55:13 kommt 31-mal vor).
    case recognized([VerseMatch])
    /// Unterhalb der Schwelle – Vorschläge, aber nicht als Treffer anzeigen.
    case uncertain([VerseMatch])
    /// Kein verwertbarer arabischer Text oder kein Kandidat.
    case nothing
}

/// Verssuche: erkannten (fehlerbehafteten) Text im gesamten Koran finden.
///
/// Swift-Umsetzung von Tools/phase0/quran_matcher.py – Konstanten und Ablauf
/// identisch, damit die Phase-0-Messwerte für die App gelten:
/// 1. Kandidatensuche: jedes (ähnliche) Wort stimmt für eine Startposition, IDF-gewichtet.
/// 2. Feinabgleich: Smith-Waterman auf Wortebene um die besten Kandidaten.
nonisolated final class VerseMatcher: @unchecked Sendable {
    nonisolated struct Configuration: Sendable {
        var gapPenalty: Float = -0.6
        /// Mindestähnlichkeit für "ähnliches Wort" in Prozent (wie rapidfuzz score_cutoff).
        var fuzzyCutoffPercent: Int = 75
        var fuzzyLimit = 8
        /// Toleranz für eingefügte/fehlende Wörter (± Wörter).
        var voteSmoothing = 3
        var maxCandidates = 15
        var windowMargin = 12
        /// Ab dieser Trefferquote gilt ein Ergebnis als erkannt. Startwert, wird mit Phase 0 kalibriert.
        var acceptThreshold: Float = 0.6
        /// Abstand, innerhalb dessen Treffer als gleichwertig gelten.
        var tieMargin: Float = 0.01
    }

    let index: QuranWordIndex
    let configuration: Configuration
    private let quran: QuranText
    private let lock = NSLock()
    private var expandCache: [String: [(word: String, similarity: Float)]] = [:]

    init(quran: QuranText, edition: QuranWordIndex.Edition = .simpleClean, configuration: Configuration = Configuration()) {
        self.quran = quran
        self.index = QuranWordIndex(quran: quran, edition: edition)
        self.configuration = configuration
    }

    // MARK: - Öffentliche Schnittstelle

    /// Bewertete Ergebnis-Liste, beste zuerst; sich überlappende Treffer zusammengefasst.
    func match(_ text: String, topK: Int = 3) -> [VerseMatch] {
        let query = ArabicNormalizer.words(text)
        guard !query.isEmpty else { return [] }
        let queryUnits = query.map(WordSimilarity.units)

        var results: [VerseMatch] = []
        for start in candidateStarts(query: query) {
            let lo = max(0, start - configuration.windowMargin)
            let hi = min(index.words.count, start + query.count + configuration.windowMargin)
            guard lo < hi else { continue }
            let alignment = align(query: queryUnits, window: Array(index.wordUnits[lo..<hi]))
            guard alignment.score > 0 else { continue }
            let first = lo + alignment.windowStart
            let last = lo + alignment.windowEnd
            let startVerse = Int(index.wordVerse[first])
            let endVerse = Int(index.wordVerse[last])
            guard let startID = quran.verse(atGlobalIndex: startVerse),
                  let endID = quran.verse(atGlobalIndex: endVerse) else { continue }
            results.append(
                VerseMatch(
                    range: VerseRange(start: startID, end: endID),
                    score: min(1, alignment.score / Float(query.count)),
                    matchedWords: alignment.matched,
                    startVerseIndex: startVerse,
                    endVerseIndex: endVerse
                )
            )
        }

        // stabil nach Score sortieren (wie Python list.sort)
        let sorted = results.enumerated()
            .sorted { $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset }
            .map(\.element)
        var unique: [VerseMatch] = []
        for candidate in sorted where !unique.contains(where: { $0.overlaps(candidate) }) {
            unique.append(candidate)
            if unique.count >= topK { break }
        }
        return unique
    }

    /// Ergebnis mit Schwelle und Gleichstand-Erkennung – für die Anzeige.
    func recognize(_ text: String) -> MatchOutcome {
        let results = match(text, topK: 5)
        guard let best = results.first else { return .nothing }
        guard best.score >= configuration.acceptThreshold else {
            return .uncertain(Array(results.prefix(3)))
        }
        return .recognized(results.filter { $0.score >= best.score - configuration.tieMargin })
    }

    // MARK: - Kandidatensuche

    /// Exaktes Wort plus ähnliche Wörter aus dem Koran-Wortschatz (wie rapidfuzz process.extract).
    func expand(_ word: String) -> [(word: String, similarity: Float)] {
        lock.lock()
        if let cached = expandCache[word] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let units = WordSimilarity.units(word)
        var result: [(word: String, similarity: Float)] = []
        if units.count <= 2 {
            if index.positions[word] != nil { result = [(word, 1)] }
        } else {
            var hits: [(offset: Int, ratio: Float)] = []
            for (offset, candidate) in index.vocabularyUnits.enumerated() {
                if let r = WordSimilarity.ratio(units, candidate, minimumPercent: configuration.fuzzyCutoffPercent) {
                    hits.append((offset, r))
                }
            }
            hits.sort { $0.ratio != $1.ratio ? $0.ratio > $1.ratio : $0.offset < $1.offset }
            result = hits.prefix(configuration.fuzzyLimit).map { (index.vocabulary[$0.offset], $0.ratio) }
        }

        lock.lock()
        expandCache[word] = result
        lock.unlock()
        return result
    }

    func candidateStarts(query: [String]) -> [Int] {
        let n = index.words.count
        var votes = [Float](repeating: 0, count: n + query.count + 1)
        var any = false
        for (i, word) in query.enumerated() {
            for (variant, similarity) in expand(word) {
                guard let positions = index.positions[variant], let idf = index.idf[variant] else { continue }
                let weight = idf * similarity * similarity
                for p in positions {
                    let start = Int(p) - i
                    if start >= 0 {
                        votes[start] += weight
                        any = true
                    }
                }
            }
        }
        guard any else { return [] }

        // Glättung: Summe über ±voteSmoothing (entspricht np.convolve(..., mode="same"))
        let count = votes.count
        var prefix = [Float](repeating: 0, count: count + 1)
        for k in 0..<count { prefix[k + 1] = prefix[k] + votes[k] }
        let s = configuration.voteSmoothing
        var smoothed: [(position: Int, value: Float)] = []
        for k in 0..<count {
            let value = prefix[min(count, k + s + 1)] - prefix[max(0, k - s)]
            if value > 1e-6 { smoothed.append((k, value)) }
        }
        smoothed.sort { $0.value != $1.value ? $0.value > $1.value : $0.position > $1.position }

        // Nicht-Maximum-Unterdrückung im Abstand der Anfragelänge
        let minDistance = max(query.count, 4)
        var chosen: [Int] = []
        for candidate in smoothed.prefix(configuration.maxCandidates * 50) {
            if chosen.allSatisfy({ abs(candidate.position - $0) >= minDistance }) {
                chosen.append(candidate.position)
                if chosen.count >= configuration.maxCandidates { break }
            }
        }
        return chosen
    }

    // MARK: - Feinabgleich

    nonisolated struct Alignment {
        let score: Float
        let windowStart: Int
        let windowEnd: Int
        let matched: Int
    }

    /// Smith-Waterman auf Wortebene.
    func align(query: [WordSimilarity.Units], window: [WordSimilarity.Units]) -> Alignment {
        let rows = query.count, cols = window.count
        var sim = [[Float]](repeating: [Float](repeating: 0, count: cols), count: rows)
        for i in 0..<rows {
            for j in 0..<cols {
                sim[i][j] = WordSimilarity.ratio(query[i], window[j])
            }
        }
        let gap = configuration.gapPenalty
        var h = [[Float]](repeating: [Float](repeating: 0, count: cols + 1), count: rows + 1)
        var best: Float = 0, bestI = 0, bestJ = 0
        for i in 1...rows {
            for j in 1...cols {
                let value = max(
                    0,
                    h[i - 1][j - 1] + (2 * sim[i - 1][j - 1] - 1),
                    h[i - 1][j] + gap,
                    h[i][j - 1] + gap
                )
                h[i][j] = value
                if value > best {
                    best = value
                    bestI = i
                    bestJ = j
                }
            }
        }

        // Rückverfolgung für Startposition und Anzahl Treffer
        var i = bestI, j = bestJ, matched = 0
        while i > 0, j > 0, h[i][j] > 0 {
            if isClose(h[i][j], h[i - 1][j - 1] + (2 * sim[i - 1][j - 1] - 1)) {
                if sim[i - 1][j - 1] >= 0.75 { matched += 1 }
                i -= 1
                j -= 1
            } else if isClose(h[i][j], h[i - 1][j] + gap) {
                i -= 1
            } else {
                j -= 1
            }
        }
        return Alignment(score: best, windowStart: j, windowEnd: bestJ - 1, matched: matched)
    }

    /// wie numpy.isclose (rtol 1e-5, atol 1e-8)
    private func isClose(_ a: Float, _ b: Float) -> Bool {
        abs(a - b) <= 1e-8 + 1e-5 * abs(b)
    }
}
