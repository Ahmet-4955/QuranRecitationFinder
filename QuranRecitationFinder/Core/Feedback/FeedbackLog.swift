import Foundation

/// Ein Eintrag im Testprotokoll: was erkannt wurde und ob es stimmte.
/// Dient der Kalibrierung (Tools/phase5/calibrate.py), nicht der Erkennung selbst.
nonisolated struct FeedbackRecord: Codable, Identifiable, Hashable, Sendable {
    nonisolated enum Verdict: String, Codable, Sendable {
        case unrated
        case correct
        case wrong
    }

    nonisolated struct Candidate: Codable, Hashable, Sendable {
        let ref: String
        let score: Float
    }

    let id: UUID
    let date: Date
    let transcript: String
    /// "recognized", "uncertain" oder "nothing"
    let outcome: String
    let candidates: [Candidate]
    let wordCount: Int
    let transcriptionSeconds: Double?
    let recognizer: String
    var verdict: Verdict
    /// Vom Nutzer angegebener richtiger Vers, z. B. "2:255"
    var correctRef: String?

    var bestScore: Float { candidates.first?.score ?? 0 }
}

/// Speichert das Testprotokoll als JSON-Datei und erzeugt die Export-Datei.
nonisolated final class FeedbackLog: @unchecked Sendable {
    static let maxRecords = 1000

    private let fileURL: URL
    private let lock = NSLock()
    private var storage: [FeedbackRecord] = []

    init(fileURL: URL = FeedbackLog.defaultURL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let stored = try? Self.decoder.decode([FeedbackRecord].self, from: data) {
            storage = stored
        }
    }

    var records: [FeedbackRecord] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func add(_ record: FeedbackRecord) {
        lock.lock()
        storage.insert(record, at: 0)
        if storage.count > Self.maxRecords { storage.removeLast(storage.count - Self.maxRecords) }
        lock.unlock()
        save()
    }

    func setVerdict(_ verdict: FeedbackRecord.Verdict, correctRef: String? = nil, for id: UUID) {
        lock.lock()
        if let index = storage.firstIndex(where: { $0.id == id }) {
            storage[index].verdict = verdict
            storage[index].correctRef = correctRef
        }
        lock.unlock()
        save()
    }

    func removeAll() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
        save()
    }

    /// Schreibt das Protokoll in eine Datei zum Teilen (AirDrop/Dateien).
    func exportFile() throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("testprotokoll-\(stamp).json")
        try Self.encoder.encode(records).write(to: url, options: .atomic)
        return url
    }

    private func save() {
        let snapshot = records
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Self.encoder.encode(snapshot).write(to: fileURL, options: .atomic)
        } catch {
            print("FeedbackLog: Speichern fehlgeschlagen: \(error)")
        }
    }

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("feedback-log.json")
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
