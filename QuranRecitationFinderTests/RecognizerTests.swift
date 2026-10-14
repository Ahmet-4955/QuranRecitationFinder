import Foundation
import Testing
@testable import QuranRecitationFinder

/// Tests Phase 3: Modellordner, Auswahl der Spracherkennung, Rauchtest mit echtem Modell.
struct WhisperModelLocatorTests {
    private func makeFolder(files: [String], info: String?) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in files {
            let url = folder.appendingPathComponent(name)
            if name.hasSuffix(".mlmodelc") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try Data("{}".utf8).write(to: url)
            }
        }
        if let info {
            try Data(info.utf8).write(to: folder.appendingPathComponent("model-info.json"))
        }
        return folder
    }

    private let validInfo = """
    {"displayName":"Tarteel Whisper base","model":"tarteel-ai/whisper-base-ar-quran","size":"base",
     "license":"Apache-2.0","sourceURL":"https://huggingface.co/tarteel-ai/whisper-base-ar-quran"}
    """

    @Test func acceptsCompleteFolder() throws {
        let folder = try makeFolder(files: ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc",
                                            "MelSpectrogram.mlmodelc", "tokenizer.json"], info: validInfo)
        let result = try WhisperModelLocator.inspect(folder: folder)
        #expect(result.info.displayName == "Tarteel Whisper base")
        #expect(result.info.license == "Apache-2.0")
    }

    @Test func reportsMissingFiles() throws {
        let folder = try makeFolder(files: ["AudioEncoder.mlmodelc"], info: validInfo)
        #expect(throws: WhisperModelLocator.LookupError.incomplete(["TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc", "tokenizer.json"])) {
            try WhisperModelLocator.inspect(folder: folder)
        }
    }

    @Test func rejectsBrokenInfo() throws {
        let folder = try makeFolder(files: ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc",
                                            "MelSpectrogram.mlmodelc", "tokenizer.json"], info: "kein json")
        #expect(throws: WhisperModelLocator.LookupError.invalidInfo) {
            try WhisperModelLocator.inspect(folder: folder)
        }
    }
}

struct RecognizerFactoryTests {
    @Test func fallsBackToPlaceholderWithReason() async throws {
        let recognizer = RecognizerFactory.make(bundle: Bundle(for: BundleToken.self))
        // Test-Bundle enthält nie ein Modell → immer Platzhalter mit Begründung
        let placeholder = try #require(recognizer as? UnavailableRecognizer)
        // Vergleich mit dem Fehlertext selbst – unabhängig von der Gerätesprache
        let expected = RecognizerFactory.isWhisperKitLinked
            ? WhisperModelLocator.LookupError.folderMissing.localizedDescription
            : NSLocalizedString("The Swift package WhisperKit is not linked yet (Tools/model/README.md, step 4).", comment: "")
        #expect(placeholder.reason == expected)
        await #expect(throws: RecognitionError.self) {
            _ = try await recognizer.transcribe(samples: [], sampleRate: 16_000)
        }
    }
}

private final class BundleToken {}

#if canImport(WhisperKit)
/// Rauchtest mit dem eingebauten Modell: lädt es, misst die Zeit, transkribiert Stille.
/// Läuft nur, wenn Tools/model/README.md Schritt 3–4 erledigt sind.
struct WhisperKitSmokeTests {
    static let model = try? WhisperModelLocator.locate(in: .main)

    @Test(.enabled(if: model != nil, "kein Modell im App-Bundle"), .timeLimit(.minutes(5)))
    func loadsModelAndHandlesSilence() async throws {
        let model = try #require(Self.model)
        let recognizer = WhisperKitRecognizer(modelFolder: model.folder, info: model.info)
        let started = Date()
        try await recognizer.prepare()
        print("Modell geladen in \(String(format: "%.1f", Date().timeIntervalSince(started))) s")

        let silence = [Float](repeating: 0, count: 16_000 * 3)
        do {
            let text = try await recognizer.transcribe(samples: silence, sampleRate: 16_000)
            print("Stille ergab: \(text)")  // Whisper „halluziniert“ bei Stille manchmal – kein Fehler
        } catch let error as RecognitionError {
            #expect(error == .noSpeech)
        }
    }
}
#endif
