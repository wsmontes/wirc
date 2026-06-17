import SwiftUI

struct FeedView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedFilter: FeedFilter = .all

    enum FeedFilter: String, CaseIterable {
        case all = "All"
        case blogs = "Blogs"
        case videos = "Videos"
        case podcasts = "Podcasts"
    }

    private var allPosts: [WOMObject] {
        appState.womObjects
            .filter { $0.type.contains("wom:Post") }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var filteredPosts: [WOMObject] {
        switch selectedFilter {
        case .all:
            return allPosts
        case .blogs:
            return allPosts.filter { obj in
                !obj.type.contains("external.youtube.video") &&
                !obj.type.contains("external.podcast.episode")
            }
        case .videos:
            return allPosts.filter { $0.type.contains("external.youtube.video") }
        case .podcasts:
            return allPosts.filter { $0.type.contains("external.podcast.episode") }
        }
    }

    private var hasFeedsConfigured: Bool {
        !appState.feedStore.getAll().isEmpty ||
        !appState.mastodonAccounts.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if let error = appState.feedError {
                    ContentUnavailableView(
                        "Feed Error",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                    .overlay(alignment: .bottom) {
                        Button("Retry") {
                            Task {
                                for acct in appState.mastodonAccounts {
                                    appState.refreshMastodonFeed(accountId: acct.id)
                                }
                                await appState.refreshAllFeeds()
                            }
                        }
                        .buttonStyle(.bordered)
                        .padding(.bottom, 40)
                    }
                } else if appState.feedLoading && allPosts.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading feed...").foregroundStyle(.secondary)
                    }
                } else if allPosts.isEmpty && !hasFeedsConfigured {
                    ContentUnavailableView(
                        "No Feed Sources",
                        systemImage: "newspaper",
                        description: Text("Add RSS feeds or a Mastodon account in Settings to see your feed.")
                    )
                } else if allPosts.isEmpty {
                    ContentUnavailableView(
                        "Feed Empty",
                        systemImage: "newspaper",
                        description: Text("Your feed is empty. New posts will appear here.")
                    )
                } else {
                    VStack(spacing: 0) {
                        // Segmented filter
                        if !allPosts.isEmpty {
                            Picker("Filter", selection: $selectedFilter) {
                                ForEach(FeedFilter.allCases, id: \.self) { filter in
                                    Text(filter.rawValue).tag(filter)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }

                        ScrollView {
                            LazyVStack(spacing: 12) {
                                if appState.feedLoading {
                                    HStack {
                                        ProgressView()
                                        Text("Refreshing...")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                ForEach(filteredPosts) { post in
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
                            await appState.refreshAllFeeds()
                        }
                    }
                }
            }
            .navigationTitle("Feed")
        }
    }
}
