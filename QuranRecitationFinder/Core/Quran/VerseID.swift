import Foundation

/// Eindeutige Adresse eines Verses, z. B. 2:255.
nonisolated struct VerseID: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    let surah: Int
    let ayah: Int

    init(surah: Int, ayah: Int) {
        self.surah = surah
        self.ayah = ayah
    }

    /// Erwartet das Format "2:255".
    init?(_ string: String) {
        let parts = string.split(separator: ":")
        guard parts.count == 2, let s = Int(parts[0]), let a = Int(parts[1]) else { return nil }
        self.init(surah: s, ayah: a)
    }

    var description: String { "\(surah):\(ayah)" }

    static func < (lhs: VerseID, rhs: VerseID) -> Bool {
        (lhs.surah, lhs.ayah) < (rhs.surah, rhs.ayah)
    }
}

/// Zusammenhängender Versbereich, z. B. 2:255–2:256.
nonisolated struct VerseRange: Hashable, Codable, Sendable, CustomStringConvertible {
    let start: VerseID
    let end: VerseID

    init(start: VerseID, end: VerseID) {
        precondition(start <= end, "VerseRange: start nach end")
        self.start = start
        self.end = end
    }

    init(_ verse: VerseID) {
        self.init(start: verse, end: verse)
    }

    func contains(_ verse: VerseID) -> Bool {
        start <= verse && verse <= end
    }

    var description: String {
        start == end ? start.description : "\(start)–\(end)"
    }
}
