import SwiftUI

@main
struct WircApp: App {
    @State private var appState = AppState()
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                TabView {
                    StreamView()
                        .tabItem { Label("Stream", systemImage: "waveform") }

                    IRCChatView()
                        .tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right") }
                        .badge(appState.irc.channelManager.totalUnread)

                    LibraryView()
                        .tabItem { Label("Library", systemImage: "archivebox") }

                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                }
                .tint(DesignSystem.Colors.signal)
                .environment(appState)
                .onOpenURL { url in appState.handleOAuthCallback(url: url) }
                .fullScreenCover(isPresented: Binding(
                    get: { !appState.onboardingCompleted },
                    set: { appState.onboardingCompleted = !$0 }
                )) {
                    OnboardingView().environment(appState)
                }
                .opacity(showSplash ? 0 : 1)

                // Splash screen — shown while store loads
                if showSplash {
                    VStack(spacing: DesignSystem.Spacing.lg) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 48))
                            .foregroundStyle(DesignSystem.Colors.signal)
                        Text("Wirc")
                            .font(.largeTitle.bold())
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DesignSystem.Colors.page)
                    .transition(.opacity)
                }
            }
            .onAppear {
                Task {
                    // Wait for store to be ready, then fade splash
                    while !appState.store.isReady { try? await Task.sleep(for: .milliseconds(50)) }
                    withAnimation(.easeOut(duration: 0.3)) { showSplash = false }
                }
            }
        }
    }
}
