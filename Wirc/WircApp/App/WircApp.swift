import SwiftUI

@main
struct WircApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            TabView {
                StreamView()
                    .tabItem {
                        Label("Stream", systemImage: "waveform")
                    }

                LibraryView()
                    .tabItem {
                        Label("Library", systemImage: "archivebox")
                    }

                WorkshopView()
                    .tabItem {
                        Label("Workshop", systemImage: "hammer")
                    }
            }
            .tint(DesignSystem.Colors.signal)
            .environment(appState)
        }
    }
}
