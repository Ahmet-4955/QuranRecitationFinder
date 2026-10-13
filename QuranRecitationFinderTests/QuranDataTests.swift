import Foundation
import Testing
@testable import QuranRecitationFinder

/// Abnahmetests Phase 1: Korantext und Übersetzungen vollständig im App-Bundle.
/// Voraussetzung: Tools/data/build_resources.py wurde ausgeführt.
struct QuranTextTests {
    private func loadQuran() throws -> QuranText {
        try QuranText.load(from: .main)
    }

    @Test func loadsCompleteText() throws {
        let quran = try loadQuran()
        #expect(quran.surahs.count == 114)
        #expect(quran.surahs.map(\.ayahCount).reduce(0, +) == 6236)
        #expect(quran.surah(1)?.ayahCount == 7)
        #expect(quran.surah(2)?.ayahCount == 286)
        #expect(quran.surah(114)?.ayahCount == 6)
        #expect(quran.surah(9)?.revelation == .medinan)
        #expect(quran.surah(1)?.transliteratedName.isEmpty == false)
    }

    @Test func everyVerseHasText() throws {
        let quran = try loadQuran()
        for index in 0..<QuranText.verseCount {
            let verse = try #require(quran.verse(atGlobalIndex: index))
            #expect(quran.displayText(verse)?.isEmpty == false, "Anzeigetext fehlt: \(verse)")
            #expect(quran.searchText(verse)?.isEmpty == false, "Suchtext fehlt: \(verse)")
        }
    }

    @Test func knownVerses() throws {
        let quran = try loadQuran()
        let kursi = try #require(quran.searchText(VerseID(surah: 2, ayah: 255)))
        #expect(ArabicNormalizer.normalize(kursi).hasPrefix("الله لا اله الا هو الحي القيوم"))
        let ikhlas = try #require(quran.searchText(VerseID(surah: 112, ayah: 1)))
        #expect(ArabicNormalizer.normalize(ikhlas) == "قل هو الله احد")
    }

    @Test func globalIndexRoundTrip() throws {
        let quran = try loadQuran()
        #expect(quran.globalIndex(of: VerseID(surah: 1, ayah: 1)) == 0)
        #expect(quran.globalIndex(of: VerseID(surah: 2, ayah: 1)) == 7)
        #expect(quran.globalIndex(of: VerseID(surah: 114, ayah: 6)) == 6235)
        for index in stride(from: 0, to: QuranText.verseCount, by: 1) {
            let verse = try #require(quran.verse(atGlobalIndex: index))
            #expect(quran.globalIndex(of: verse) == index)
        }
        #expect(quran.verse(atGlobalIndex: 6236) == nil)
        #expect(quran.globalIndex(of: VerseID(surah: 1, ayah: 8)) == nil)
        #expect(quran.globalIndex(of: VerseID(surah: 115, ayah: 1)) == nil)
    }

    @Test func versesInRangeAcrossSurahBoundary() throws {
        let quran = try loadQuran()
        let range = VerseRange(start: VerseID(surah: 1, ayah: 6), end: VerseID(surah: 2, ayah: 2))
        #expect(quran.verses(in: range).map(\.description) == ["1:6", "1:7", "2:1", "2:2"])
    }
}

struct TranslationTests {
    @Test func bundlesGermanTurkishEnglish() throws {
        let store = try TranslationStore(bundle: .main)
        for language in TranslationLanguage.allCases {
            #expect(store.info(forLanguage: language.rawValue) != nil, "Keine Übersetzung für \(language.rawValue)")
        }
    }

    @Test(arguments: TranslationLanguage.allCases)
    func translationIsComplete(language: TranslationLanguage) throws {
        let store = try TranslationStore(bundle: .main)
        let info = try #require(store.info(forLanguage: language.rawValue))
        let translation = try store.translation(forKey: info.key)
        let quran = try QuranText.load(from: .main)
        for index in 0..<QuranText.verseCount {
            let verse = try #require(quran.verse(atGlobalIndex: index))
            let text = translation.text(for: verse)
            #expect(text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                    "\(info.key): Übersetzung fehlt für \(verse)")
        }
        #expect(!info.version.isEmpty, "Versionsnummer fehlt (QuranEnc-Bedingung)")
    }

    @Test func libraryReturnsTranslation() async throws {
        let library = try await QuranLibrary.load(from: .main)
        let german = try library.translation(of: VerseID(surah: 1, ayah: 1), in: .german)
        #expect(german?.isEmpty == false)
    }
}

struct ArabicNormalizerTests {
    @Test func matchesPythonPrototype() {
        for (input, expected) in NormalizerFixtures.cases {
            #expect(ArabicNormalizer.normalize(input) == expected)
        }
    }

    @Test func basicRules() {
        #expect(ArabicNormalizer.normalize("ٱلرَّحْمَٰنِ ٱلرَّحِيمِ") == "الرحمن الرحيم")
        #expect(ArabicNormalizer.normalize("ٱلَّذِى") == "الذي")
        #expect(ArabicNormalizer.normalize("hello 123") == "")
        #expect(ArabicNormalizer.words("قُلْ هُوَ ٱللَّهُ أَحَدٌ") == ["قل", "هو", "الله", "احد"])
    }
}

struct VerseIDTests {
    @Test func parsingAndOrdering() {
        #expect(VerseID("2:255") == VerseID(surah: 2, ayah: 255))
        #expect(VerseID("2-255") == nil)
        #expect(VerseID(surah: 2, ayah: 286) < VerseID(surah: 3, ayah: 1))
        #expect(VerseRange(start: VerseID(surah: 2, ayah: 255), end: VerseID(surah: 2, ayah: 256)).description == "2:255–2:256")
    }
}

@MainActor
struct AppSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let name = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultFollowsDeviceLanguage() {
        #expect(AppSettings(defaults: freshDefaults(), locale: Locale(identifier: "de_DE")).translationLanguage == .german)
        #expect(AppSettings(defaults: freshDefaults(), locale: Locale(identifier: "tr_TR")).translationLanguage == .turkish)
        #expect(AppSettings(defaults: freshDefaults(), locale: Locale(identifier: "fr_FR")).translationLanguage == .english)
    }

    @Test func choiceIsPersisted() {
        let defaults = freshDefaults()
        AppSettings(defaults: defaults, locale: Locale(identifier: "de_DE")).translationLanguage = .turkish
        #expect(AppSettings(defaults: defaults, locale: Locale(identifier: "de_DE")).translationLanguage == .turkish)
    }
}
