import Foundation
import AVFoundation
import Combine

@MainActor
class AudioRecorder: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case recording
        case processing
        case completed(QuranVerse?)
        case permissionDenied
    }

    @Published private(set) var recordingState: State = .idle
    @Published var showPermissionAlert = false
    @Published var remainingSeconds = 0
    @Published var audioLevel: Float = 0.0
    @Published var lastRecordingURL: URL?

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var meterTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var recordingDuration = 5
    private let matcher = AudioMatchManager()

    var isRecording: Bool {
        recordingState == .recording
    }

    func startRecording(duration: Int) {
        recordingDuration = max(duration, 1)
        Task { await requestPermissionAndRecord() }
    }

    func stopRecording() {
        stopTask?.cancel()
        meterTask?.cancel()
        audioRecorder?.stop()
        updateAudioLevel()
        let wasRecording = recordingState == .recording
        recordingState = .processing
        remainingSeconds = 0
        guard wasRecording, let url = audioRecorder?.url else {
            recordingState = .completed(nil)
            return
        }

        lastRecordingURL = url
        matcher.matchAudioFile(url: url) { [weak self] result in
            DispatchQueue.main.async {
                self?.recordingState = .completed(result)
            }
        }
    }

    private func requestPermissionAndRecord() async {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                await startSession()
            case .denied:
                recordingState = .permissionDenied
                showPermissionAlert = true
            case .undetermined:
                let status = await withCheckedContinuation { continuation in
                    AVAudioApplication.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }

                if status {
                    await startSession()
                } else {
                    recordingState = .permissionDenied
                    showPermissionAlert = true
                }
            @unknown default:
                recordingState = .permissionDenied
                showPermissionAlert = true
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted:
                await startSession()
            case .denied:
                recordingState = .permissionDenied
                showPermissionAlert = true
            case .undetermined:
                let status = await withCheckedContinuation { continuation in
                    AVAudioSession.sharedInstance().requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }

                if status {
                    await startSession()
                } else {
                    recordingState = .permissionDenied
                    showPermissionAlert = true
                }
            @unknown default:
                recordingState = .permissionDenied
                showPermissionAlert = true
            }
        }
    }

    private func startSession() async {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("quran_recitation.m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            audioRecorder = try AVAudioRecorder(url: tempURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            recordingState = .recording
            remainingSeconds = recordingDuration
            meterTask = Task { [weak self] in
                guard let self else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    if Task.isCancelled { return }
                    await MainActor.run {
                        self.updateAudioLevel()
                    }
                }
            }
            stopTask = Task { [weak self] in
                guard let self else { return }
                for second in stride(from: recordingDuration, through: 1, by: -1) {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if Task.isCancelled { return }
                    await MainActor.run {
                        self.remainingSeconds = second - 1
                    }
                }
                if !Task.isCancelled {
                    await MainActor.run {
                        self.stopRecording()
                    }
                }
            }
        } catch {
            recordingState = .completed(nil)
        }
    }

    private func updateAudioLevel() {
        guard let recorder = audioRecorder else {
            audioLevel = 0
            return
        }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        let level = max(0, min(1, (power + 80) / 80))
        audioLevel = pow(level, 1.5)
    }
    func playLastRecording() {
        guard let url = lastRecordingURL else { return }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            print("AudioRecorder: playback failed: \(error)")
        }
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            recordingState = .completed(nil)
        }
    }
}
