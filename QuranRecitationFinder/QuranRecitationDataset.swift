import Foundation
import AVFoundation
import Accelerate

/// Grundlage für den Hugging Face "Quran-Recitations"-Ansatz.
///
/// In einer echten App würde hier ein vorab geladenes Dataset benutzt werden,
/// z. B. verse-level Audio-Dateien oder Metadaten aus dem HF-Dataset.
/// Aktuell versucht die App, ein lokales JSON-Sample zu laden und greift bei
/// Bedarf auf eine eingebaute Beispielmenge zurück.
struct QuranVerse: Identifiable, Codable, Hashable {
    let id: String
    let surahNumber: Int
    let ayahNumber: Int
    let surahName: String
    let text: String
    let source: String?
    let audioPath: String?
    let audioURL: String?

    var displayName: String {
        "Sure \(surahName), Vers \(ayahNumber)"
    }

    var displayDetail: String {
        if let source {
            return "\(displayName) – \(source)"
        }
        return displayName
    }

    var audioSourceDescription: String? {
        if let audioPath {
            return "Lokale Referenz: \(audioPath)"
        }
        if let audioURL {
            return "Remote Audio: \(audioURL)"
        }
        return nil
    }
}

struct QuranAudioFeatures: Hashable {
    let duration: TimeInterval
    let rms: Float
    let peak: Float
    let averagePower: Float

    static func from(url: URL) -> QuranAudioFeatures? {
        guard let file = try? AVAudioFile(forReading: url) else {
            return nil
        }

        let format = file.processingFormat
        let frameLength = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else {
            return nil
        }

        do {
            try file.read(into: buffer)
        } catch {
            return nil
        }

        let channelCount = Int(format.channelCount)
        let sampleCount = Int(buffer.frameLength) * channelCount
        guard sampleCount > 0 else {
            return nil
        }

        var sumSquares: Float = 0
        var peak: Float = 0

        if let floatData = buffer.floatChannelData {
            for channel in 0..<channelCount {
                let channelData = floatData[channel]
                for sampleIndex in 0..<Int(buffer.frameLength) {
                    let sample = channelData[sampleIndex]
                    sumSquares += sample * sample
                    peak = max(peak, abs(sample))
                }
            }
        } else if let int16Data = buffer.int16ChannelData {
            for channel in 0..<channelCount {
                let channelData = int16Data[channel]
                for sampleIndex in 0..<Int(buffer.frameLength) {
                    let sample = Float(channelData[sampleIndex]) / Float(Int16.max)
                    sumSquares += sample * sample
                    peak = max(peak, abs(sample))
                }
            }
        } else {
            return nil
        }

        let rms = sqrt(sumSquares / Float(sampleCount))
        let averagePower = 20 * log10(max(rms, 0.000_000_1))

        return QuranAudioFeatures(
            duration: Double(file.length) / format.sampleRate,
            rms: rms,
            peak: peak,
            averagePower: averagePower
        )
    }
}

struct QuranAudioFingerprint: Hashable {
    let duration: TimeInterval
    let spectralCentroid: Float
    let spectralBandwidth: Float
    let normalizedBandEnergy: [Float]

    static func from(url: URL) -> QuranAudioFingerprint? {
        guard let file = try? AVAudioFile(forReading: url) else {
            return nil
        }

        let format = file.processingFormat
        let frameLength = AVAudioFrameCount(file.length)
        let targetLength = AVAudioFrameCount(min(Double(frameLength), format.sampleRate * 3.0))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: targetLength) else {
            return nil
        }

        do {
            try file.read(into: buffer, frameCount: targetLength)
        } catch {
            return nil
        }

        guard let floatData = buffer.floatChannelData else {
            return nil
        }

        let channelCount = Int(format.channelCount)
        let sampleCount = Int(buffer.frameLength)
        guard sampleCount > 0 else {
            return nil
        }

        var mono = [Float](repeating: 0, count: sampleCount)
        for frameIndex in 0..<sampleCount {
            var sum: Float = 0
            for channel in 0..<channelCount {
                sum += floatData[channel][frameIndex]
            }
            mono[frameIndex] = sum / Float(channelCount)
        }

        guard let fingerprintData = buildFingerprint(from: mono, sampleRate: format.sampleRate) else {
            return nil
        }

