import SwiftUI

/// Stream tab — posts from feeds (RSS, Mastodon, YouTube, Podcast, GitHub).
/// IRC messages are in the Messages tab.
struct StreamView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedSource: String = "All"

    /// Dynamic source filters — built from actual data.
    private var sourceFilters: [String] {
        var sources = Set<String>()
        for obj in appState.womObjects where obj.type.contains("wom:Post") {
            let network = obj.data["network"] ?? ""
            if !network.isEmpty { sources.insert(network.capitalized) }
        }
        // Fixed preferred order
        let order = ["Rss", "Mastodon", "Youtube", "Podcast", "Github"]
        var sorted = order.filter { sources.contains($0) }
        for s in sources.sorted() where !order.contains(s) {
            sorted.append(s)
        }
        return ["All"] + sorted
    }

    /// Posts timeline — capped at 200, reverse chronological.
    private var timeline: [WOMObject] {
        let posts = appState.womObjects.filter { $0.type.contains("wom:Post") }
        let filtered: [WOMObject]
        if selectedSource == "All" {
            filtered = posts
        } else {
            filtered = posts.filter { ($0.data["network"] ?? "").capitalized == selectedSource }
        }
        return Array(filtered.sorted { $0.createdAt > $1.createdAt }.prefix(200))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Dynamic source filter chips
            if sourceFilters.count > 1 {
                filterBar
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.sm)
            }

            if timeline.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(timeline) { object in
                            FeedCard(post: object)
                        }
                    }
                    .padding(.vertical, DesignSystem.Spacing.lg)
                }
            }
        }
        .background(DesignSystem.Colors.page)
        .refreshable {
            let newObjects = await appState.feed.refreshAllFeedsBatched(womStore: appState.store)
            appState.womObjects.append(contentsOf: newObjects)
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(sourceFilters, id: \.self) { source in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedSource = source
                        }
                    } label: {
                        Text(source)
                            .font(DesignSystem.Fonts.chipLabel)
                            .foregroundStyle(selectedSource == source ? .white : DesignSystem.Colors.ink)
                            .padding(.horizontal, DesignSystem.Spacing.md)
                            .padding(.vertical, DesignSystem.Spacing.sm)
                            .background(selectedSource == source
                                ? DesignSystem.Colors.forSource(source.lowercased())
                                : DesignSystem.Colors.border)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.chip))
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "No posts yet",
            systemImage: "waveform",
            description: Text("Add RSS feeds or Mastodon accounts in Workshop to start your stream.")
        )
    }
}
