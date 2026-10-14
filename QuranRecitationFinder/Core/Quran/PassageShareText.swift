import Foundation

/// Text zum Teilen eines Versbereichs: Arabisch, Übersetzung, Quellenangabe
/// (Pflichtangaben nach Tanzil- und QuranEnc-Bedingungen).
nonisolated enum PassageShareText {
    static let maxVerses = 20

    static func make(range: VerseRange, quran: QuranText, translation: Translation?) -> String {
        let verses = quran.verses(in: range)
        var lines: [String] = []
        if let surah = quran.surah(range.start.surah) {
            lines.append("\(surah.transliteratedName) (\(surah.arabicName)) · \(range)")
        } else {
            lines.append(range.description)
        }
        for verse in verses.prefix(maxVerses) {
            lines.append("")
            let marker = verses.count > 1 ? "(\(verse)) " : ""
            if let arabic = quran.displayText(verse) {
                lines.append(marker + arabic)
            }
            if let text = translation?.text(for: verse) {
                lines.append(text)
            }
        }
        if verses.count > maxVerses {
            lines.append("")
            lines.append(String(format: NSLocalizedString("… %@ more verses", comment: ""), String(verses.count - maxVerses)))
        }
        lines.append("")
        var source = NSLocalizedString("Quran text: Tanzil.net", comment: "")
        if let info = translation?.info {
            source += " · " + String(format: NSLocalizedString("Translation: %@", comment: ""), info.attribution)
        }
        lines.append("— " + source)
        return lines.joined(separator: "\n")
    }
}
