import SwiftUI

/// Ganze Sure lesen – springt zum erkannten Vers und hebt den Bereich hervor.
struct SurahReaderView: View {
    let surahNumber: Int
    var highlight: VerseRange? = nil
    let context: AppContext
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        let quran = context.library.text
        let surah = quran.surah(surahNumber)

        ScrollViewReader { proxy in
            List {
                if let surah {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(surah.arabicName).font(.title2)
                            Text(verbatim: "\(surah.number). \(surah.transliteratedName) · \(surah.englishName)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(String(format: NSLocalizedString("%1$@ verses · %2$@", comment: ""), String(surah.ayahCount),
                                        surah.revelation == .meccan ? NSLocalizedString("Meccan", comment: "") : NSLocalizedString("Medinan", comment: "")))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    ForEach(1...(surah?.ayahCount ?? 1), id: \.self) { ayah in
                        let verse = VerseID(surah: surahNumber, ayah: ayah)
                        VerseRow(verse: verse, context: context, language: settings.translationLanguage)
                            .listRowBackground(highlight?.contains(verse) == true ? Color.accentColor.opacity(0.12) : nil)
                            .id(verse)
                    }
                }
            }
            .listStyle(.plain)
            .onAppear {
                guard let start = highlight?.start else { return }
                // kurz warten, bis die Liste aufgebaut ist
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation { proxy.scrollTo(start, anchor: .top) }
                }
            }
        }
        .navigationTitle(surah?.transliteratedName ?? String(format: NSLocalizedString("Surah %@", comment: ""), String(surahNumber)))
        .navigationBarTitleDisplayMode(.inline)
    }
}
