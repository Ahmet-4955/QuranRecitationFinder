import Foundation

/// Liest die Tanzil-XML-Dateien (Korantext und Metadaten).
nonisolated enum TanzilParser {
    nonisolated enum ParseError: LocalizedError {
        case unreadable(URL, Error?)
        case incomplete(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let url, let error):
                return "Tanzil-Datei nicht lesbar: \(url.lastPathComponent) \(error?.localizedDescription ?? "")"
            case .incomplete(let detail):
                return "Tanzil-Daten unvollständig: \(detail)"
            }
        }
    }

    /// Korantext (quran-uthmani.xml / quran-simple-clean.xml): Verse je Sure.
    static func parseText(at url: URL) throws -> [[String]] {
        let delegate = TextDelegate()
        try run(delegate, url: url)
        return delegate.surahs
    }

    /// Metadaten (quran-data.xml): Surennamen und Versanzahl.
    static func parseMetadata(at url: URL) throws -> [SurahInfo] {
        let delegate = MetadataDelegate()
        try run(delegate, url: url)
        return delegate.surahs
    }

    private static func run(_ delegate: any XMLParserDelegate, url: URL) throws {
        guard let parser = XMLParser(contentsOf: url) else {
            throw ParseError.unreadable(url, nil)
        }
        parser.delegate = delegate
        guard parser.parse() else {
            throw ParseError.unreadable(url, parser.parserError)
        }
    }

    private nonisolated final class TextDelegate: NSObject, XMLParserDelegate {
        var surahs: [[String]] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes: [String: String] = [:]) {
            switch elementName {
            case "sura":
                surahs.append([])
            case "aya":
                guard !surahs.isEmpty else { return }
                surahs[surahs.count - 1].append(attributes["text"] ?? "")
            default:
                break
            }
        }
    }

    private nonisolated final class MetadataDelegate: NSObject, XMLParserDelegate {
        var surahs: [SurahInfo] = []
        private var inSuras = false

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes: [String: String] = [:]) {
            if elementName == "suras" {
                inSuras = true
            } else if elementName == "sura", inSuras,
                      let index = attributes["index"].flatMap(Int.init),
                      let ayahs = attributes["ayas"].flatMap(Int.init) {
                surahs.append(
                    SurahInfo(
                        number: index,
                        ayahCount: ayahs,
                        arabicName: attributes["name"] ?? "",
                        transliteratedName: attributes["tname"] ?? "",
                        englishName: attributes["ename"] ?? "",
                        revelation: attributes["type"] == "Medinan" ? .medinan : .meccan
                    )
                )
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            if elementName == "suras" { inSuras = false }
        }
    }
}
