import SwiftUI

struct HistoryView: View {
    let context: AppContext
    @EnvironmentObject private var history: HistoryStore
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Group {
                if history.entries.isEmpty {
                    ContentUnavailableView("Noch keine Erkennungen", systemImage: "clock",
                                           description: Text("Erkannte Verse erscheinen hier."))
                } else {
                    List {
                        ForEach(history.entries) { entry in
                            NavigationLink {
                                HistoryDetailView(entry: entry, context: context)
                            } label: {
                                HistoryRow(entry: entry, quran: context.library.text)
                            }
                        }
                        .onDelete(perform: history.remove)
                    }
                }
            }
            .navigationTitle("Verlauf")
            .toolbar {
                if !history.entries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Leeren", role: .destructive) { confirmClear = true }
                    }
                }
            }
            .confirmationDialog("Gesamten Verlauf löschen?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Verlauf löschen", role: .destructive) { history.removeAll() }
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let quran: QuranText

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(PassageTitle.text(for: entry.range, quran: quran))
                .font(.body)
            HStack {
                Text(entry.date, format: .dateTime.day().month().year().hour().minute())
                Spacer()
                Text("\(Int((entry.score * 100).rounded())) %")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct HistoryDetailView: View {
    let entry: HistoryEntry
    let context: AppContext

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VersePassageView(range: entry.range, context: context)
                if !entry.alternatives.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Gleicher Wortlaut auch in:")
                            .font(.subheadline.weight(.semibold))
                        ForEach(entry.alternatives, id: \.self) { range in
                            Text(PassageTitle.text(for: range, quran: context.library.text))
                                .font(.subheadline)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Erkannter Text")
                        .font(.footnote.weight(.semibold))
                    ArabicText(entry.transcript, size: 18)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(entry.range.description)
        .navigationBarTitleDisplayMode(.inline)
    }
}
