import Foundation

/// Der gesamte Koran als eine durchgehende Wortfolge (~77.400 Wörter)
/// mit Fundstellen-Index und IDF-Gewichten.
nonisolated struct QuranWordIndex: Sendable {
    nonisolated enum Edition: String, Sendable {
        /// Tanzil Simple Clean – Standardschreibweise (Voreinstellung)
        case simpleClean
        /// Tanzil Uthmani – falls Phase 0 zeigt, dass die Erkennung diese Schreibweise liefert
        case uthmani
    }

    let edition: Edition
    /// Normalisierte Wörter in Koranreihenfolge.
    let words: [String]
    let wordUnits: [WordSimilarity.Units]
    /// Globaler Versindex (0…6235) je Wort.
    let wordVerse: [Int32]
    /// Fundstellen je Wort (Positionen in `words`).
    let positions: [String: [Int32]]
    /// log(Gesamtwörter / Häufigkeit) – seltene Wörter zählen mehr.
    let idf: [String: Float]
    /// Wortschatz (jedes Wort einmal), für die Ähnlichkeitssuche.
    let vocabulary: [String]
    let vocabularyUnits: [WordSimilarity.Units]

    init(quran: QuranText, edition: Edition = .simpleClean) {
        var words: [String] = []
        var wordVerse: [Int32] = []
        words.reserveCapacity(80_000)
        wordVerse.reserveCapacity(80_000)
        for index in 0..<QuranText.verseCount {
            guard let verse = quran.verse(atGlobalIndex: index) else { continue }
            let text = (edition == .uthmani ? quran.displayText(verse) : quran.searchText(verse)) ?? ""
            for word in ArabicNormalizer.words(text) {
                words.append(word)
                wordVerse.append(Int32(index))
            }
        }

        var positions: [String: [Int32]] = [:]
        var vocabulary: [String] = []
        for (p, word) in words.enumerated() {
            if positions[word] == nil { vocabulary.append(word) }
            positions[word, default: []].append(Int32(p))
        }
        let total = Float(words.count)
        var idf: [String: Float] = [:]
        for (word, list) in positions {
            idf[word] = log(total / Float(list.count))
        }

        self.edition = edition
        self.words = words
        self.wordUnits = words.map(WordSimilarity.units)
        self.wordVerse = wordVerse
        self.positions = positions
        self.idf = idf
        self.vocabulary = vocabulary
        self.vocabularyUnits = vocabulary.map(WordSimilarity.units)
    }
}
