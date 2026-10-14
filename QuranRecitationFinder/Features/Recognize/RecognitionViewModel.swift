import Combine
import Foundation

/// Steuert den Ablauf: Aufnahme → Spracherkennung → Verssuche → Ergebnis.
final class RecognitionViewModel: ObservableObject {
    enum Phase {
        case idle
        case recording
        case processing
        case finished(Recognition)
        case failed(String)
    }

    /// Warum die Aufnahme endete.
    enum StopReason: Equatable {
        case manual
        case maximum
        case silence
        case early
    }

    struct Recognition {
        let outcome: MatchOutcome
        let transcript: String
        /// Eintrag im Testprotokoll (für „Stimmt / Stimmt nicht“).
        let recordID: UUID
        /// Dauer der Spracherkennung in Sekunden (nil bei Texteingabe). Ziel Phase 3: < 3 s.
        var transcriptionSeconds: Double? = nil
        /// nil bei Texteingabe
        var stopReason: StopReason? = nil
        /// Länge der Aufnahme in Sekunden (nil bei Texteingabe)
        var recordedSeconds: Double? = nil
    }

    /// Unter dieser Länge lohnt die Erkennung nicht.
    static let minimumSeconds: TimeInterval = 2

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var level: Float = 0
    @Published private(set) var elapsed: TimeInterval = 0
    /// Rückmeldung zum aktuellen Ergebnis.
    @Published private(set) var verdict: FeedbackRecord.Verdict = .unrated

    private let capture: AudioCapturing
    private let recognizer: any RecitationRecognizer
    private let matcher: VerseMatcher
    private let history: HistoryStore
    private let settings: AppSettings
    private let feedback: FeedbackLog
    private var meterTask: Task<Void, Never>?
    private var earlyTask: Task<Void, Never>?
    private var silenceDetector = SilenceDetector()
    private var earlyPolicy = EarlyRecognitionPolicy()

    init(capture: AudioCapturing, recognizer: any RecitationRecognizer, matcher: VerseMatcher,
         history: HistoryStore, settings: AppSettings, feedback: FeedbackLog) {
        self.capture = capture
        self.recognizer = recognizer
        self.matcher = matcher
        self.history = history
        self.settings = settings
        self.feedback = feedback
    }

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    var isProcessing: Bool {
        if case .processing = phase { return true }
        return false
    }

    var isBusy: Bool {
        switch phase {
        case .recording, .processing: return true
        default: return false
        }
    }

    // MARK: - Aufnahme

    func toggleRecording() async {
        if isRecording {
            await stopAndRecognize()
        } else {
            await startRecording()
        }
    }

    func startRecording() async {
        guard !isBusy else { return }
        guard await capture.requestPermission() else {
            phase = .failed(AudioCaptureError.permissionDenied.localizedDescription)
            return
        }
        do {
            try capture.start()
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        elapsed = 0
        level = 0
        silenceDetector.reset()
        earlyPolicy.reset()
        phase = .recording
        startMeter()
    }

    func stopAndRecognize(reason: StopReason = .manual) async {
        guard isRecording else { return }
        meterTask?.cancel()
        meterTask = nil
        earlyTask?.cancel()  // ein laufender Zwischenversuch wird nicht mehr gebraucht
        earlyTask = nil
        let samples = capture.stop()
        level = 0
        let seconds = Double(samples.count) / AudioFormat.sampleRate
        guard seconds >= Self.minimumSeconds else {
            phase = .failed(RecognitionError.tooShort.localizedDescription)
            return
        }
        phase = .processing
        do {
            let started = Date()
            let text = try await recognizer.transcribe(samples: samples, sampleRate: AudioFormat.sampleRate)
            await finish(transcript: text, transcriptionSeconds: Date().timeIntervalSince(started),
                         stopReason: reason, recordedSeconds: seconds)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Aktualisiert Pegel/Zeit; stoppt bei Höchstdauer oder Stille; startet Zwischenerkennungen.
    private func startMeter() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard let self, self.isRecording else { return }
                self.level = self.capture.level
                self.elapsed = self.capture.elapsed
                // Stoppen jeweils in eigener Task: diese hier wird beim Stoppen abgebrochen,
                // die Erkennung soll aber weiterlaufen.
                if self.elapsed >= Double(self.settings.maxRecordingSeconds) {
                    Task { await self.stopAndRecognize(reason: .maximum) }
                    return
                }
                if self.settings.autoStopOnSilence,
                   self.silenceDetector.update(level: self.level, at: self.elapsed) {
                    Task { await self.stopAndRecognize(reason: .silence) }
                    return
                }
                if self.settings.earlyRecognition, self.earlyTask == nil,
                   self.earlyPolicy.shouldAttempt(elapsed: self.elapsed) {
                    self.earlyPolicy.didAttempt(at: self.elapsed)
                    self.startEarlyAttempt()
                }
            }
        }
    }

