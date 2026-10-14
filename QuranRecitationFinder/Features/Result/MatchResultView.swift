import SwiftUI

/// Zeigt das Ergebnis einer Erkennung: erkannt / unsicher / nichts.
struct MatchResultView: View {
    let outcome: MatchOutcome
    let transcript: String
    var transcriptionSeconds: Double? = nil
    let context: AppContext

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch outcome {
            case .recognized(let matches):
                if let best = matches.first {
                    ScoreHeader(title: Text("Recognized"), score: best.score, color: .green)
                    VersePassageView(range: best.range, context: context)
                    if matches.count > 1 {
                        AlternativesList(title: Text("Same wording also in:"), matches: Array(matches.dropFirst()), context: context)
                    }
                }
            case .uncertain(let candidates):
                ScoreHeader(title: Text("Not recognized with certainty"), score: candidates.first?.score, color: .orange)
                Text("Please record longer or more clearly. Possible passages:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                AlternativesList(title: nil, matches: candidates, context: context)
            case .nothing:
                Label("No Quran verse recognized", systemImage: "questionmark.circle")
                    .font(.headline)
                    .foregroundStyle(.orange)
            }

            if !transcript.isEmpty {
                DisclosureGroup("Recognized text") {
                    ArabicText(transcript, size: 18)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .font(.footnote)
            }
            if let seconds = transcriptionSeconds {
                Text(String(format: NSLocalizedString("Speech recognition: %@ s", comment: ""), UIFormat.seconds(seconds, decimals: 1)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ScoreHeader: View {
    let title: Text
    let score: Float?
    let color: Color

    var body: some View {
        HStack {
            title
                .font(.headline)
                .foregroundStyle(color)
            Spacer()
            if let score {
                Text(String(format: NSLocalizedString("Match: %@", comment: ""), UIFormat.percent(score)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

private struct AlternativesList: View {
    let title: Text?
    let matches: [VerseMatch]
    let context: AppContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                title
                    .font(.subheadline.weight(.semibold))
            }
            ForEach(matches, id: \.self) { match in
                NavigationLink {
                    ScrollView {
                        VersePassageView(range: match.range, context: context).padding()
                    }
                    .navigationTitle(match.range.description)
                } label: {
                    HStack {
                        Text(PassageTitle.text(for: match.range, quran: context.library.text))
                        Spacer()
                        Text(UIFormat.percent(match.score))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .font(.subheadline)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
