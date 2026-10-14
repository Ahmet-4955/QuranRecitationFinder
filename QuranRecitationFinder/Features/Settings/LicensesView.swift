import SwiftUI

/// Pflichtangaben der Datenquellen (Tanzil, QuranEnc) und später der Modelle.
struct LicensesView: View {
    let context: AppContext

    var body: some View {
        List {
            Section {
                Text("Quran text: Tanzil Quran Text (Uthmani and Simple Clean), copyright © Tanzil.net. License: Creative Commons Attribution 3.0. The text is used unchanged.")
                Link(destination: URL(string: "https://tanzil.net")!) { Text(verbatim: "tanzil.net") }
            } header: {
                Text("Quran text")
            }

            Section {
                ForEach(context.library.translations.available) { info in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(info.title)
                        Text(String(format: NSLocalizedString("Source: %1$@ · version %2$@", comment: ""), info.source, info.version))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let url = URL(string: info.sourceURL) {
                            Link(info.sourceURL, destination: url)
                                .font(.caption)
                        }
                    }
                }
            } header: {
                Text("Translations")
            } footer: {
                Text("The translations are taken unchanged from QuranEnc.com. Please report remarks on translations to QuranEnc.com.")
            }

            Section {
                Text(String(format: NSLocalizedString("Speech recognition: %@", comment: ""), context.recognizer.displayName))
                ForEach(context.recognizer.credits, id: \.self) { line in
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Speech recognition")
            }
        }
        .navigationTitle("Sources & licenses")
    }
}
