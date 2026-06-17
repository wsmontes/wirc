import SwiftUI

@main
struct WircApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            TabView {
                ChatView()
                    .tabItem {
                        Label("Chat", systemImage: "bubble.left.and.bubble.right")
                    }

                FeedView()
                    .tabItem {
                        Label("Feed", systemImage: "house")
                    }

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
            }
            .environment(appState)
        }
    }
}
