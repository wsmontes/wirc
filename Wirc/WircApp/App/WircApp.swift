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

                IRCChatView()
                    .tabItem {
                        Label("Messages", systemImage: "bubble.left.and.bubble.right")
                    }
                    .badge(appState.irc.channelManager.totalUnread)

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
