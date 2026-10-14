import SwiftUI

/// Überschrift eines Versbereichs, z. B. "2. Al-Baqara · 2:255" oder "1. Al-Faatiha · 1:6–1:7".
enum PassageTitle {
    static func text(for range: VerseRange, quran: QuranText) -> String {
        let start = quran.surah(range.start.surah)
        var title = start.map { "\($0.number). \($0.transliteratedName)" } ?? String(format: NSLocalizedString("Surah %@", comment: ""), String(range.start.surah))
        if range.end.surah != range.start.surah, let end = quran.surah(range.end.surah) {
            title += " – \(end.number). \(end.transliteratedName)"
        }
        return "\(title) · \(range)"
    }
}

/// Arabischer Text, rechtsbündig und von rechts nach links.
struct ArabicText: View {
    let text: String
    let size: CGFloat

    init(_ text: String, size: CGFloat = 26) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(.system(size: size))
            .lineSpacing(size * 0.35)
            // App-Layout ist links→rechts: .trailing = rechtsbündig. Die Schreibrichtung
            // innerhalb der Zeile ergibt sich aus dem arabischen Text selbst.
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .textSelection(.enabled)
    }
}

/// Alle Verse eines Bereichs mit arabischem Text und Übersetzung.
struct VersePassageView: View {
    /// Längere Bereiche werden gekürzt angezeigt.
    static let maxVerses = 20

    let range: VerseRange
    let context: AppContext
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        let quran = context.library.text
        let verses = quran.verses(in: range)
        let info = context.library.translations.info(forLanguage: settings.translationLanguage.rawValue)

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(PassageTitle.text(for: range, quran: quran))
                    .font(.title3.weight(.semibold))
                if let surah = quran.surah(range.start.surah) {
                    Text(verbatim: "\(surah.arabicName) · \(surah.englishName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(verses.prefix(Self.maxVerses), id: \.self) { verse in
                VerseRow(verse: verse, context: context, language: settings.translationLanguage)
                Divider()
            }
            if verses.count > Self.maxVerses {
                Text(String(format: NSLocalizedString("… %@ more verses", comment: ""), String(verses.count - Self.maxVerses)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let info {
                Text(String(format: NSLocalizedString("Translation: %@", comment: ""), info.attribution))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                ShareLink(item: shareText(info: info)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                if showsReaderLink {
                    NavigationLink {
                        SurahReaderView(surahNumber: range.start.surah, highlight: range, context: context)
                    } label: {
                        Label("Read whole surah", systemImage: "book")
                    }
                }
            }
            .buttonStyle(.bordered)
            .font(.subheadline)
        }
    }

    /// In der Sure-Ansicht selbst nicht noch einmal anbieten.
    var showsReaderLink = true

    private func shareText(info: TranslationInfo?) -> String {
        let translation = info.flatMap { try? context.library.translations.translation(forKey: $0.key) }
        return PassageShareText.make(range: range, quran: context.library.text, translation: translation)
    }
}

/// Ein Vers: Nummer, arabischer Text, Übersetzung, Fußnoten.
struct VerseRow: View {
    let verse: VerseID
    let context: AppContext
    let language: TranslationLanguage
    @State private var showFootnotes = false

    var body: some View {
        let translationStore = context.library.translations
        let translation = translationStore.info(forLanguage: language.rawValue)
            .flatMap { try? translationStore.translation(forKey: $0.key) }

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text(verbatim: "\(verse.ayah)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 26, minHeight: 26)
                    .background(Circle().fill(Color.accentColor))
                ArabicText(context.library.text.displayText(verse) ?? "")
            }
            if let text = translation?.text(for: verse) {
                Text(text)
                    .font(.body)
                    .textSelection(.enabled)
            } else {
                Text("No translation available")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let notes = translation?.footnotes(for: verse) {
                DisclosureGroup("Footnotes", isExpanded: $showFootnotes) {
                    Text(notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .font(.footnote)
            }
        }
    }
}
