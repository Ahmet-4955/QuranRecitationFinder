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
                    ScoreHeader(title: "Erkannt", score: best.score, color: .green)
                    VersePassageView(range: best.range, context: context)
                    if matches.count > 1 {
                        AlternativesList(title: "Gleicher Wortlaut auch in:", matches: Array(matches.dropFirst()), context: context)
                    }
                }
            case .uncertain(let candidates):
                ScoreHeader(title: "Nicht sicher erkannt", score: candidates.first?.score, color: .orange)
                Text("Bitte länger oder deutlicher aufnehmen. Mögliche Stellen:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                AlternativesList(title: nil, matches: candidates, context: context)
            case .nothing:
                Label("Kein Koranvers erkannt", systemImage: "questionmark.circle")
                    .font(.headline)
                    .foregroundStyle(.orange)
            }

            if !transcript.isEmpty {
                DisclosureGroup("Erkannter Text") {
                    ArabicText(transcript, size: 18)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .font(.footnote)
            }
            if let seconds = transcriptionSeconds {
                Text(String(format: "Spracherkennung: %.1f s", seconds))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ScoreHeader: View {
    let title: String
    let score: Float?
    let color: Color

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(color)
            Spacer()
            if let score {
                Text("Übereinstimmung \(Int((score * 100).rounded())) %")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

private struct AlternativesList: View {
    let title: String?
    let matches: [VerseMatch]
    let context: AppContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
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
                        Text("\(Int((match.score * 100).rounded())) %")
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
