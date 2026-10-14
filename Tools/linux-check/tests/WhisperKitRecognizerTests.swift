import Foundation
import Testing
import WhisperKit
@testable import QuranRecitationFinder

/// Nur unter Linux mit dem Ersatz-Modul WhisperKit (Tools/linux-check/stubs):
/// prüft WhisperKitRecognizer gegen die Schnittstelle von argmax-oss-swift v1.1.1.
@Suite(.serialized)
struct WhisperKitRecognizerTests {
    private func makeRecognizer() -> WhisperKitRecognizer {
        let info = WhisperModelInfo(displayName: "Tarteel Whisper base", model: "tarteel-ai/whisper-base-ar-quran",
                                    size: "base", license: "Apache-2.0",
                                    sourceURL: "https://huggingface.co/tarteel-ai/whisper-base-ar-quran",
                                    convertedWith: nil, convertedAt: nil)
        return WhisperKitRecognizer(modelFolder: URL(fileURLWithPath: "/tmp/WhisperModel"), info: info)
    }

    @Test func transcribesAndReportsCredits() async throws {
        WhisperKit.Simulation.shared.reset()
        let recognizer = makeRecognizer()
        let text = try await recognizer.transcribe(samples: [Float](repeating: 0, count: 16_000), sampleRate: 16_000)
        #expect(text == "قل هو الله احد")
        #expect(recognizer.displayName == "Tarteel Whisper base")
        #expect(recognizer.credits.contains { $0.contains("Apache-2.0") })
    }

    @Test func rejectsWrongSampleRate() async {
        await #expect(throws: RecognitionError.unsupportedSampleRate) {
            _ = try await makeRecognizer().transcribe(samples: [0], sampleRate: 44_100)
        }
    }

    /// Früherkennung + endgültige Erkennung dürfen WhisperKit nie gleichzeitig nutzen.
    @Test func concurrentCallsRunOneAfterAnother() async throws {
        let sim = WhisperKit.Simulation.shared
        sim.reset()
        let recognizer = makeRecognizer()
        try await recognizer.prepare()
        let samples = [Float](repeating: 0, count: 16_000)
        async let a = recognizer.transcribe(samples: samples, sampleRate: 16_000)
        async let b = recognizer.transcribe(samples: samples, sampleRate: 16_000)
        async let c = recognizer.transcribe(samples: samples, sampleRate: 16_000)
        _ = try await (a, b, c)
        #expect(sim.calls == 3)
        #expect(sim.maxConcurrent == 1, "gleichzeitige WhisperKit-Aufrufe: \(sim.maxConcurrent)")
    }
}
