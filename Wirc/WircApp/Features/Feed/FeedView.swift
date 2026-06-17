import SwiftUI

struct FeedView: View {
    @Environment(AppState.self) private var appState

    private var posts: [WOMObject] {
        appState.womObjects
            .filter { $0.type.contains("wom:Post") }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let error = appState.feedError {
                    // Error state
                    ContentUnavailableView(
                        "Feed Error",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                    .overlay(alignment: .bottom) {
                        Button("Retry") {
                            for acct in appState.mastodonAccounts {
                                appState.refreshMastodonFeed(accountId: acct.id)
                            }
                        }
                        .buttonStyle(.bordered)
                        .padding(.bottom, 40)
                    }
                } else if appState.feedLoading && posts.isEmpty {
                    // Loading state
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading feed...").foregroundStyle(.secondary)
                    }
                } else if posts.isEmpty && !appState.mastodonAccounts.isEmpty {
                    // Empty but has accounts
                    ContentUnavailableView(
                        "Feed Empty",
                        systemImage: "newspaper",
                        description: Text("Your timeline is empty. Follow some people on Mastodon!")
                    )
                } else if posts.isEmpty {
                    // No accounts configured
                    ContentUnavailableView(
                        "No Mastodon Account",
                        systemImage: "newspaper",
                        description: Text("Add a Mastodon account in Settings to see your feed.")
                    )
                } else {
                    // Posts!
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if appState.feedLoading {
                                HStack { ProgressView(); Text("Refreshing...").font(.caption).foregroundStyle(.secondary) }
                            }
                            ForEach(posts) { post in
                                FeedCard(post: post)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .refreshable {
                        for acct in appState.mastodonAccounts {
                            appState.refreshMastodonFeed(accountId: acct.id)
                        }
                    }
                }
            }
            .navigationTitle("Feed")
        }
    }
}
