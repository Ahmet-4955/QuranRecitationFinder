import Foundation
import Speech

class AudioMatchManager {
    private let dataset = QuranRecitationDataset.shared

    var datasetInfo: String {
        dataset.infoDescription
    }

    var datasetCount: Int {
        dataset.verses.count
    }

    func matchAudioFile(url: URL, completion: @escaping (QuranVerse?) -> Void) {
        transcribeAudio(url: url) { [weak self] transcription in
            DispatchQueue.global(qos: .userInitiated).async {
                let matchedVerse: QuranVerse?

                if let transcription, !transcription.isEmpty {
                    matchedVerse = self?.dataset.matchCandidate(for: transcription)
                } else {
                    matchedVerse = self?.dataset.matchCandidate(for: url)
                }

                DispatchQueue.main.async {
                    completion(matchedVerse)
                }
            }
        }
    }

    func sampleMatchResult() -> QuranVerse? {
        dataset.randomSample()
    }

    private func transcribeAudio(url: URL, completion: @escaping (String?) -> Void) {
        let localeIdentifiers = ["ar-SA", "ar"]
        guard let speechRecognizer = Self.availableSpeechRecognizer(for: localeIdentifiers) else {
            completion(nil)
            return
        }

        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                completion(nil)
                return
            }

            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = true
            request.taskHint = .dictation

            var recognitionTask: SFSpeechRecognitionTask?
            var lastTranscription: String?
            var didComplete = false

            let finishRecognition: (String?) -> Void = { text in
                guard !didComplete else { return }
                didComplete = true
                recognitionTask?.cancel()
                completion(text)
            }

            let timeoutWorkItem = DispatchWorkItem {
                finishRecognition(lastTranscription)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: timeoutWorkItem)

            recognitionTask = speechRecognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    print("Speech recognition error: \(error)")
                    timeoutWorkItem.cancel()
                    finishRecognition(lastTranscription)
                    return
                }

                if let result = result {
                    lastTranscription = result.bestTranscription.formattedString
                    if result.isFinal {
                        timeoutWorkItem.cancel()
                        finishRecognition(lastTranscription)
                    }
                }
            }
        }
    }

    private static func availableSpeechRecognizer(for identifiers: [String]) -> SFSpeechRecognizer? {
        for identifier in identifiers {
            if let recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier)), recognizer.isAvailable {
                return recognizer
            }
        }
        return nil
    }
}
