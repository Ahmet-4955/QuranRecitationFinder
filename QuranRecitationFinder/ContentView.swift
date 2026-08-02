import SwiftUI

struct ContentView: View {
    @StateObject private var recorder = AudioRecorder()
    @State private var statusMessage = "Bereit zur Erkennung"
    @State private var matchedVerse: QuranVerse?
    @State private var feedbackStatusMessage: String?
    @State private var durationText = "5"
    private let matcher = AudioMatchManager()

    var body: some View {
        VStack(spacing: 24) {
            Text("Quran Recitation Finder")
                .font(.title)
                .bold()

            Text(statusMessage)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Text(matcher.datasetInfo)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            HStack {
                TextField("Dauer in Sekunden", text: $durationText)
                    .keyboardType(.numberPad)
                    .disabled(recorder.isRecording)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)

                Text("Sek.")
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            if recorder.isRecording {
                VStack(spacing: 14) {
                    Text("Aufnahme läuft: \(recorder.remainingSeconds) s verbleibend")
                        .font(.subheadline)
                        .foregroundColor(.orange)

                    RecordingVisualizer(level: recorder.audioLevel)
                        .frame(height: 80)
                        .padding(.horizontal)
                }
                .padding(.horizontal)
            }

            if recorder.recordingState == .processing {
                VStack(spacing: 10) {
                    ProgressView("Vergleich läuft...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .scaleEffect(1.2, anchor: .center)
                        .padding(.top, 8)

                    Text("Die App vergleicht gerade die Aufnahme mit dem Quran-Dataset.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.horizontal)
            }

            Button(action: toggleRecording) {
                HStack {
                    Image(systemName: recorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 40))
                    Text(recorder.isRecording ? "Stopp" : "Start")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(recorder.isRecording ? Color.red : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding(.horizontal)

            Button(action: displaySampleDatasetVerse) {
                Text("Testdaten anzeigen")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Color(UIColor.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
            }
            .padding(.horizontal)

            if recorder.lastRecordingURL != nil {
                Button(action: recorder.playLastRecording) {
                    Text("Aufnahme wiedergeben")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Color(UIColor.systemBlue))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .disabled(recorder.isRecording)
            }

            if let matchedVerse {
                VStack(spacing: 10) {
                    Text("Ergebnis")
                        .font(.headline)

                    VStack(spacing: 6) {
                        Text(matchedVerse.displayName)
                            .font(.title3)
                            .bold()

                        if !matchedVerse.text.isEmpty {
                            Text(matchedVerse.text)
                                .font(.body)
                                .multilineTextAlignment(.center)
                                .padding(10)
                                .background(Color(UIColor.systemGray6))
                                .cornerRadius(10)
                        }

                        if let source = matchedVerse.source {
                            Text("Reciter: \(source)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        if let audioInfo = matchedVerse.audioSourceDescription {
                            Text(audioInfo)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }

                        if let feedbackLabel = FeedbackManager.shared.feedbackLabel(for: matchedVerse) {
                            Text(feedbackLabel)
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)

                    HStack(spacing: 14) {
                        Button(action: { submitFeedback(isCorrect: true) }) {
                            Text("Richtig")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(12)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }

                        Button(action: { submitFeedback(isCorrect: false) }) {
                            Text("Falsch")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(12)
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }

                    if let feedbackStatusMessage {
                        Text(feedbackStatusMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal)
            }

            Spacer()
        }
        .padding(.top, 50)
        .onChange(of: recorder.recordingState) { _, state in
            feedbackStatusMessage = nil
            switch state {
            case .idle:
                statusMessage = "Bereit zur Erkennung"
            case .recording:
                statusMessage = "Aufnahme läuft... sprich jetzt die Rezitation ein."
            case .processing:
                statusMessage = "Verarbeite Audio..."
            case .completed(let result):
                matchedVerse = result
                statusMessage = result != nil ? "Erkennung abgeschlossen" : "Keine Übereinstimmung gefunden"
            case .permissionDenied:
                statusMessage = "Mikrofonzugriff erforderlich."
            }
        }
        .alert(isPresented: $recorder.showPermissionAlert) {
            Alert(
                title: Text("Mikrofonberechtigung benötigt"),
                message: Text("Bitte erlaube der App den Zugriff auf das Mikrofon in den Einstellungen."),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func toggleRecording() {
        if recorder.isRecording {
            recorder.stopRecording()
        } else {
            matchedVerse = nil
            feedbackStatusMessage = nil
            statusMessage = "Bereit zur Erkennung"
            let seconds = Int(durationText) ?? 5
            recorder.startRecording(duration: max(seconds, 1))
        }
    }

    private func displaySampleDatasetVerse() {
        matchedVerse = matcher.sampleMatchResult()
        statusMessage = matchedVerse != nil ? "Testdaten aus dem Dataset geladen" : "Keine Testdaten verfügbar"
    }

    private func submitFeedback(isCorrect: Bool) {
        guard let verse = matchedVerse else { return }
        FeedbackManager.shared.recordFeedback(for: verse, isCorrect: isCorrect)
        feedbackStatusMessage = isCorrect ? "Danke. Dein positives Feedback hilft, die Trefferquote zu verbessern." : "Danke. Dein negatives Feedback wird berücksichtigt und das Modell wird angepasst."
    }
}

struct RecordingVisualizer: View {
    let level: Float
    private let barCount = 6

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(0..<barCount, id: \ .self) { index in
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: barHeight(for: index))
                    .opacity(barOpacity(for: index))
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color(UIColor.secondarySystemFill).opacity(0.3))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let base: CGFloat = 20
        let maxExtra: CGFloat = 50
        let variation = CGFloat(index) * 6
        let normalized = CGFloat(level) * (1.0 - CGFloat(index) * 0.08)
        return base + maxExtra * normalized + variation
    }

    private func barOpacity(for index: Int) -> Double {
        let threshold: Float = Float(index) * 0.13
        return level > threshold ? 1.0 : 0.35
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
