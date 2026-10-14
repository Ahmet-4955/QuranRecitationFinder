import Combine
import Foundation

/// Alles, was die Oberfläche nach dem Laden braucht.
struct AppContext {
    let library: QuranLibrary
    let matcher: VerseMatcher
    let recognizer: any RecitationRecognizer
    let config: RecognitionConfig
    let feedback: FeedbackLog
}

/// Lädt Korantext, Übersetzungen und den Suchindex beim App-Start.
final class AppModel: ObservableObject {
    enum State {
        case loading
        case ready(AppContext)
        case failed(String)
    }

    /// Zustand der Spracherkennung (Modell laden dauert beim ersten Start einige Sekunden).
    enum RecognizerStatus: Equatable {
        case preparing
        case ready
        case unavailable(String)
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var recognizerStatus: RecognizerStatus = .preparing
    let settings: AppSettings
    let history: HistoryStore
    let feedback: FeedbackLog
    private let recognizer: any RecitationRecognizer

    init(settings: AppSettings = AppSettings(), history: HistoryStore = HistoryStore(),
         feedback: FeedbackLog = FeedbackLog(),
         recognizer: any RecitationRecognizer = RecognizerFactory.make()) {
        self.settings = settings
        self.history = history
        self.feedback = feedback
        self.recognizer = recognizer
    }

    func load() async {
        guard case .loading = state else { return }
        do {
            let library = try await QuranLibrary.load()
            // Index über ~77.400 Wörter abseits des Main-Threads aufbauen
            let language = settings.translationLanguage.rawValue
            let config = RecognitionConfig.load()
            let matcher = await Task.detached(priority: .userInitiated) {
                // gewählte Übersetzung vorladen, damit das erste Ergebnis nicht stockt
                if let info = library.translations.info(forLanguage: language) {
                    _ = try? library.translations.translation(forKey: info.key)
                }
                return VerseMatcher(quran: library.text, edition: config.matcherEdition,
                                    configuration: config.matcherConfiguration)
            }.value
            state = .ready(AppContext(library: library, matcher: matcher, recognizer: recognizer,
                                      config: config, feedback: feedback))
        } catch {
            state = .failed(error.localizedDescription)
            return
        }
        await prepareRecognizer()
    }

    /// Lädt das Sprachmodell vor, damit die erste Erkennung nicht warten muss.
    func prepareRecognizer() async {
        if let unavailable = recognizer as? UnavailableRecognizer {
            recognizerStatus = .unavailable(unavailable.reason)
            return
        }
        recognizerStatus = .preparing
        do {
            try await recognizer.prepare()
            recognizerStatus = .ready
        } catch {
            recognizerStatus = .failed(error.localizedDescription)
        }
    }
}
