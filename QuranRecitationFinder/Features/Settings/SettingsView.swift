import SwiftUI

struct SettingsView: View {
    let context: AppContext
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Sprache", selection: $settings.translationLanguage) {
                        ForEach(TranslationLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    if let info = context.library.translations.info(forLanguage: settings.translationLanguage.rawValue) {
                        LabeledContent("Übersetzung", value: info.title)
                        LabeledContent("Version", value: info.version)
                    } else {
                        Text("Für diese Sprache ist keine Übersetzung eingebaut.")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Übersetzung")
                }

                Section {
                    Stepper(value: $settings.maxRecordingSeconds, in: AppSettings.recordingRange) {
                        LabeledContent("Höchstdauer", value: "\(settings.maxRecordingSeconds) s")
                    }
                } header: {
                    Text("Aufnahme")
                } footer: {
                    Text("Die Aufnahme endet automatisch nach dieser Zeit. 8–15 Sekunden reichen meist.")
                }

                Section {
                    LabeledContent("Spracherkennung", value: context.recognizer.displayName)
                    NavigationLink("Quellen & Lizenzen") {
                        LicensesView(context: context)
                    }
                } header: {
                    Text("Info")
                }
            }
            .navigationTitle("Einstellungen")
        }
    }
}
