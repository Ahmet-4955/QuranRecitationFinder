import Foundation

nonisolated struct SurahInfo: Hashable, Sendable, Identifiable {
    nonisolated enum Revelation: String, Sendable { case meccan, medinan }

    let number: Int
    let ayahCount: Int
    let arabicName: String
    let transliteratedName: String
    let englishName: String
    let revelation: Revelation

    var id: Int { number }
}

/// Vollständiger Korantext in zwei Tanzil-Ausgaben:
/// - `uthmani`: für die Anzeige
/// - `simpleClean`: Grundlage für die Verssuche
nonisolated struct QuranText: Sendable {
    static let surahCount = 114
    static let verseCount = 6236

    let surahs: [SurahInfo]
    private let uthmani: [[String]]
    private let simpleClean: [[String]]
    /// Globaler Index (0…6235) des ersten Verses jeder Sure.
    private let offsets: [Int]

    init(surahs: [SurahInfo], uthmani: [[String]], simpleClean: [[String]]) throws {
        guard surahs.count == Self.surahCount else {
            throw TanzilParser.ParseError.incomplete(String(format: NSLocalizedString("%@ surahs in the metadata", comment: ""), String(surahs.count)))
        }
        for (name, text) in [("uthmani", uthmani), ("simple-clean", simpleClean)] {
            guard text.count == Self.surahCount else {
                throw TanzilParser.ParseError.incomplete(String(format: NSLocalizedString("%1$@: %2$@ surahs", comment: ""), name, String(text.count)))
            }
            for (i, info) in surahs.enumerated() where text[i].count != info.ayahCount {
                throw TanzilParser.ParseError.incomplete(String(
                    format: NSLocalizedString("%1$@: surah %2$@ has %3$@ instead of %4$@ verses", comment: ""),
                    name, String(info.number), String(text[i].count), String(info.ayahCount)))
            }
        }
        self.surahs = surahs
        self.uthmani = uthmani
        self.simpleClean = simpleClean
        var running = 0
        offsets = surahs.map { info in
            defer { running += info.ayahCount }
            return running
        }
        guard running == Self.verseCount else {
            throw TanzilParser.ParseError.incomplete(String(format: NSLocalizedString("%1$@ verses instead of %2$@", comment: ""), String(running), String(Self.verseCount)))
        }
    }

    /// Lädt die Tanzil-Dateien aus dem App-Bundle.
    static func load(from bundle: Bundle = .main) throws -> QuranText {
        try QuranText(
            surahs: TanzilParser.parseMetadata(at: ResourceLocator.url(for: "quran-data.xml", in: bundle)),
            uthmani: TanzilParser.parseText(at: ResourceLocator.url(for: "quran-uthmani.xml", in: bundle)),
            simpleClean: TanzilParser.parseText(at: ResourceLocator.url(for: "quran-simple-clean.xml", in: bundle))
        )
    }

    // MARK: - Zugriff

    func contains(_ verse: VerseID) -> Bool {
        (1...Self.surahCount).contains(verse.surah) && (1...surahs[verse.surah - 1].ayahCount).contains(verse.ayah)
    }

    func surah(_ number: Int) -> SurahInfo? {
        (1...Self.surahCount).contains(number) ? surahs[number - 1] : nil
    }

    /// Text in Uthmani-Schrift für die Anzeige.
    func displayText(_ verse: VerseID) -> String? {
        contains(verse) ? uthmani[verse.surah - 1][verse.ayah - 1] : nil
    }

    /// Text in vereinfachter Schrift (Grundlage der Verssuche).
    func searchText(_ verse: VerseID) -> String? {
        contains(verse) ? simpleClean[verse.surah - 1][verse.ayah - 1] : nil
    }

    func globalIndex(of verse: VerseID) -> Int? {
        contains(verse) ? offsets[verse.surah - 1] + verse.ayah - 1 : nil
    }

    func verse(atGlobalIndex index: Int) -> VerseID? {
        guard (0..<Self.verseCount).contains(index) else { return nil }
        // letzte Sure, deren Startindex <= index ist
        var lo = 0, hi = offsets.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if offsets[mid] <= index { lo = mid } else { hi = mid - 1 }
        }
        return VerseID(surah: lo + 1, ayah: index - offsets[lo] + 1)
    }

    /// Alle Verse eines Bereichs, in Reihenfolge.
    func verses(in range: VerseRange) -> [VerseID] {
        guard let a = globalIndex(of: range.start), let b = globalIndex(of: range.end) else { return [] }
        return (a...b).compactMap(verse(atGlobalIndex:))
    }
}

/// Findet Ressourcen im Bundle – unabhängig davon, ob Xcode sie flach
/// oder in Unterordnern ablegt.
nonisolated enum ResourceLocator {
    nonisolated struct NotFound: LocalizedError {
        let name: String
        var errorDescription: String? {
            String(format: NSLocalizedString("Resource missing from the app bundle: %@ – run Tools/data/build_resources.py.", comment: ""), name)
        }
    }

    static func url(for fileName: String, in bundle: Bundle) throws -> URL {
        let name = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        if let url = bundle.url(forResource: name, withExtension: ext) {
            return url
        }
        for sub in ["Resources/Quran", "Resources/Translations", "Quran", "Translations"] {
            if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: sub) {
                return url
            }
        }
        throw NotFound(name: fileName)
    }
}
