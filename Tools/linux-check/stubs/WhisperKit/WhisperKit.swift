// Ersatz-Modul „WhisperKit“ – NUR für die Kompilierprüfung unter Linux.
//
// Enthält die öffentlichen Signaturen aus argmax-oss-swift v1.1.1, die die App nutzt
// (Sources/WhisperKit/Core/Configurations.swift, Models.swift, WhisperKit.swift), damit
// WhisperKitRecognizer.swift gegen die echte Schnittstelle übersetzt wird. Die Erkennung selbst
// ist simuliert und zählt gleichzeitige Aufrufe (Test der Reihenfolge).
import Foundation

public enum Logging {
    public enum LogLevel: Int, Sendable { case debug = 1, info = 2, error = 3, none = 4 }
}

public enum DecodingTask: Codable, CustomStringConvertible, CaseIterable, Sendable {
    case transcribe
    case translate
    public var description: String { self == .transcribe ? "transcribe" : "translate" }
}

public enum ChunkingStrategy: String, Codable, CaseIterable, Sendable { case none, vad }
public struct ModelComputeOptions: Sendable { public init() {} }
public struct AudioInputOptions: Sendable { public init() {} }
public protocol AudioProcessing {}
public protocol FeatureExtracting {}
public protocol AudioEncoding {}
public protocol TextDecoding {}
public protocol LogitsFiltering {}
public protocol SegmentSeeking {}
open class VoiceActivityDetector {}
public struct TranscriptionProgress: Sendable {}
public struct TranscriptionSegment: Sendable {}
public typealias TranscriptionCallback = @Sendable (TranscriptionProgress) -> Bool?
public typealias SegmentDiscoveryCallback = @Sendable (_ segments: [TranscriptionSegment]) -> Void

open class TranscriptionResult: @unchecked Sendable {
    public var text: String
    public init(text: String) { self.text = text }
}

public struct DecodingOptions: Codable, Sendable {
    public var task: DecodingTask
    public var language: String?
    public var temperature: Float
    public var usePrefillPrompt: Bool
    public var skipSpecialTokens: Bool
    public var withoutTimestamps: Bool

    public init(
        verbose: Bool = false,
        task: DecodingTask = .transcribe,
        language: String? = nil,
        temperature: Float = 0.0,
        temperatureIncrementOnFallback: Float = 0.2,
        temperatureFallbackCount: Int = 5,
        sampleLength: Int = 224,
        topK: Int = 5,
        usePrefillPrompt: Bool = true,
        detectLanguage: Bool? = nil,
        skipSpecialTokens: Bool = false,
        withoutTimestamps: Bool = false,
        wordTimestamps: Bool = false,
        maxInitialTimestamp: Float? = nil,
        maxWindowSeek: Int? = nil,
        clipTimestamps: [Float] = [],
        windowClipTime: Float = 1.0,
        promptTokens: [Int]? = nil,
        prefixTokens: [Int]? = nil,
        suppressBlank: Bool = false,
        suppressTokens: [Int]? = nil,
        compressionRatioThreshold: Float? = 2.4,
        logProbThreshold: Float? = -1.0,
        firstTokenLogProbThreshold: Float? = -1.5,
        noSpeechThreshold: Float? = 0.6,
        concurrentWorkerCount: Int? = nil,
        chunkingStrategy: ChunkingStrategy? = nil
    ) {
        self.task = task
        self.language = language
        self.temperature = temperature
        self.usePrefillPrompt = usePrefillPrompt
        self.skipSpecialTokens = skipSpecialTokens
        self.withoutTimestamps = withoutTimestamps
    }
}

open class WhisperKitConfig {
    public var modelFolder: String?
    public var tokenizerFolder: URL?
    public var download: Bool

    public init(model: String? = nil,
                downloadBase: URL? = nil,
                modelRepo: String? = nil,
                modelToken: String? = nil,
                modelEndpoint: String? = nil,
                modelFolder: String? = nil,
                tokenizerFolder: URL? = nil,
                computeOptions: ModelComputeOptions? = nil,
                audioInputConfig: AudioInputOptions? = nil,
                audioProcessor: (any AudioProcessing)? = nil,
                featureExtractor: (any FeatureExtracting)? = nil,
                audioEncoder: (any AudioEncoding)? = nil,
                textDecoder: (any TextDecoding)? = nil,
                logitsFilters: [any LogitsFiltering]? = nil,
                segmentSeeker: (any SegmentSeeking)? = nil,
                voiceActivityDetector: VoiceActivityDetector? = nil,
                verbose: Bool = true,
                logLevel: Logging.LogLevel = .info,
                prewarm: Bool? = nil,
                load: Bool? = nil,
                download: Bool = true,
                useBackgroundDownloadSession: Bool = false) {
        self.modelFolder = modelFolder
        self.tokenizerFolder = tokenizerFolder
        self.download = download
    }
}

open class WhisperKit {
    /// Simulation: Dauer je Erkennung, Zähler für gleichzeitige Aufrufe, Antworttext.
    public final class Simulation: @unchecked Sendable {
        public static let shared = Simulation()
        private let lock = NSLock()
        private var running = 0
        private var _maxConcurrent = 0
        private var _calls = 0
        public var delayNanoseconds: UInt64 = 50_000_000
        public var text = "قل هو الله احد"

        public var maxConcurrent: Int { lock.lock(); defer { lock.unlock() }; return _maxConcurrent }
        public var calls: Int { lock.lock(); defer { lock.unlock() }; return _calls }

        public func reset() {
            lock.lock(); defer { lock.unlock() }
            running = 0; _maxConcurrent = 0; _calls = 0
        }

        func enter() {
            lock.lock(); defer { lock.unlock() }
            running += 1; _calls += 1; _maxConcurrent = max(_maxConcurrent, running)
        }

        func leave() {
            lock.lock(); defer { lock.unlock() }
            running -= 1
        }
    }

    public init(_ config: WhisperKitConfig = WhisperKitConfig()) async throws {}

    open func transcribe(
        audioArray: [Float],
        decodeOptions: DecodingOptions? = nil,
        callback: TranscriptionCallback? = nil,
        segmentCallback: SegmentDiscoveryCallback? = nil
    ) async throws -> [TranscriptionResult] {
        let sim = Simulation.shared
        sim.enter()
        defer { sim.leave() }
        try await Task.sleep(nanoseconds: sim.delayNanoseconds)
        return [TranscriptionResult(text: sim.text)]
    }
}
