import SwiftUI

struct SettingsView: View {
    let context: AppContext
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var app: AppModel
    @State private var records: [FeedbackRecord] = []
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var confirmDelete = false

    private var recognizerStatusText: String {
        switch app.recognizerStatus {
        case .preparing: return "wird geladen …"
        case .ready: return "bereit"
        case .unavailable: return "nicht verfügbar"
        case .failed: return "Fehler"
        }
    }

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
                    LabeledContent("Status", value: recognizerStatusText)
                    NavigationLink("Quellen & Lizenzen") {
                        LicensesView(context: context)
                    }
                } header: {
                    Text("Info")
                }

                Section {
                    LabeledContent("Einträge", value: "\(records.count)")
                    LabeledContent("Bewertet richtig / falsch",
                                   value: "\(records.filter { $0.verdict == .correct }.count) / \(records.filter { $0.verdict == .wrong }.count)")
                    LabeledContent("Schwelle", value: String(format: "%.2f", context.config.acceptThreshold))
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Protokoll teilen", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button("Protokoll exportieren") {
                            do {
                                exportURL = try context.feedback.exportFile()
                            } catch {
                                exportError = error.localizedDescription
                            }
                        }
                        .disabled(records.isEmpty)
                    }
                    if let exportError {
                        Text(exportError).foregroundStyle(.red).font(.footnote)
                    }
                    Button("Protokoll löschen", role: .destructive) { confirmDelete = true }
                        .disabled(records.isEmpty)
                } header: {
                    Text("Testprotokoll (Feinabstimmung)")
                } footer: {
                    Text("Jede Erkennung wird mit Ihrer Bewertung gespeichert – nur auf diesem Gerät. Export per AirDrop an den Mac, dann Tools/phase5/calibrate.py.")
                }
            }
            .navigationTitle("Einstellungen")
            .onAppear {
                records = context.feedback.records
                exportURL = nil
            }
            .confirmationDialog("Testprotokoll löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    context.feedback.removeAll()
                    records = []
                    exportURL = nil
                }
            }
        }
    }
}
