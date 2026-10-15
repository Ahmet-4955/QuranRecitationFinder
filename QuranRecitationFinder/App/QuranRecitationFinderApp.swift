import Combine
import SwiftUI

@main
struct QuranRecitationFinderApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.settings)
                .environmentObject(model.history)
                .task { await model.load() }
        }
    }
}
