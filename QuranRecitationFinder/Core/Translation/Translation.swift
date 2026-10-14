import Foundation

/// Eintrag aus translations-index.json (welche Übersetzungen gebündelt sind).
nonisolated struct TranslationInfo: Codable, Hashable, Sendable, Identifiable {
    let key: String
    let language: String
    let title: String
    let version: String
    let direction: String
    let source: String
    let sourceURL: String
    let file: String

    var id: String { key }

    /// Quellenangabe nach QuranEnc-Bedingungen (Quelle + Version).
    var attribution: String { String(format: NSLocalizedString("%1$@ – %2$@, version %3$@", comment: ""), title, source, version) }
}

/// Eine vollständige Übersetzung (6.236 Verse), Inhalt unverändert von QuranEnc.
nonisolated struct Translation: Sendable {
    nonisolated struct Entry: Codable, Sendable {
        let sura: Int
        let aya: Int
        let text: String
        let footnotes: String?
    }

    private nonisolated struct FileFormat: Codable {
        let key: String
        let version: String
        let verses: [Entry]
    }

    nonisolated enum LoadError: LocalizedError {
        case incomplete(key: String, count: Int)
        case keyMismatch(expected: String, found: String)

        var errorDescription: String? {
            switch self {
            case .incomplete(let key, let count):
                return String(format: NSLocalizedString("Translation %1$@ incomplete: %2$@ instead of %3$@ verses", comment: ""), key, String(count), String(QuranText.verseCount))
            case .keyMismatch(let expected, let found):
                return String(format: NSLocalizedString("Translation file does not match: expected %1$@, found %2$@", comment: ""), expected, found)
            }
        }
    }

    let info: TranslationInfo
    private let entries: [VerseID: Entry]

    init(info: TranslationInfo, data: Data) throws {
        let file = try JSONDecoder().decode(FileFormat.self, from: data)
        guard file.key == info.key else {
            throw LoadError.keyMismatch(expected: info.key, found: file.key)
        }
        var map: [VerseID: Entry] = [:]
        map.reserveCapacity(file.verses.count)
        for entry in file.verses {
            map[VerseID(surah: entry.sura, ayah: entry.aya)] = entry
        }
        guard map.count == QuranText.verseCount else {
            throw LoadError.incomplete(key: info.key, count: map.count)
        }
        self.info = info
        self.entries = map
    }

    func text(for verse: VerseID) -> String? {
        entries[verse]?.text
    }

    func footnotes(for verse: VerseID) -> String? {
        guard let notes = entries[verse]?.footnotes, !notes.isEmpty else { return nil }
        return notes
    }
}

/// Kennt die gebündelten Übersetzungen und lädt sie bei Bedarf.
nonisolated final class TranslationStore: @unchecked Sendable {
    let available: [TranslationInfo]
    private let bundle: Bundle
    private let lock = NSLock()
    private var cache: [String: Translation] = [:]

    private nonisolated struct Index: Codable {
        let translations: [TranslationInfo]
    }

    init(bundle: Bundle = .main) throws {
        self.bundle = bundle
        let url = try ResourceLocator.url(for: "translations-index.json", in: bundle)
        available = try JSONDecoder().decode(Index.self, from: Data(contentsOf: url)).translations
    }

    func info(forKey key: String) -> TranslationInfo? {
        available.first { $0.key == key }
    }

    /// Erste gebündelte Übersetzung für eine Sprache (ISO-Code, z. B. "de").
    func info(forLanguage language: String) -> TranslationInfo? {
        available.first { $0.language == language }
    }

    func translation(forKey key: String) throws -> Translation {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        guard let info = info(forKey: key) else {
            throw ResourceLocator.NotFound(name: String(format: NSLocalizedString("Translation %@", comment: ""), key))
        }
        let url = try ResourceLocator.url(for: info.file, in: bundle)
        let translation = try Translation(info: info, data: Data(contentsOf: url))
        cache[key] = translation
        return translation
    }
}
