import Foundation
import Testing
@testable import QuranRecitationFinder

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
