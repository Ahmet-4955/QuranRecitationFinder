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

    struct Recognition {
        let outcome: MatchOutcome
        let transcript: String
        /// Dauer der Spracherkennung in Sekunden (nil bei Texteingabe). Ziel Phase 3: < 3 s.
        var transcriptionSeconds: Double? = nil
    }

    /// Unter dieser Länge lohnt die Erkennung nicht.
    static let minimumSeconds: TimeInterval = 2

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var level: Float = 0
    @Published private(set) var elapsed: TimeInterval = 0

    private let capture: AudioCapturing
    private let recognizer: any RecitationRecognizer
    private let matcher: VerseMatcher
    private let history: HistoryStore
    private let settings: AppSettings
    private var meterTask: Task<Void, Never>?

    init(capture: AudioCapturing, recognizer: any RecitationRecognizer, matcher: VerseMatcher,
         history: HistoryStore, settings: AppSettings) {
        self.capture = capture
        self.recognizer = recognizer
        self.matcher = matcher
        self.history = history
        self.settings = settings
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
        phase = .recording
        startMeter()
    }

    func stopAndRecognize() async {
        guard isRecording else { return }
        meterTask?.cancel()
        meterTask = nil
        let samples = capture.stop()
        level = 0
        let seconds = Double(samples.count) / AudioCaptureService.sampleRate
        guard seconds >= Self.minimumSeconds else {
            phase = .failed(RecognitionError.tooShort.localizedDescription)
            return
        }
        phase = .processing
        do {
            let started = Date()
            let text = try await recognizer.transcribe(samples: samples, sampleRate: AudioCaptureService.sampleRate)
            await finish(transcript: text, transcriptionSeconds: Date().timeIntervalSince(started))
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Aktualisiert Pegel/Zeit und stoppt automatisch bei der eingestellten Höchstdauer.
    private func startMeter() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard let self, self.isRecording else { return }
                self.level = self.capture.level
                self.elapsed = self.capture.elapsed
                if self.elapsed >= Double(self.settings.maxRecordingSeconds) {
                    // eigene Task: diese hier wird beim Stoppen abgebrochen, die Erkennung soll weiterlaufen
                    Task { await self.stopAndRecognize() }
                    return
                }
            }
        }
    }

    // MARK: - Verssuche

    /// Auch direkt nutzbar (Texteingabe zum Testen, solange Phase 3 fehlt).
    func recognize(text: String) async {
        guard !isBusy else { return }
        phase = .processing
        await finish(transcript: text)
    }

    private func finish(transcript: String, transcriptionSeconds: Double? = nil) async {
        let matcher = self.matcher
        let outcome = await Task.detached(priority: .userInitiated) {
            matcher.recognize(transcript)
        }.value
        if case .recognized(let matches) = outcome, let best = matches.first {
            history.add(
                HistoryEntry(range: best.range, score: best.score,
                             alternatives: matches.dropFirst().map(\.range), transcript: transcript)
            )
        }
        phase = .finished(Recognition(outcome: outcome, transcript: transcript, transcriptionSeconds: transcriptionSeconds))
    }

    func reset() {
        guard !isBusy else { return }
        phase = .idle
    }
}
