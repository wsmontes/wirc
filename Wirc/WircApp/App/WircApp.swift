import SwiftUI
import BackgroundTasks

@main
struct WircApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

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
            .onAppear {
                registerBackgroundTasks()
                appState.scheduleNextRefresh()
                Task {
                    await appState.refreshAllFeeds()
                }
            }
        }
    }

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.wirc.feed-refresh",
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }

            Task {
                await appState.refreshAllFeeds()
                refreshTask.setTaskCompleted(success: true)
                appState.scheduleNextRefresh()
            }

            refreshTask.expirationHandler = {
                refreshTask.setTaskCompleted(success: false)
            }
        }
    }
}
