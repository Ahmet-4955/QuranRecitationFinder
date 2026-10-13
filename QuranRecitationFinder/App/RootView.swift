import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        switch model.state {
        case .loading:
            VStack(spacing: 16) {
                ProgressView()
                Text("Korantext wird geladen …")
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("Daten fehlen", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
        case .ready(let context):
            TabView {
                RecognizeView(context: context)
                    .tabItem { Label("Erkennen", systemImage: "waveform") }
                HistoryView(context: context)
                    .tabItem { Label("Verlauf", systemImage: "clock") }
                SettingsView(context: context)
                    .tabItem { Label("Einstellungen", systemImage: "gearshape") }
            }
        }
    }
}
