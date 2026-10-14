import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        switch model.state {
        case .loading:
            VStack(spacing: 16) {
                ProgressView()
                Text("Loading Quran text …")
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("Data missing", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
        case .ready(let context):
            TabView {
                RecognizeView(context: context)
                    .tabItem { Label("Recognize", systemImage: "waveform") }
                HistoryView(context: context)
                    .tabItem { Label("History", systemImage: "clock") }
                SettingsView(context: context)
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
        }
    }
}
