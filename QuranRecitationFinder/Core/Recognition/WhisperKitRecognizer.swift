import Foundation

#if canImport(WhisperKit)
import WhisperKit

/// Spracherkennung mit WhisperKit und dem eingebauten Tarteel-Whisper-Modell (offline).
///
/// Wird nur kompiliert, wenn das Swift-Paket „WhisperKit“ eingebunden ist
/// (Tools/model/README.md, Schritt 4). Sonst nutzt die App den Platzhalter.
actor WhisperKitRecognizer: RecitationRecognizer {
    nonisolated let displayName: String
    nonisolated let credits: [String]
    private let modelFolder: URL

    /// WhisperKit ist nicht Sendable – Zugriff nur über diesen Actor.
    nonisolated private final class Box: @unchecked Sendable {
        let kit: WhisperKit
        init(_ kit: WhisperKit) { self.kit = kit }
    }

    private var box: Box?
    private var loading: Task<Box, Error>?
    /// Letzte angestoßene Erkennung – neue Aufrufe warten darauf (siehe `transcribe`).
    private var queueTail: Task<Void, Never>?

    init(modelFolder: URL, info: WhisperModelInfo) {
        self.modelFolder = modelFolder
        self.displayName = info.displayName
        self.credits = [
            String(format: NSLocalizedString("Model: %1$@ – license %2$@ (%3$@)", comment: ""), info.model, info.license, info.sourceURL),
            NSLocalizedString("WhisperKit (argmax-oss-swift) – MIT license, https://github.com/argmaxinc/argmax-oss-swift", comment: ""),
        ]
    }

    func prepare() async throws {
        _ = try await loadedBox()
    }

    /// Aufrufe laufen strikt nacheinander: Actors erlauben Wiedereintritt bei `await`, und
    /// Zwischenerkennung (Früherkennung) und endgültige Erkennung dürfen nicht gleichzeitig
    /// auf dieselbe WhisperKit-Instanz zugreifen.
    func transcribe(samples: [Float], sampleRate: Double) async throws -> String {
        guard sampleRate == 16_000 else { throw RecognitionError.unsupportedSampleRate }
        let previous = queueTail
        let job = Task<String, Error> {
            await previous?.value
            return try await self.performTranscription(samples: samples)
        }
        queueTail = Task { _ = try? await job.value }
        return try await job.value
    }

    private func performTranscription(samples: [Float]) async throws -> String {
        let kit = try await loadedBox().kit
        let options = DecodingOptions(
            task: .transcribe,
            language: "ar",
            temperature: 0,
            usePrefillPrompt: true,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw RecognitionError.noSpeech }
        return text
    }

    /// Lädt das Modell genau einmal, auch wenn mehrere Aufrufe gleichzeitig kommen.
    private func loadedBox() async throws -> Box {
        if let box { return box }
        if let loading { return try await loading.value }
        let folder = modelFolder.path
        let task = Task<Box, Error> {
            let config = WhisperKitConfig(
                modelFolder: folder,
                tokenizerFolder: URL(fileURLWithPath: folder),
                verbose: false,
                prewarm: true,
                load: true,
                download: false
            )
            return Box(try await WhisperKit(config))
        }
        loading = task
        do {
            let loaded = try await task.value
            box = loaded
            loading = nil
            return loaded
        } catch {
            loading = nil
            throw error
        }
    }
}
#endif

/// Wählt die passende Spracherkennung: WhisperKit, wenn Paket und Modell vorhanden sind.
nonisolated enum RecognizerFactory {
    static var isWhisperKitLinked: Bool {
        #if canImport(WhisperKit)
        return true
        #else
        return false
        #endif
    }

    static func make(bundle: Bundle = .main) -> any RecitationRecognizer {
        #if canImport(WhisperKit)
        do {
            let model = try WhisperModelLocator.locate(in: bundle)
            return WhisperKitRecognizer(modelFolder: model.folder, info: model.info)
        } catch {
            return UnavailableRecognizer(reason: error.localizedDescription)
        }
        #else
        return UnavailableRecognizer(reason: NSLocalizedString("The Swift package WhisperKit is not linked yet (Tools/model/README.md, step 4).", comment: ""))
        #endif
    }
}
