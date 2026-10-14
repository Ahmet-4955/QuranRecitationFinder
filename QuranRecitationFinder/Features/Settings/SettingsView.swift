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
        case .preparing: return NSLocalizedString("loading …", comment: "")
        case .ready: return NSLocalizedString("ready", comment: "")
        case .unavailable: return NSLocalizedString("not available", comment: "")
        case .failed: return NSLocalizedString("error", comment: "")
        }
    }

    private func verbatimPair(_ a: Int, _ b: Int) -> String { "\(a) / \(b)" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Language", selection: $settings.translationLanguage) {
                        ForEach(TranslationLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    if let info = context.library.translations.info(forLanguage: settings.translationLanguage.rawValue) {
                        LabeledContent("Translation", value: info.title)
                        LabeledContent("Version", value: info.version)
                    } else {
                        Text("No translation is built in for this language.")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Translation")
                }

                Section {
                    Button("Change app language") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } header: {
                    Text("App language")
                } footer: {
                    Text("The app language follows the iPhone language. It can be changed per app in the iOS settings.")
                }

                Section {
                    Stepper(value: $settings.maxRecordingSeconds, in: AppSettings.recordingRange) {
                        LabeledContent("Maximum length", value: String(format: NSLocalizedString("%@ s", comment: ""), String(settings.maxRecordingSeconds)))
                    }
                    Toggle("Stop automatically on silence", isOn: $settings.autoStopOnSilence)
                    Toggle("Recognize while still recording", isOn: $settings.earlyRecognition)
                } header: {
                    Text("Recording")
                } footer: {
                    Text("Maximum length: the recording ends after this time at the latest; 8–15 seconds are usually enough. Silence: stops after 2.5 s of quiet, breathing pauses are tolerated. Early recognition: once the verse is clearly recognized twice in a row, the recording ends immediately.")
                }

                Section {
                    LabeledContent("Speech recognition", value: context.recognizer.displayName)
                    LabeledContent("Status", value: recognizerStatusText)
                    NavigationLink("Sources & licenses") {
                        LicensesView(context: context)
                    }
                } header: {
                    Text("Info")
                }

                Section {
                    LabeledContent("Entries", value: String(records.count))
                    LabeledContent("Rated correct / wrong",
                                   value: verbatimPair(records.filter { $0.verdict == .correct }.count, records.filter { $0.verdict == .wrong }.count))
                    LabeledContent("Threshold", value: context.config.acceptThreshold.formatted(.number.precision(.fractionLength(2))))
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Share log", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button("Export log") {
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
                    Button("Delete log", role: .destructive) { confirmDelete = true }
                        .disabled(records.isEmpty)
                } header: {
                    Text("Test log (fine-tuning)")
                } footer: {
                    Text("Every recognition is saved with your rating – only on this device. Export via AirDrop to the Mac, then Tools/phase5/calibrate.py.")
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                records = context.feedback.records
                exportURL = nil
            }
            .confirmationDialog("Delete the test log?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    context.feedback.removeAll()
                    records = []
                    exportURL = nil
                }
            }
        }
    }
}
