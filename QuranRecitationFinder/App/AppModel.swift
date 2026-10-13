import Combine
import Foundation

/// Alles, was die Oberfläche nach dem Laden braucht.
struct AppContext {
    let library: QuranLibrary
    let matcher: VerseMatcher
    let recognizer: any RecitationRecognizer
}

/// Lädt Korantext, Übersetzungen und den Suchindex beim App-Start.
final class AppModel: ObservableObject {
    enum State {
        case loading
        case ready(AppContext)
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    let settings: AppSettings
    let history: HistoryStore
    private let recognizer: any RecitationRecognizer

    init(settings: AppSettings = AppSettings(), history: HistoryStore = HistoryStore(),
         recognizer: any RecitationRecognizer = UnavailableRecognizer()) {
        self.settings = settings
        self.history = history
        self.recognizer = recognizer
    }

    func load() async {
        guard case .loading = state else { return }
        do {
            let library = try await QuranLibrary.load()
            // Index über ~77.400 Wörter abseits des Main-Threads aufbauen
            let language = settings.translationLanguage.rawValue
            let matcher = await Task.detached(priority: .userInitiated) {
                // gewählte Übersetzung vorladen, damit das erste Ergebnis nicht stockt
                if let info = library.translations.info(forLanguage: language) {
                    _ = try? library.translations.translation(forKey: info.key)
                }
                return VerseMatcher(quran: library.text)
            }.value
            state = .ready(AppContext(library: library, matcher: matcher, recognizer: recognizer))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
