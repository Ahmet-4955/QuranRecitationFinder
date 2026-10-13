import Foundation
import Testing
@testable import QuranRecitationFinder

/// Abnahmetests Phase 4: Ablauf Aufnahme → Erkennung → Verssuche → Verlauf
/// mit simuliertem Mikrofon und simulierter Spracherkennung.

@MainActor
final class MockCapture: AudioCapturing {
    var permission = true
    var seconds: TimeInterval = 4
    private(set) var started = false

    var level: Float { started ? 0.5 : 0 }
    var elapsed: TimeInterval { started ? seconds : 0 }

    func requestPermission() async -> Bool { permission }

    func start() throws { started = true }

    func stop() -> [Float] {
        started = false
        return [Float](repeating: 0, count: Int(seconds * AudioCaptureService.sampleRate))
    }
}

struct MockRecognizer: RecitationRecognizer {
    let displayName = "Test"
    let text: String

    func transcribe(samples: [Float], sampleRate: Double) async throws -> String { text }
}

@MainActor
struct RecognitionFlowTests {
    private func makeHistory() -> HistoryStore {
        HistoryStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString).json"))
    }

    private func makeSettings() -> AppSettings {
        let name = "test.\(UUID().uuidString)"
        return AppSettings(defaults: UserDefaults(suiteName: name)!, locale: Locale(identifier: "de_DE"))
    }

    private func makeModel(capture: MockCapture, recognizer: any RecitationRecognizer,
                           history: HistoryStore) throws -> RecognitionViewModel {
        RecognitionViewModel(capture: capture, recognizer: recognizer, matcher: try SharedMatcher.get(),
                             history: history, settings: makeSettings())
    }

    @Test func recordingIsRecognizedAndSaved() async throws {
        let capture = MockCapture()
        let history = makeHistory()
        let model = try makeModel(capture: capture, recognizer: MockRecognizer(text: "قل هو الله احد الله الصمد"),
                                  history: history)
        await model.startRecording()
        #expect(model.isRecording)
        await model.stopAndRecognize()

        guard case .finished(let recognition) = model.phase,
              case .recognized(let matches) = recognition.outcome else {
            Issue.record("erwartet: erkannt, ist: \(model.phase)")
            return
        }
        #expect(matches.first?.range.start == VerseID(surah: 112, ayah: 1))
        #expect(history.entries.count == 1)
        #expect(history.entries.first?.range.start == VerseID(surah: 112, ayah: 1))
    }

    @Test func tooShortRecordingIsRejected() async throws {
        let capture = MockCapture()
        capture.seconds = 1
        let model = try makeModel(capture: capture, recognizer: MockRecognizer(text: "x"), history: makeHistory())
        await model.startRecording()
        await model.stopAndRecognize()
        guard case .failed(let message) = model.phase else {
            Issue.record("erwartet: Fehler")
            return
        }
        #expect(message == RecognitionError.tooShort.localizedDescription)
    }

    @Test func missingPermissionIsReported() async throws {
        let capture = MockCapture()
        capture.permission = false
        let model = try makeModel(capture: capture, recognizer: MockRecognizer(text: "x"), history: makeHistory())
        await model.startRecording()
        #expect(!capture.started)
        if case .failed = model.phase {} else { Issue.record("erwartet: Fehler") }
    }

    @Test func placeholderRecognizerExplainsPhase3() async throws {
        let model = try makeModel(capture: MockCapture(), recognizer: UnavailableRecognizer(), history: makeHistory())
        await model.startRecording()
        await model.stopAndRecognize()
        guard case .failed(let message) = model.phase else {
            Issue.record("erwartet: Fehler")
            return
        }
        #expect(message.contains("Phase 3"))
    }

    @Test func recordingStopsAutomaticallyAtMaximum() async throws {
        let capture = MockCapture()
        capture.seconds = 60  // über der Höchstdauer (Standard 12 s)
        let model = try makeModel(capture: capture, recognizer: MockRecognizer(text: "قل اعوذ برب الناس"),
                                  history: makeHistory())
        await model.startRecording()
        for _ in 0..<100 where model.isBusy {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(!capture.started)
        guard case .finished(let recognition) = model.phase, case .recognized = recognition.outcome else {
            Issue.record("erwartet: automatisch gestoppt und erkannt, ist: \(model.phase)")
            return
        }
    }

    @Test func manualTextInputUsesSameSearch() async throws {
        let history = makeHistory()
        let model = try makeModel(capture: MockCapture(), recognizer: UnavailableRecognizer(), history: history)
        await model.recognize(text: "هذا نص عربي حديث عن الهاتف والسيارة والحاسوب")
        guard case .finished(let recognition) = model.phase else {
            Issue.record("erwartet: Ergebnis")
            return
        }
        if case .recognized = recognition.outcome { Issue.record("fremder Text darf nicht erkannt werden") }
        #expect(history.entries.isEmpty, "Unsichere Ergebnisse nicht im Verlauf speichern")
    }
}

@MainActor
struct HistoryStoreTests {
    @Test func entriesArePersisted() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString).json")
        let store = HistoryStore(fileURL: url)
        store.add(HistoryEntry(range: VerseRange(VerseID(surah: 2, ayah: 255)), score: 0.95, transcript: "…"))
        store.add(HistoryEntry(range: VerseRange(VerseID(surah: 1, ayah: 1)), score: 0.9,
                               alternatives: [VerseRange(VerseID(surah: 27, ayah: 30))], transcript: "…"))

        let reloaded = HistoryStore(fileURL: url)
        #expect(reloaded.entries.count == 2)
        #expect(reloaded.entries.first?.range.start == VerseID(surah: 1, ayah: 1))  // neuestes zuerst
        #expect(reloaded.entries.first?.alternatives.first?.start == VerseID(surah: 27, ayah: 30))

        reloaded.removeAll()
        #expect(HistoryStore(fileURL: url).entries.isEmpty)
    }

    @Test func historyIsCapped() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString).json")
        let store = HistoryStore(fileURL: url)
        for _ in 0..<(HistoryStore.maxEntries + 5) {
            store.add(HistoryEntry(range: VerseRange(VerseID(surah: 1, ayah: 1)), score: 1, transcript: ""))
        }
        #expect(store.entries.count == HistoryStore.maxEntries)
    }
}

@MainActor
struct RecordingSettingsTests {
    @Test func maxRecordingIsClampedAndPersisted() {
        let name = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let settings = AppSettings(defaults: defaults)
        #expect(settings.maxRecordingSeconds == AppSettings.defaultMaxRecordingSeconds)
        settings.maxRecordingSeconds = 99
        #expect(settings.maxRecordingSeconds == AppSettings.recordingRange.upperBound)
        #expect(AppSettings(defaults: defaults).maxRecordingSeconds == AppSettings.recordingRange.upperBound)
    }
}
