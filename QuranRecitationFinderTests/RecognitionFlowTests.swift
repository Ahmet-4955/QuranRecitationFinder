import Foundation
import Testing
@testable import QuranRecitationFinder

/// Abnahmetests Phase 4: Ablauf Aufnahme → Erkennung → Verssuche → Verlauf
/// mit simuliertem Mikrofon und simulierter Spracherkennung.

@MainActor
final class MockCapture: AudioCapturing {
    var permission = true
    /// Länge der Aufnahme. Ohne `step` sofort erreicht.
    var seconds: TimeInterval = 4
    /// Simulierte Zeit: jede Abfrage von `elapsed` rückt um `step` Sekunden vor – unabhängig
    /// von der echten Uhr, damit Zeit-Tests auch unter Last reproduzierbar sind.
    var step: TimeInterval?
    /// Pegelverlauf über die Aufnahmezeit
    var levelAt: (TimeInterval) -> Float = { _ in 0.5 }
    private(set) var started = false
    private(set) var stoppedAt: TimeInterval?
    private var position: TimeInterval = 0

    /// aktuelle Aufnahmeposition, ohne vorzurücken
    private var current: TimeInterval { step == nil ? seconds : position }

    var elapsed: TimeInterval {
        guard started else { return stoppedAt ?? 0 }
        if let step { position = min(position + step, seconds) }
        return current
    }

    var level: Float { started ? levelAt(current) : 0 }

    func requestPermission() async -> Bool { permission }

    func start() throws {
        started = true
        stoppedAt = nil
        position = 0
    }

    func snapshot() -> [Float] {
        [Float](repeating: 0, count: Int(current * AudioFormat.sampleRate))
    }

    func stop() -> [Float] {
        let samples = snapshot()
        stoppedAt = current
        started = false
        return samples
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

    private func makeFeedback() -> FeedbackLog {
        FeedbackLog(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("feedback-\(UUID().uuidString).json"))
    }

    private func makeModel(capture: MockCapture, recognizer: any RecitationRecognizer,
                           history: HistoryStore, feedback: FeedbackLog? = nil) throws -> RecognitionViewModel {
        RecognitionViewModel(capture: capture, recognizer: recognizer, matcher: try SharedMatcher.get(),
                             history: history, settings: makeSettings(), feedback: feedback ?? makeFeedback())
    }

    private func waitUntilDone(_ model: RecognitionViewModel) async throws {
        for _ in 0..<800 where model.isBusy {  // max. 20 s Echtzeit
            try await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    @Test func silenceEndsRecordingAutomatically() async throws {
        let capture = MockCapture()
        capture.seconds = 60
        capture.step = 0.1
        capture.levelAt = { $0 < 4 ? 0.7 : 0.1 }  // 4 s Rezitation, dann Ruhe
        let settings = makeSettings()
        settings.earlyRecognition = false  // nur die Stille prüfen
        let model = RecognitionViewModel(capture: capture, recognizer: MockRecognizer(text: "قل هو الله احد الله الصمد"),
                                         matcher: try SharedMatcher.get(), history: makeHistory(),
                                         settings: settings, feedback: makeFeedback())
        await model.startRecording()
        try await waitUntilDone(model)
        guard case .finished(let recognition) = model.phase else {
            Issue.record("erwartet: Ergebnis, ist: \(model.phase)")
            return
        }
        #expect(recognition.stopReason == .silence)
        let stoppedAt = try #require(capture.stoppedAt)
        #expect(stoppedAt > 6.3 && stoppedAt < 6.8, "gestoppt nach \(stoppedAt) s (erwartet: 4 s + 2,5 s Ruhe)")
    }

    @Test func confidentResultEndsRecordingEarly() async throws {
        let capture = MockCapture()
        capture.seconds = 60
        capture.step = 0.1
        capture.levelAt = { _ in 0.7 }  // durchgehend Rezitation, keine Stille
        let text = "يس والقران الحكيم انك لمن المرسلين علي صراط مستقيم"
        let settings = makeSettings()
        settings.maxRecordingSeconds = 30  // Spielraum: Zwischenerkennungen brauchen echte Rechenzeit
        let model = RecognitionViewModel(capture: capture, recognizer: MockRecognizer(text: text),
                                         matcher: try SharedMatcher.get(), history: makeHistory(),
                                         settings: settings, feedback: makeFeedback())
        await model.startRecording()
        try await waitUntilDone(model)
        guard case .finished(let recognition) = model.phase, case .recognized(let matches) = recognition.outcome else {
            Issue.record("erwartet: erkannt, ist: \(model.phase)")
            return
        }
        #expect(recognition.stopReason == .early)
        #expect(matches.first?.range.start == VerseID(surah: 36, ayah: 1))
        let stoppedAt = try #require(capture.stoppedAt)
        #expect(stoppedAt >= 8 && stoppedAt < 30, "Früherkennung frühestens beim 2. Versuch (8 s), war \(stoppedAt) s")
    }

    @Test func automaticsCanBeSwitchedOff() async throws {
        let capture = MockCapture()
        capture.seconds = 60
        capture.step = 0.5
        capture.levelAt = { $0 < 4 ? 0.7 : 0.1 }
        let settings = makeSettings()
        settings.autoStopOnSilence = false
        settings.earlyRecognition = false
        let model = RecognitionViewModel(capture: capture, recognizer: MockRecognizer(text: "يس والقران الحكيم انك لمن المرسلين"),
                                         matcher: try SharedMatcher.get(), history: makeHistory(),
                                         settings: settings, feedback: makeFeedback())
        await model.startRecording()
        try await waitUntilDone(model)
        guard case .finished(let recognition) = model.phase else {
            Issue.record("erwartet: Ergebnis")
            return
        }
        #expect(recognition.stopReason == .maximum)
    }

    @Test func ratingIsWrittenToFeedbackLog() async throws {
        let feedback = makeFeedback()
        let model = try makeModel(capture: MockCapture(), recognizer: MockRecognizer(text: "قل هو الله احد الله الصمد"),
                                  history: makeHistory(), feedback: feedback)
        await model.startRecording()
        await model.stopAndRecognize()
        #expect(feedback.records.count == 1)
        #expect(feedback.records.first?.outcome == "recognized")
        #expect(feedback.records.first?.transcriptionSeconds != nil)
        model.rate(.wrong, correctRef: " 2:255 ")
        #expect(model.verdict == .wrong)
        #expect(feedback.records.first?.verdict == .wrong)
        #expect(feedback.records.first?.correctRef == "2:255")
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
        #expect(message == RecognitionError.notAvailable(UnavailableRecognizer().reason).localizedDescription)
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

    @Test func removingSelectedEntries() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString).json")
        let store = HistoryStore(fileURL: url)
        for ayah in 1...4 {
            store.add(HistoryEntry(range: VerseRange(VerseID(surah: 1, ayah: ayah)), score: 1, transcript: ""))
        }
        store.remove(at: IndexSet([0, 2]))  // neuestes zuerst: entfernt 1:4 und 1:2
        #expect(store.entries.map(\.range.start.ayah) == [3, 1])
        #expect(HistoryStore(fileURL: url).entries.count == 2)
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
