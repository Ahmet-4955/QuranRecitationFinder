import Combine
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
            .navigationTitle("Recognize")
        }
        .onAppear {
            holder.setUp(context: context, history: history, settings: settings)
        }
    }
}

private struct RecognizeScreen: View {
    @ObservedObject var model: RecognitionViewModel
    let context: AppContext
    @EnvironmentObject private var app: AppModel
    @State private var showTextInput = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                RecognizerStatusBanner(status: app.recognizerStatus)
                RecordButton(model: model)
                    .padding(.top, 8)
                PhaseView(model: model, context: context)
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showTextInput = true
                } label: {
                    Label("Enter text", systemImage: "character.cursor.ibeam")
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
                                     matcher: context.matcher, history: history, settings: settings,
                                     feedback: context.feedback)
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
            .accessibilityLabel(model.isRecording ? Text("Stop recording") : Text("Start recording"))

            Group {
                if model.isRecording {
                    Text(String(format: NSLocalizedString("Recording … %@ s", comment: ""), UIFormat.seconds(model.elapsed)))
                } else {
                    Text("Tap, then play or recite a recitation")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }
}

private struct PhaseView: View {
    @ObservedObject var model: RecognitionViewModel
    let context: AppContext

    static func stopNote(_ recognition: RecognitionViewModel.Recognition) -> String? {
        guard let reason = recognition.stopReason, let seconds = recognition.recordedSeconds else { return nil }
        let length = UIFormat.seconds(seconds)
        switch reason {
        case .manual: return String(format: NSLocalizedString("Recording: %@ s", comment: ""), length)
        case .maximum: return String(format: NSLocalizedString("Recording: %@ s (maximum length reached)", comment: ""), length)
        case .silence: return String(format: NSLocalizedString("Recording: %@ s (stopped automatically – silence)", comment: ""), length)
        case .early: return String(format: NSLocalizedString("Recognized early after %@ s of recording", comment: ""), length)
        }
    }

    var body: some View {
        switch model.phase {
        case .idle, .recording:
            EmptyView()
        case .processing:
            ProgressView("Recognizing …")
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.circle")
                .foregroundStyle(.orange)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .finished(let recognition):
            VStack(alignment: .leading, spacing: 20) {
                MatchResultView(outcome: recognition.outcome, transcript: recognition.transcript,
                                transcriptionSeconds: recognition.transcriptionSeconds, context: context)
                if let note = Self.stopNote(recognition) {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                FeedbackButtons(model: model)
            }
        }
    }
}

/// „Stimmt / Stimmt nicht“ – fließt ins Testprotokoll für die Kalibrierung (Phase 5).
private struct FeedbackButtons: View {
    @ObservedObject var model: RecognitionViewModel
    @State private var askCorrectVerse = false
    @State private var correctRef = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch model.verdict {
            case .unrated:
                Text("Is the result correct?")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 12) {
                    Button {
                        model.rate(.correct)
                    } label: {
                        Label("Correct", systemImage: "hand.thumbsup")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    Button {
                        askCorrectVerse = true
                    } label: {
                        Label("Not correct", systemImage: "hand.thumbsdown")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            case .correct:
                Label("Thanks – marked as correct.", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            case .wrong:
                Label("Thanks – marked as wrong.", systemImage: "xmark.circle")
                    .foregroundStyle(.red)
            }
        }
        .font(.subheadline)
        .alert("Which verse was it?", isPresented: $askCorrectVerse) {
            TextField("e.g. 2:255 (optional)", text: $correctRef)
                .keyboardType(.numbersAndPunctuation)
            Button("Save") { model.rate(.wrong, correctRef: correctRef) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Helps to fine-tune the recognition.")
        }
    }
}

/// Hinweis, solange das Sprachmodell lädt oder fehlt.
private struct RecognizerStatusBanner: View {
    let status: AppModel.RecognizerStatus

    var body: some View {
        switch status {
        case .ready:
            EmptyView()
        case .preparing:
            Label("Preparing the speech model – up to a minute on first launch.", systemImage: "hourglass")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .unavailable(let reason), .failed(let reason):
            Label(reason, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    TextField("e.g. قل هو الله أحد", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        // Rechts→links-Eingabe: dort ist .leading die rechte Seite
                        .multilineTextAlignment(.leading)
                        .environment(\.layoutDirection, .rightToLeft)
                } footer: {
                    Text("Tests the verse search without a recording. Vowel marks are not needed.")
                }
            }
            .navigationTitle("Enter text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Search") {
                        onSubmit(text)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