    /// Zwischenerkennung auf der bisherigen Aufnahme; bei sicherem Ergebnis vorzeitig fertig.
    private func startEarlyAttempt() {
        let samples = capture.snapshot()
        let recordedSeconds = Double(samples.count) / AudioFormat.sampleRate
        let recognizer = self.recognizer
        let matcher = self.matcher
        earlyTask = Task { [weak self] in
            let started = Date()
            let text = try? await recognizer.transcribe(samples: samples, sampleRate: AudioFormat.sampleRate)
            let seconds = Date().timeIntervalSince(started)
            var outcome: MatchOutcome?
            if let text {
                outcome = await Task.detached(priority: .userInitiated) { matcher.recognize(text) }.value
            }
            guard let self else { return }
            self.earlyTask = nil
            guard self.isRecording, !Task.isCancelled, let text, let outcome else { return }
            let words = VerseMatcher.stripOpeningFormulas(ArabicNormalizer.words(text)).words.count
            if self.earlyPolicy.evaluate(outcome, wordCount: words, acceptThreshold: matcher.configuration.acceptThreshold) {
                await self.finishEarly(transcript: text, outcome: outcome, transcriptionSeconds: seconds,
                                       recordedSeconds: recordedSeconds)
            }
        }
    }

    private func finishEarly(transcript: String, outcome: MatchOutcome, transcriptionSeconds: Double,
                             recordedSeconds: Double) async {
        guard isRecording else { return }
        meterTask?.cancel()
        meterTask = nil
        _ = capture.stop()
        level = 0
        phase = .processing
        await finish(transcript: transcript, transcriptionSeconds: transcriptionSeconds, stopReason: .early,
                     recordedSeconds: recordedSeconds, precomputed: outcome)
    }

    // MARK: - Verssuche

    /// Auch direkt nutzbar (Texteingabe zum Testen, solange Phase 3 fehlt).
    func recognize(text: String) async {
        guard !isBusy else { return }
        phase = .processing
        await finish(transcript: text)
    }

    private func finish(transcript: String, transcriptionSeconds: Double? = nil, stopReason: StopReason? = nil,
                        recordedSeconds: Double? = nil, precomputed: MatchOutcome? = nil) async {
        let matcher = self.matcher
        let outcome: MatchOutcome
        if let precomputed {
            outcome = precomputed
        } else {
            outcome = await Task.detached(priority: .userInitiated) {
                matcher.recognize(transcript)
            }.value
        }
        if case .recognized(let matches) = outcome, let best = matches.first {
            history.add(
                HistoryEntry(range: best.range, score: best.score,
                             alternatives: matches.dropFirst().map(\.range), transcript: transcript)
            )
        }
        let record = Self.makeRecord(outcome: outcome, transcript: transcript,
                                     transcriptionSeconds: transcriptionSeconds, recognizer: recognizer.displayName)
        feedback.add(record)
        verdict = .unrated
        phase = .finished(Recognition(outcome: outcome, transcript: transcript, recordID: record.id,
                                      transcriptionSeconds: transcriptionSeconds, stopReason: stopReason,
                                      recordedSeconds: recordedSeconds))
    }

    /// Rückmeldung „Stimmt / Stimmt nicht“ (optional mit richtigem Vers) ins Testprotokoll.
    func rate(_ verdict: FeedbackRecord.Verdict, correctRef: String? = nil) {
        guard case .finished(let recognition) = phase else { return }
        let ref = correctRef?.trimmingCharacters(in: .whitespaces)
        feedback.setVerdict(verdict, correctRef: (ref?.isEmpty ?? true) ? nil : ref, for: recognition.recordID)
        self.verdict = verdict
    }

    nonisolated static func makeRecord(outcome: MatchOutcome, transcript: String,
                                       transcriptionSeconds: Double?, recognizer: String) -> FeedbackRecord {
        let (kind, matches): (String, [VerseMatch]) = {
            switch outcome {
            case .recognized(let m): return ("recognized", m)
            case .uncertain(let m): return ("uncertain", m)
            case .nothing: return ("nothing", [])
            }
        }()
        return FeedbackRecord(
            id: UUID(), date: Date(), transcript: transcript, outcome: kind,
            candidates: matches.map { FeedbackRecord.Candidate(ref: $0.range.description, score: $0.score) },
            wordCount: VerseMatcher.stripOpeningFormulas(ArabicNormalizer.words(transcript)).words.count,
            transcriptionSeconds: transcriptionSeconds, recognizer: recognizer,
            verdict: .unrated, correctRef: nil
        )
    }

    func reset() {
        guard !isBusy else { return }
        phase = .idle
    }
}
