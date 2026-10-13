import SwiftUI

struct RecognizeView: View {
    let context: AppContext
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var history: HistoryStore
    @StateObject private var holder = ViewModelHolder()

    var body: some View {
        NavigationStack {
            Group {
                if let model = holder.model {
                    RecognizeScreen(model: model, context: context)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Erkennen")
        }
        .onAppear {
            holder.setUp(context: context, history: history, settings: settings)
        }
    }
}

private struct RecognizeScreen: View {
    @ObservedObject var model: RecognitionViewModel
    let context: AppContext
    @State private var showTextInput = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                RecordButton(model: model)
                    .padding(.top, 24)
                PhaseView(model: model, context: context)
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showTextInput = true
                } label: {
                    Label("Text eingeben", systemImage: "character.cursor.ibeam")
                }
                .disabled(model.isBusy)
            }
        }
        .sheet(isPresented: $showTextInput) {
            ManualInputView { text in
                Task { await model.recognize(text: text) }
            }
        }
    }
}

/// Hält das ViewModel, sobald Kontext und Umgebung verfügbar sind.
final class ViewModelHolder: ObservableObject {
    @Published private(set) var model: RecognitionViewModel?

    func setUp(context: AppContext, history: HistoryStore, settings: AppSettings) {
        guard model == nil else { return }
        model = RecognitionViewModel(capture: AudioCaptureService(), recognizer: context.recognizer,
                                     matcher: context.matcher, history: history, settings: settings)
    }
}

private struct RecordButton: View {
    @ObservedObject var model: RecognitionViewModel

    var body: some View {
        VStack(spacing: 12) {
            Button {
                Task { await model.toggleRecording() }
            } label: {
                ZStack {
                    Circle()
                        .fill(model.isRecording ? Color.red : Color.accentColor)
                        .frame(width: 120, height: 120)
                        .scaleEffect(model.isRecording ? 1 + CGFloat(model.level) * 0.25 : 1)
                        .animation(.easeOut(duration: 0.1), value: model.level)
                    Image(systemName: model.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .disabled(model.isProcessing)
            .accessibilityLabel(model.isRecording ? "Aufnahme beenden" : "Aufnahme starten")

            Text(model.isRecording
                 ? String(format: "Aufnahme läuft … %.0f s", model.elapsed)
                 : "Tippen und Rezitation abspielen oder rezitieren")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

private struct PhaseView: View {
    @ObservedObject var model: RecognitionViewModel
    let context: AppContext

    var body: some View {
        switch model.phase {
        case .idle, .recording:
            EmptyView()
        case .processing:
            ProgressView("Wird erkannt …")
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.circle")
                .foregroundStyle(.orange)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .finished(let recognition):
            MatchResultView(outcome: recognition.outcome, transcript: recognition.transcript, context: context)
        }
    }
}

private struct ManualInputView: View {
    let onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("z. B. قل هو الله أحد", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        // Rechts→links-Eingabe: dort ist .leading die rechte Seite
                        .multilineTextAlignment(.leading)
                        .environment(\.layoutDirection, .rightToLeft)
                } footer: {
                    Text("Zum Testen der Verssuche, solange die Spracherkennung (Phase 3) fehlt. Vokalzeichen sind nicht nötig.")
                }
            }
            .navigationTitle("Text eingeben")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Suchen") {
                        onSubmit(text)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
