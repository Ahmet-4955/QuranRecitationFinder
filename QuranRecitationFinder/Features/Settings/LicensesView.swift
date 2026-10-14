import SwiftUI

/// Pflichtangaben der Datenquellen (Tanzil, QuranEnc) und später der Modelle.
struct LicensesView: View {
    let context: AppContext

    var body: some View {
        List {
            Section {
                Text("Korantext: Tanzil Quran Text (Uthmani und Simple Clean), Copyright © Tanzil.net. Lizenz: Creative Commons Attribution 3.0. Der Text wird unverändert verwendet.")
                Link("tanzil.net", destination: URL(string: "https://tanzil.net")!)
            } header: {
                Text("Korantext")
            }

            Section {
                ForEach(context.library.translations.available) { info in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(info.title)
                        Text("Quelle: \(info.source) · Version \(info.version)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let url = URL(string: info.sourceURL) {
                            Link(info.sourceURL, destination: url)
                                .font(.caption)
                        }
                    }
                }
            } header: {
                Text("Übersetzungen")
            } footer: {
                Text("Die Übersetzungen werden unverändert von QuranEnc.com übernommen. Hinweise zu Übersetzungen bitte an QuranEnc.com melden.")
            }

            Section {
                Text("Spracherkennung: \(context.recognizer.displayName)")
                ForEach(context.recognizer.credits, id: \.self) { line in
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Spracherkennung")
            }
        }
        .navigationTitle("Quellen & Lizenzen")
    }
}
