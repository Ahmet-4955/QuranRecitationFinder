import Foundation

/// Reduziert arabischen Text auf ein vergleichbares Grundgerüst
/// (ohne Vokalzeichen, einheitliche Alif-/Ya-/Hamza-Formen).
///
/// Muss identisch zu `normalize()` in Tools/phase0/quran_corpus.py arbeiten,
/// damit die Testergebnisse aus Phase 0 auf die App übertragbar sind.
nonisolated enum ArabicNormalizer {
    /// Zeichen, die komplett entfernt werden.
    private static func isRemoved(_ v: UInt32) -> Bool {
        switch v {
        case 0x0610...0x061A,  // Ehrenzeichen / kleine Zeichen
             0x064B...0x065F,  // Harakat, Tanwin, Shadda, Sukun
             0x0670,  // hochgestelltes Alif
             0x06D6...0x06ED,  // Koran-Annotationszeichen
             0x0640,  // Tatweel
             0x08D3...0x08FF,  // erweiterte Koranzeichen
             0x0621:  // freistehende Hamza
            return true
        default:
            return false
        }
    }

    private static let replacements: [UInt32: UInt32] = [
        0x0671: 0x0627,  // Alif Wasla -> Alif
        0x0623: 0x0627,  // Alif mit Hamza oben
        0x0625: 0x0627,  // Alif mit Hamza unten
        0x0622: 0x0627,  // Alif Madda
        0x0672: 0x0627,
        0x0673: 0x0627,
        0x0649: 0x064A,  // Alif Maqsura -> Ya
        0x0629: 0x0647,  // Ta Marbuta -> Ha
        0x0624: 0x0648,  // Waw mit Hamza -> Waw
        0x0626: 0x064A,  // Ya mit Hamza -> Ya
        0x06CC: 0x064A,  // Farsi Ya
        0x06A9: 0x0643,  // Farsi Kaf
    ]

    static func normalize(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let v = replacements[scalar.value] ?? scalar.value
            if isRemoved(v) { continue }
            if (0x0622...0x064A).contains(v) {
                scalars.append(Unicode.Scalar(v)!)
            } else {
                scalars.append(" ")  // Leerzeichen, Satzzeichen, lateinische Zeichen, Ziffern
            }
        }
        return String(scalars).split(separator: " ").joined(separator: " ")
    }

    static func words(_ text: String) -> [String] {
        normalize(text).split(separator: " ").map(String.init)
    }
}
