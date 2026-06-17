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

            var completed = false

            Task {
                await appState.refreshAllFeeds()
                if !completed {
                    completed = true
                    refreshTask.setTaskCompleted(success: true)
                    appState.scheduleNextRefresh()
                }
            }

            refreshTask.expirationHandler = {
                if !completed {
                    completed = true
                    refreshTask.setTaskCompleted(success: false)
                }
            }
        }
    }
}
