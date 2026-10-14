import Foundation

/// Ähnlichkeit zweier Wörter, 0…1.
///
/// Entspricht `rapidfuzz.fuzz.ratio / 100` aus dem Python-Prototyp:
/// 2 · (längste gemeinsame Teilfolge) / (Länge a + Länge b).
nonisolated enum WordSimilarity {
    /// Wort als Folge von UTF-16-Einheiten (normalisierte arabische Buchstaben liegen alle im BMP).
    typealias Units = [UInt16]

    static func units(_ word: String) -> Units {
        Array(word.utf16)
    }

    static func ratio(_ a: Units, _ b: Units) -> Float {
        let total = a.count + b.count
        if total == 0 { return 1 }
        if a.isEmpty || b.isEmpty { return 0 }
        return Float(2 * lcsLength(a, b)) / Float(total)
    }

    /// Ähnlichkeit, falls sie mindestens `minimumPercent` % erreicht – sonst nil.
    /// Vergleich exakt in Ganzzahlen (wie rapidfuzz `score_cutoff`).
    static func ratio(_ a: Units, _ b: Units, minimumPercent: Int) -> Float? {
        let total = a.count + b.count
        guard total > 0, !a.isEmpty, !b.isEmpty else { return total == 0 ? 1 : nil }
        guard 200 * min(a.count, b.count) >= minimumPercent * total else { return nil }
        let lcs = lcsLength(a, b)
        guard 200 * lcs >= minimumPercent * total else { return nil }
        return Float(2 * lcs) / Float(total)
    }

    private static func lcsLength(_ a: Units, _ b: Units) -> Int {
        var row = [Int](repeating: 0, count: b.count + 1)
        for ca in a {
            var diagonal = 0
            for j in 1...b.count {
                let above = row[j]
                row[j] = ca == b[j - 1] ? diagonal + 1 : max(above, row[j - 1])
                diagonal = above
            }
        }
        return row[b.count]
    }
}
