import Foundation

/// Bündelt Korantext und Übersetzungen. Wird einmal beim App-Start geladen.
nonisolated struct QuranLibrary: Sendable {
    let text: QuranText
    let translations: TranslationStore

    /// Lädt alles abseits des Main-Threads (ca. 1,5 MB XML je Ausgabe).
    static func load(from bundle: Bundle = .main) async throws -> QuranLibrary {
        try await Task.detached(priority: .userInitiated) {
            try QuranLibrary(text: QuranText.load(from: bundle), translations: TranslationStore(bundle: bundle))
        }.value
    }

    /// Übersetzung eines Verses in der gewählten Sprache.
    func translation(of verse: VerseID, in language: TranslationLanguage) throws -> String? {
        guard let info = translations.info(forLanguage: language.rawValue) else { return nil }
        return try translations.translation(forKey: info.key).text(for: verse)
    }
}
