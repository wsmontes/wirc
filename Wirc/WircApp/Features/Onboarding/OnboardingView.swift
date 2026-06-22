import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @State private var currentPage = 0

    var body: some View {
        TabView(selection: $currentPage) {
            // Page 1: Welcome
            VStack(spacing: DesignSystem.Spacing.xl) {
                Spacer()
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 64))
                    .foregroundStyle(DesignSystem.Colors.signal)
                Text("Welcome to Wirc")
                    .font(.largeTitle.bold())
                Text("All your content, one place.\nRSS, YouTube, Podcasts, Mastodon, and IRC \u{2014} together.")
                    .font(DesignSystem.Fonts.body())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DesignSystem.Colors.pencil)
                Spacer()
            }
            .tag(0)

            // Page 2: What to expect
            VStack(spacing: DesignSystem.Spacing.lg) {
                Spacer()
                HStack(spacing: DesignSystem.Spacing.xl) {
                    VStack { Image(systemName: "dot.radiowaves.left.and.right").font(.title); Text("Feeds").font(DesignSystem.Fonts.caption) }
                    VStack { Image(systemName: "bubble.left.and.bubble.right").font(.title); Text("Chat").font(DesignSystem.Fonts.caption) }
                    VStack { Image(systemName: "archivebox").font(.title); Text("Archive").font(DesignSystem.Fonts.caption) }
                }
                .foregroundStyle(DesignSystem.Colors.signal)
                Text("We've prepared 200+ trusted sources across tech, news, podcasts, and video.")
                    .font(DesignSystem.Fonts.body())
                    .multilineTextAlignment(.center)
                Text("You can customize everything later in Settings.")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(DesignSystem.Colors.pencil)
                Spacer()
                Button("Get Started") {
                    appState.onboardingCompleted = true
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.signal)
                .padding(.bottom, 48)
            }
            .tag(1)
        }
        .tabViewStyle(.page)
        .background(DesignSystem.Colors.page)
    }
}
