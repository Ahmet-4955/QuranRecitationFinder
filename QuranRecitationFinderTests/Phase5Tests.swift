import Foundation
import Testing
@testable import QuranRecitationFinder

/// Tests Phase 5: Konfigurationsdatei und Testprotokoll (laufen auch unter Linux).
struct RecognitionConfigTests {
    @Test func missingFieldsFallBackToDefaults() throws {
        let config = try JSONDecoder().decode(RecognitionConfig.self, from: Data(#"{"acceptThreshold": 0.72}"#.utf8))
        #expect(config.acceptThreshold == 0.72)
        #expect(config.tieMargin == RecognitionConfig().tieMargin)
        #expect(config.matcherEdition == .simpleClean)
        #expect(config.matcherConfiguration.acceptThreshold == 0.72)
    }

    @Test func uthmaniEditionIsRecognized() throws {
        let config = try JSONDecoder().decode(RecognitionConfig.self, from: Data(#"{"edition": "uthmani"}"#.utf8))
        #expect(config.matcherEdition == .uthmani)
    }

    @Test func missingFileGivesDefaults() {
        let config = RecognitionConfig.load(from: Bundle(for: ConfigBundleToken.self))
        #expect(config == RecognitionConfig())
    }

    @Test func thresholdFromConfigIsApplied() throws {
        var strict = RecognitionConfig()
        strict.acceptThreshold = 1.01  // unerreichbar → nie „erkannt“
        let matcher = VerseMatcher(quran: try QuranText.load(from: .main), configuration: strict.matcherConfiguration)
        if case .recognized = matcher.recognize("قل هو الله احد الله الصمد") {
            Issue.record("Schwelle aus der Konfiguration wird nicht beachtet")
        }
    }
}

private final class ConfigBundleToken {}

struct FeedbackLogTests {
    private func makeRecord(score: Float) -> FeedbackRecord {
        FeedbackRecord(id: UUID(), date: Date(), transcript: "قل هو الله احد", outcome: "recognized",
                       candidates: [.init(ref: "112:1", score: score)], wordCount: 4,
                       transcriptionSeconds: 1.2, recognizer: "Test", verdict: .unrated, correctRef: nil)
    }

    @Test func recordsArePersistedAndRated() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fb-\(UUID().uuidString).json")
        let log = FeedbackLog(fileURL: url)
        let record = makeRecord(score: 0.93)
        log.add(record)
        log.setVerdict(.correct, for: record.id)

        let reloaded = FeedbackLog(fileURL: url)
        #expect(reloaded.records.count == 1)
        #expect(reloaded.records.first?.verdict == .correct)
        #expect(reloaded.records.first?.bestScore == 0.93)
    }

    @Test func exportProducesReadableJSON() throws {
        let log = FeedbackLog(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("fb-\(UUID().uuidString).json"))
        log.add(makeRecord(score: 0.5))
        let exported = try log.exportFile()
        let data = try Data(contentsOf: exported)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode([FeedbackRecord].self, from: data).count == 1)
        #expect(String(decoding: data, as: UTF8.self).contains("\"candidates\""))
    }
}