        return QuranAudioFingerprint(
            duration: Double(frameLength) / format.sampleRate,
            spectralCentroid: fingerprintData.centroid,
            spectralBandwidth: fingerprintData.bandwidth,
            normalizedBandEnergy: fingerprintData.bands
        )
    }

    private static func buildFingerprint(from samples: [Float], sampleRate: Double) -> (centroid: Float, bandwidth: Float, bands: [Float])? {
        let count = samples.count
        guard count > 0 else { return nil }

        let fftSize = 1 << Int(ceil(log2(Double(count))))
        let halfSize = fftSize / 2
        let log2Size = vDSP_Length(log2(Float(fftSize)))

        var paddedSamples = samples + [Float](repeating: 0, count: fftSize - count)
        var realp = [Float](repeating: 0, count: halfSize)
        var imagp = [Float](repeating: 0, count: halfSize)

        paddedSamples.withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { complexPointer in
                realp.withUnsafeMutableBufferPointer { realPtr in
                    imagp.withUnsafeMutableBufferPointer { imagPtr in
                        var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                        guard let fftSetup = vDSP_create_fftsetup(log2Size, FFTRadix(kFFTRadix2)) else { return }
                        vDSP_ctoz(complexPointer, 2, &splitComplex, 1, vDSP_Length(halfSize))
                        vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2Size, FFTDirection(FFT_FORWARD))
                        vDSP_destroy_fftsetup(fftSetup)
                    }
                }
            }
        }

        var magnitudes = [Float](repeating: 0, count: halfSize)
        realp.withUnsafeMutableBufferPointer { realPtr in
            imagp.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfSize))
            }
        }

        var powerSpectrum = [Float](repeating: 0, count: halfSize)
        vDSP_vsq(magnitudes, 1, &powerSpectrum, 1, vDSP_Length(halfSize))

        let bandCount = 16
        let binPerBand = max(1, halfSize / bandCount)
        var bands = [Float](repeating: 0, count: bandCount)
        for band in 0..<bandCount {
            let start = band * binPerBand
            let end = min(halfSize, start + binPerBand)
            if start < end {
                let slice = powerSpectrum[start..<end]
                bands[band] = slice.reduce(0, +)
            }
        }

        if let maxEnergy = bands.max(), maxEnergy > 0 {
            bands = bands.map { $0 / maxEnergy }
        }

        var frequencyWeights = [Float](repeating: 0, count: halfSize)
        let nyquist = Float(sampleRate / 2)
        for i in 0..<halfSize {
            frequencyWeights[i] = Float(i) * nyquist / Float(halfSize)
        }

        var weightedPower = [Float](repeating: 0, count: halfSize)
        vDSP_vmul(powerSpectrum, 1, frequencyWeights, 1, &weightedPower, 1, vDSP_Length(halfSize))

        let totalEnergy = powerSpectrum.reduce(0, +)
        let centroid = totalEnergy > 0 ? weightedPower.reduce(0, +) / totalEnergy : 0

        var centroidDiff = [Float](repeating: 0, count: halfSize)
        if totalEnergy > 0 {
            let centroidValue = centroid
            var tmp = [Float](repeating: 0, count: halfSize)
            vDSP_vsmsa(frequencyWeights, 1, [1.0], [-centroidValue], &tmp, 1, vDSP_Length(halfSize))
            vDSP_vsq(tmp, 1, &centroidDiff, 1, vDSP_Length(halfSize))
            var weightedBandwidth = [Float](repeating: 0, count: halfSize)
            vDSP_vmul(centroidDiff, 1, powerSpectrum, 1, &weightedBandwidth, 1, vDSP_Length(halfSize))
            let bandwidth = sqrt(weightedBandwidth.reduce(0, +) / totalEnergy)
            return (centroid: centroid, bandwidth: bandwidth, bands: bands)
        }

        return (centroid: 0, bandwidth: 0, bands: bands)
    }
}

final class QuranRecitationDataset {
    static let shared = QuranRecitationDataset()
    let verses: [QuranVerse]
    let isLoadedFromBundle: Bool
    private var verseFeaturesCache: [String: QuranAudioFeatures] = [:]
    private var verseFingerprintCache: [String: QuranAudioFingerprint] = [:]

