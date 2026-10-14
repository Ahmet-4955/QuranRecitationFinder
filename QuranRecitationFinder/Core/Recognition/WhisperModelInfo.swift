import Foundation

/// Inhalt von Models/WhisperModel/model-info.json (erzeugt von Tools/model/convert_model.py).
nonisolated struct WhisperModelInfo: Codable, Sendable, Equatable {
    let displayName: String
    let model: String
    let size: String
    let license: String
    let sourceURL: String
    let convertedWith: String?
    let convertedAt: String?
}

/// Findet das in die App eingebaute Whisper-Modell.
nonisolated enum WhisperModelLocator {
    /// Name des Ordners (in Xcode als Ordner-Referenz eingebunden).
    static let folderName = "WhisperModel"
    static let requiredFiles = ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc",
                                "tokenizer.json", "model-info.json"]

    nonisolated enum LookupError: LocalizedError, Equatable {
        case folderMissing
        case incomplete([String])
        case invalidInfo

        var errorDescription: String? {
            switch self {
            case .folderMissing:
                return "Modellordner „\(WhisperModelLocator.folderName)“ ist nicht in der App (Tools/model/README.md, Schritt 3)."
            case .incomplete(let missing):
                return "Modellordner unvollständig, es fehlt: \(missing.joined(separator: ", "))."
            case .invalidInfo:
                return "model-info.json ist nicht lesbar."
            }
        }
    }

    static func locate(in bundle: Bundle = .main) throws -> (folder: URL, info: WhisperModelInfo) {
        guard let folder = bundle.url(forResource: folderName, withExtension: nil) else {
            throw LookupError.folderMissing
        }
        return try inspect(folder: folder)
    }

    /// Prüft einen Modellordner (auch für Tests mit eigenem Ordner).
    static func inspect(folder: URL) throws -> (folder: URL, info: WhisperModelInfo) {
        let fm = FileManager.default
        let missing = requiredFiles.filter { !fm.fileExists(atPath: folder.appendingPathComponent($0).path) }
        guard missing.isEmpty else { throw LookupError.incomplete(missing) }
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("model-info.json")),
              let info = try? JSONDecoder().decode(WhisperModelInfo.self, from: data) else {
            throw LookupError.invalidInfo
        }
        return (folder, info)
    }
}
