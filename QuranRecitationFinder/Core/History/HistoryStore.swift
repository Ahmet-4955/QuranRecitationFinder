import Combine
import Foundation

/// Ein gespeichertes Erkennungsergebnis.
nonisolated struct HistoryEntry: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let date: Date
    let range: VerseRange
    let score: Float
    /// Weitere gleichlautende Fundstellen.
    let alternatives: [VerseRange]
    /// Erkannter arabischer Text (zur Nachvollziehbarkeit).
    let transcript: String

    init(id: UUID = UUID(), date: Date = Date(), range: VerseRange, score: Float,
         alternatives: [VerseRange] = [], transcript: String) {
        self.id = id
        self.date = date
        self.range = range
        self.score = score
        self.alternatives = alternatives
        self.transcript = transcript
    }
}

/// Verlauf der Erkennungen, gespeichert als JSON im Application-Support-Ordner.
final class HistoryStore: ObservableObject {
    static let maxEntries = 200

    @Published private(set) var entries: [HistoryEntry] = []
    private let fileURL: URL

    init(fileURL: URL = HistoryStore.defaultURL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let stored = try? Self.decoder.decode([HistoryEntry].self, from: data) {
            entries = stored
        }
    }

    func add(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
        save()
    }

    func remove(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        save()
    }

    func removeAll() {
        entries.removeAll()
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Self.encoder.encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            print("HistoryStore: Speichern fehlgeschlagen: \(error)")
        }
    }

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("history.json")
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