    private init() {
        if let loadResult = Self.loadSampleDataset() {
            verses = loadResult.verses
            isLoadedFromBundle = loadResult.loadedFromBundle
        } else {
            verses = Self.sampleVerses
            isLoadedFromBundle = false
        }
    }

    private static func loadSampleDataset() -> (verses: [QuranVerse], loadedFromBundle: Bool)? {
        guard let url = Bundle.main.url(forResource: "quran_recitations_sample", withExtension: "json") else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let verses = try decoder.decode([QuranVerse].self, from: data)
            return (verses: verses, loadedFromBundle: true)
        } catch {
            print("QuranRecitationDataset: Fehler beim Laden des Sample-Datasets: \(error)")
            return nil
        }
    }

    private static let sampleVerses: [QuranVerse] = [
        QuranVerse(
            id: "1-1",
            surahNumber: 1,
            ayahNumber: 1,
            surahName: "Al-Fatiha",
            text: "بِسْمِ اللَّهِ الرَّحْمَـٰنِ الرَّحِيمِ",
            source: "عبدالباسط عبدالصمد",
            audioPath: nil,
            audioURL: nil
        ),
        QuranVerse(
            id: "2-255",
            surahNumber: 2,
            ayahNumber: 255,
            surahName: "Al-Baqara",
            text: "اللَّهُ لَا إِلَٰهَ إِلَّا هُوَ الْحَيُّ الْقَيُّومُ",
            source: "محمود خليل الحصري",
            audioPath: nil,
            audioURL: nil
        ),
        QuranVerse(
            id: "3-18",
            surahNumber: 3,
            ayahNumber: 18,
            surahName: "Al-Imran",
            text: "شَهِدَ اللَّهُ أَنَّهُ لَا إِلَٰهَ إِلَّا هُوَ",
            source: "محمود خليل الحصري",
            audioPath: nil,
            audioURL: nil
        ),
        QuranVerse(
            id: "4-1",
            surahNumber: 4,
            ayahNumber: 1,
            surahName: "An-Nisa",
            text: "يَا أَيُّهَا النَّاسُ اتَّقُوا رَبَّكُمْ",
            source: "مشاري العفاسي",
            audioPath: nil,
            audioURL: nil
        ),
        QuranVerse(
            id: "5-3",
            surahNumber: 5,
            ayahNumber: 3,
            surahName: "Al-Ma'idah",
            text: "حُرِّمَتْ عَلَيْكُمُ الْمَيْتَةُ",
            source: "علي الحذيفي",
            audioPath: nil,
            audioURL: nil
        ),
        QuranVerse(
            id: "7-1",
            surahNumber: 7,
            ayahNumber: 1,
            surahName: "Al-A'raf",
            text: "الم",
            source: "عبدالباسط عبدالصمد",
            audioPath: nil,
            audioURL: nil
        ),
        QuranVerse(
            id: "10-1",
            surahNumber: 10,
            ayahNumber: 1,
            surahName: "Yunus",
            text: "الر",
            source: "محمود خليل الحصري",
            audioPath: nil,
            audioURL: nil
        ),
        QuranVerse(
            id: "18-1",
            surahNumber: 18,
            ayahNumber: 1,
            surahName: "Al-Kahf",
            text: "الْحَمْدُ لِلَّهِ الَّذِي أَنزَلَ عَلَى عَبْدِهِ الْكِتَابَ",
            source: "مشاري العفاسي",
            audioPath: nil,
            audioURL: nil
        ),
        QuranVerse(
            id: "36-1",
            surahNumber: 36,
            ayahNumber: 1,
            surahName: "Yasin",
            text: "يس",
            source: "مشاري العفاسي",
            audioPath: nil,
            audioURL: nil
        ),
        QuranVerse(
            id: "51-1",
            surahNumber: 51,
            ayahNumber: 1,
            surahName: "Adh-Dhariyat",
            text: "وَالذَّارِيَاتِ ذَرْوًا",
            source: "علي الحذيفي",
            audioPath: nil,
            audioURL: nil
        ),
        QuranVerse(
            id: "55-1",
            surahNumber: 55,
            ayahNumber: 1,
            surahName: "Ar-Rahman",
            text: "الرَّحْمَٰنُ",
            source: "علي الحذيفي",
            audioPath: nil,
            audioURL: nil
        ),
        QuranVerse(
            id: "68-1",
            surahNumber: 68,
            ayahNumber: 1,
            surahName: "Al-Qalam",
            text: "ن وَالْقَلَمِ وَمَا يَسْطُرُونَ",
            source: "عبدالباسط عبدالصمد",
            audioPath: nil,
            audioURL: nil
        ),
        QuranVerse(
            id: "87-1",
            surahNumber: 87,
            ayahNumber: 1,
            surahName: "Al-A'la",
            text: "سَبِّحِ اسْمَ رَبِّكَ الْأَعْلَى",
            source: "علي الحذيفي",
            audioPath: nil,
            audioURL: nil
        ),
        QuranVerse(
            id: "93-1",
            surahNumber: 93,
            ayahNumber: 1,
            surahName: "Ad-Duha",
            text: "وَالضُّحَىٰ",
            source: "مشاري العفاسي",
            audioPath: nil,
            audioURL: nil
        ),
        QuranVerse(
            id: "100-1",
            surahNumber: 100,
            ayahNumber: 1,
            surahName: "Al-Adiyat",
            text: "وَالْعَادِيَاتِ ضَبْحًا",
            source: "عبدالباسط عبدالصمد",
            audioPath: nil,
            audioURL: nil
        ),
        QuranVerse(
            id: "106-1",
            surahNumber: 106,
            ayahNumber: 1,
            surahName: "Quraysh",
            text: "لِإِيلَافِ قُرَيْشٍ",
            source: "عبدالباسط عبدالصمد",
            audioPath: nil,
            audioURL: nil
        ),
        QuranVerse(
            id: "107-1",
            surahNumber: 107,
            ayahNumber: 1,
            surahName: "Al-Ma'un",
            text: "أَرَأَيْتَ الَّذِي يُكَذِّبُ بِالدِّينِ",
            source: "عبدالباسط عبدالصمد",
            audioPath: nil,
            audioURL: nil
        ),
        QuranVerse(
            id: "108-1",
            surahNumber: 108,
            ayahNumber: 1,
            surahName: "Al-Kawthar",
            text: "إِنَّا أَعْطَيْنَاكَ الْكَوْثَرَ",
            source: "عبدالباسط عبدالصمد",
            audioPath: nil,
            audioURL: nil
        ),
        QuranVerse(
            id: "109-1",
            surahNumber: 109,
            ayahNumber: 1,
            surahName: "Al-Kafirun",
            text: "قُلْ يَا أَيُّهَا الْكَافِرُونَ",
            source: "عبدالباسط عبدالصمد",
            audioPath: nil,
            audioURL: nil
        ),
        QuranVerse(
            id: "110-1",
            surahNumber: 110,
            ayahNumber: 1,
            surahName: "An-Nasr",
            text: "إِذَا جَاءَ نَصْرُ اللَّهِ وَالْفَتْحُ",
            source: "عبدالباسط عبدالصمد",
            audioPath: nil,
            audioURL: nil
        ),
        QuranVerse(
            id: "111-1",
            surahNumber: 111,
            ayahNumber: 1,
            surahName: "Al-Masad",
            text: "تَبَّتْ يَدَا أَبِي لَهَبٍ وَتَبَّ",
            source: "عبدالباسط عبدالصمد",
            audioPath: nil,
            audioURL: nil
        ),
        QuranVerse(
            id: "112-1",
            surahNumber: 112,
            ayahNumber: 1,
            surahName: "Al-Ikhlas",
            text: "قُلْ هُوَ اللَّهُ أَحَدٌ",
            source: "عبدالباسط عبدالصمد",
            audioPath: nil,
            audioURL: nil
        ),
        QuranVerse(
            id: "113-1",
            surahNumber: 113,
            ayahNumber: 1,
            surahName: "Al-Falaq",
            text: "قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ",
            source: "مشاري العفاسي",
            audioPath: nil,
            audioURL: nil
        ),
        QuranVerse(
            id: "114-1",
            surahNumber: 114,
            ayahNumber: 1,
            surahName: "An-Nas",
            text: "قُلْ أَعُوذُ بِرَبِّ النَّاسِ",
            source: "علي الحذيفي",
            audioPath: nil,
            audioURL: nil
        )
    ]

    var infoDescription: String {
        let sourceDescription = isLoadedFromBundle ? "sample JSON aus dem Bundle" : "eingebaute Ersatzdaten"
        return "Dataset geladen: \(verses.count) Verse • \(sourceDescription)"
    }

    func matchCandidate(for transcription: String) -> QuranVerse? {
        let normalizedTranscription = Self.normalizeText(transcription)

        let scored = verses.map { verse -> (QuranVerse, Int) in
            return (verse, similarityScore(between: normalizedTranscription, and: verse))
        }

        if let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= 45 {
            return best.0
        }

        return matchCandidate(for: normalizedTranscription, fallbackUsing: normalizedTranscription)
    }

    private static func normalizeText(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
        let filteredScalars = folded.unicodeScalars.filter { scalar in
            let allowed = CharacterSet.letters.union(.whitespaces)
            return allowed.contains(scalar)
        }

        let cleaned = String(String.UnicodeScalarView(filteredScalars))
        let tokens = cleaned.split { $0.isWhitespace }.map(String.init)
        return tokens.joined(separator: " ")
    }

    private static func similarityScore(between a: String, and b: String) -> Int {
        let aTokens = a.split(separator: " ").map(String.init)
        let bTokens = b.split(separator: " ").map(String.init)
        let intersection = Set(aTokens).intersection(Set(bTokens)).count
        let union = Set(aTokens).union(Set(bTokens)).count
        let jaccard = union > 0 ? Float(intersection) / Float(union) : 0
        let sequenceScore = longestCommonTokenSequenceRatio(aTokens, bTokens)
        return Int((jaccard * 60 + sequenceScore * 40) * 100)
    }

    private func similarityScore(between source: String, and verse: QuranVerse) -> Int {
        let normalizedVerse = Self.normalizeText(verse.text)
        let baseScore = Self.similarityScore(between: source, and: normalizedVerse)
        let feedbackBonus = FeedbackManager.shared.confidenceBonus(for: verse)
        return baseScore + feedbackBonus
    }

    private static func longestCommonTokenSequenceRatio(_ a: [String], _ b: [String]) -> Float {
        let rows = a.count + 1
        let cols = b.count + 1
        var dp = Array(repeating: Array(repeating: 0, count: cols), count: rows)
        var longest = 0

        for i in 1..<rows {
            for j in 1..<cols {
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                    longest = max(longest, dp[i][j])
                }
            }
        }

        let maxLength = max(a.count, b.count)
        guard maxLength > 0 else { return 0 }
        return Float(longest) / Float(maxLength)
    }

    private func matchCandidate(for transcription: String, fallbackUsing normalizedTranscription: String) -> QuranVerse? {
        let bestMatch = verses.max(by: { verseA, verseB in
            let scoreA = similarityScore(between: normalizedTranscription, and: verseA)
            let scoreB = similarityScore(between: normalizedTranscription, and: verseB)
            return scoreA < scoreB
        })
        return bestMatch ?? verses.randomElement()
    }

    func matchCandidate(for audioURL: URL) -> QuranVerse? {
        guard !verses.isEmpty else { return nil }
        guard let inputFeatures = QuranAudioFeatures.from(url: audioURL) else { return nil }

        if let inputFingerprint = QuranAudioFingerprint.from(url: audioURL) {
            return matchCandidate(for: inputFeatures, fingerprint: inputFingerprint)
        }

        return matchCandidate(for: inputFeatures)
    }

    func matchCandidate(for inputFeatures: QuranAudioFeatures) -> QuranVerse? {
        let candidates: [(QuranVerse, QuranAudioFeatures)] = verses.compactMap { verse in
            guard let verseFeatures = sampleFeatures(for: verse) else { return nil }
            return (verse, verseFeatures)
        }

        if !candidates.isEmpty {
            return candidates.min(by: { score(features: inputFeatures, candidate: $0.1) < score(features: inputFeatures, candidate: $1.1) })?.0
        }

        let index = Int((inputFeatures.duration * 10).rounded()) % verses.count
        return verses[index]
    }

    func matchCandidate(for inputFeatures: QuranAudioFeatures, fingerprint: QuranAudioFingerprint) -> QuranVerse? {
        let candidates: [(QuranVerse, QuranAudioFingerprint, QuranAudioFeatures)] = verses.compactMap { verse in
            guard let verseFingerprint = sampleFingerprint(for: verse), let verseFeatures = sampleFeatures(for: verse) else { return nil }
            return (verse, verseFingerprint, verseFeatures)
        }

        if !candidates.isEmpty {
            return candidates.min(by: { candidateA, candidateB in
                let scoreA = combinedScore(inputFeatures: inputFeatures, inputFingerprint: fingerprint, verseFeatures: candidateA.2, verseFingerprint: candidateA.1)
                let scoreB = combinedScore(inputFeatures: inputFeatures, inputFingerprint: fingerprint, verseFeatures: candidateB.2, verseFingerprint: candidateB.1)
                return scoreA < scoreB
            })?.0
        }

        return matchCandidate(for: inputFeatures)
    }

    private func sampleAudioURL(for verse: QuranVerse) -> URL? {
        guard let remoteURL = remoteAudioURL(for: verse) else {
            return nil
        }
        return downloadRemoteAudioIfNeeded(from: remoteURL)
    }

    private func remoteAudioURL(for verse: QuranVerse) -> URL? {
        guard let audioURL = verse.audioURL else { return nil }
        return URL(string: audioURL)
    }

    private func downloadRemoteAudioIfNeeded(from url: URL) -> URL? {
        guard let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }

        let remoteCache = cachesDirectory.appendingPathComponent("quran_audio_cache", isDirectory: true)
        let destinationURL = remoteCache.appendingPathComponent(url.lastPathComponent)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }

        do {
            try FileManager.default.createDirectory(at: remoteCache, withIntermediateDirectories: true)
            let data = try Data(contentsOf: url)
            try data.write(to: destinationURL)
            return destinationURL
        } catch {
            print("QuranRecitationDataset: remote audio download failed for \(url): \(error)")
            return nil
        }
    }

    private func sampleFeatures(for verse: QuranVerse) -> QuranAudioFeatures? {
        if let cached = verseFeaturesCache[verse.id] {
            return cached
        }

        guard let url = sampleAudioURL(for: verse), let features = QuranAudioFeatures.from(url: url) else {
            return nil
        }

        verseFeaturesCache[verse.id] = features
        return features
    }

    private func sampleFingerprint(for verse: QuranVerse) -> QuranAudioFingerprint? {
        if let cached = verseFingerprintCache[verse.id] {
            return cached
        }

        guard let url = sampleAudioURL(for: verse), let fingerprint = QuranAudioFingerprint.from(url: url) else {
            return nil
        }

        verseFingerprintCache[verse.id] = fingerprint
        return fingerprint
    }

    private func score(features: QuranAudioFeatures, candidate: QuranAudioFeatures) -> Float {
        let durationDiff = abs(Float(features.duration - candidate.duration))
        let rmsDiff = abs(features.rms - candidate.rms)
        let powerDiff = abs(features.averagePower - candidate.averagePower)
        return durationDiff * 2.0 + rmsDiff * 10.0 + powerDiff * 0.5
    }

    private func score(fingerprint: QuranAudioFingerprint, candidate: QuranAudioFingerprint) -> Float {
        let durationDiff = abs(Float(fingerprint.duration - candidate.duration))
        let centroidDiff = abs(fingerprint.spectralCentroid - candidate.spectralCentroid)
        let bandwidthDiff = abs(fingerprint.spectralBandwidth - candidate.spectralBandwidth)

        var bandDiff: Float = 0
        let bandCount = min(fingerprint.normalizedBandEnergy.count, candidate.normalizedBandEnergy.count)
        for index in 0..<bandCount {
            bandDiff += abs(fingerprint.normalizedBandEnergy[index] - candidate.normalizedBandEnergy[index])
        }

        return durationDiff * 2.5 + centroidDiff * 0.05 + bandwidthDiff * 0.05 + bandDiff * 1.0
    }

    private func combinedScore(inputFeatures: QuranAudioFeatures, inputFingerprint: QuranAudioFingerprint, verseFeatures: QuranAudioFeatures, verseFingerprint: QuranAudioFingerprint) -> Float {
        let featureScore = score(features: inputFeatures, candidate: verseFeatures)
        let fingerprintScore = score(fingerprint: inputFingerprint, candidate: verseFingerprint)
        return featureScore * 0.4 + fingerprintScore * 0.6
    }

    func randomSample() -> QuranVerse? {
        verses.randomElement()
    }
}
