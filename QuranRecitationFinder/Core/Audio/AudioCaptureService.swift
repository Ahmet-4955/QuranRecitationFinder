import AVFoundation
import Foundation

/// Nimmt über AVAudioEngine auf und wandelt direkt in 16 kHz mono um
/// (Eingangsformat von Whisper).
final class AudioCaptureService: AudioCapturing {
    static let sampleRate = AudioFormat.sampleRate

    private let engine = AVAudioEngine()
    private let collector = SampleCollector()

    var level: Float { collector.level }
    var elapsed: TimeInterval { Double(collector.sampleCount) / Self.sampleRate }

    func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        default:
            return await AVAudioApplication.requestRecordPermission()
        }
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
        } catch {
            throw AudioCaptureError.engineFailed(error)
        }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioFormat.sampleRate,
                                         channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: target) else {
            throw AudioCaptureError.formatUnavailable
        }

        collector.reset()
        Self.installTap(on: input, format: inputFormat, converter: converter, target: target, collector: collector)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw AudioCaptureError.engineFailed(error)
        }
    }

    func snapshot() -> [Float] {
        collector.snapshot()
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return collector.drain()
    }

    /// Bewusst `nonisolated`: der Tap-Block läuft auf dem Audio-Thread, nicht auf dem Main Actor.
    nonisolated private static func installTap(on input: AVAudioInputNode, format: AVAudioFormat,
                                               converter: AVAudioConverter, target: AVAudioFormat,
                                               collector: SampleCollector) {
        let ratio = target.sampleRate / format.sampleRate
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var delivered = false
            var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if delivered {
                    status.pointee = .noDataNow
                    return nil
                }
                delivered = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, let channel = output.floatChannelData?[0] else { return }
            collector.append(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
        }
    }
}

/// Sammelt Samples threadsicher (Audio-Thread schreibt, Main Actor liest).
nonisolated final class SampleCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var currentLevel: Float = 0

    var level: Float {
        lock.lock(); defer { lock.unlock() }
        return currentLevel
    }

    var sampleCount: Int {
        lock.lock(); defer { lock.unlock() }
        return samples.count
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        samples.removeAll(keepingCapacity: true)
        currentLevel = 0
    }

    func append(_ chunk: UnsafeBufferPointer<Float>) {
        guard !chunk.isEmpty else { return }
        var sum: Float = 0
        for s in chunk { sum += s * s }
        let rms = (sum / Float(chunk.count)).squareRoot()
        // grob auf 0…1: -60 dB … 0 dB
        let db = 20 * log10(max(rms, 1e-6))
        let normalized = max(0, min(1, (db + 60) / 60))
        lock.lock(); defer { lock.unlock() }
        samples.append(contentsOf: chunk)
        currentLevel = normalized
    }

    func snapshot() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return samples
    }

    func drain() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        let result = samples
        samples.removeAll()
        currentLevel = 0
        return result
    }
}
