import SwiftUI

/// Stream tab — posts from feeds (RSS, Mastodon, YouTube, Podcast, GitHub).
/// IRC messages are in the Messages tab.
struct StreamView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedSource: String = "All"
    @State private var sourceFilters: [String] = ["All"]
    @State private var timeline: [WOMObject] = []
    @State private var refreshTask: Task<Void, Never>?
    @State private var isInitialLoad = true

    /// Recompute filters & timeline once when underlying data changes (not on every body eval).
    private func refreshTimeline() {
        let posts = appState.feedObjects

        // Source filters from actual data
        var sources = Set<String>()
        for obj in posts {
            let network = obj.data["network"] ?? ""
            if !network.isEmpty { sources.insert(networkDisplayName(network)) }
        }
        let order = ["RSS", "Mastodon", "YouTube", "Podcast", "GitHub"]
        var sorted = order.filter { sources.contains($0) }
        for s in sources.sorted() where !order.contains(s) {
            sorted.append(s)
        }
        sourceFilters = ["All"] + sorted

        // Timeline — chronological, newest first. Source filter chips provide
        // per-type filtering when the user wants to focus on one content type.
        let filtered: [WOMObject]
        if selectedSource == "All" {
            filtered = posts
        } else {
            filtered = posts.filter { ($0.data["network"] ?? "").capitalized == selectedSource }
        }
        timeline = Array(filtered.prefix(200))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Status bar — visible during refresh, after summary, on error, or when offline
            if appState.feed.isRefreshing || appState.feed.refreshSummary != nil || appState.feed.feedError != nil || !appState.feed.isOnline {
                statusBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // New posts indicator — tap to dismiss
            if !appState.feed.isRefreshing && appState.feed.newPostCount > 0 && !timeline.isEmpty {
                Button {
                    appState.feed.newPostCount = 0
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                        Text("\(appState.feed.newPostCount) new posts")
                    }
                    .font(DesignSystem.Fonts.data(11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, 6)
                    .background(DesignSystem.Colors.signal)
                    .clipShape(Capsule())
                }
                .padding(.top, DesignSystem.Spacing.xs)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

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
        .onAppear {
            refreshTimeline()
            isInitialLoad = false
        }
        .onChange(of: appState.womObjects.count) { _, _ in
            // If refreshing, rebuild fully (batches are done). Otherwise debounce.
            refreshTask?.cancel()
            refreshTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                refreshTimeline()
            }
        }
        .onChange(of: appState.feed.isRefreshing) { _, refreshing in
            if !refreshing {
                isInitialLoad = false
                refreshTimeline() // Full rebuild when refresh completes
            }
        }
        .onChange(of: selectedSource) { _, _ in refreshTimeline() }
        .refreshable {
            // onIncrementalBatch handles per-batch appends; just kick off the refresh
            _ = await appState.feed.refreshAllFeedsBatched(womStore: appState.store)
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        let p = appState.feed.refreshProgress
        let fraction = p.total > 0 ? Double(p.completed) / Double(p.total) : 0
        let isComplete = !appState.feed.isRefreshing && appState.feed.refreshSummary != nil
        let hasError = appState.feed.feedError != nil
        let isOffline = !appState.feed.isOnline

        return VStack(spacing: DesignSystem.Spacing.xs) {
            // Progress track (hidden for completion, error, or offline)
            if !isComplete && !hasError && !isOffline {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DesignSystem.Colors.border)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(hasError ? Color.red : DesignSystem.Colors.signal)
                                .frame(width: max(4, geo.size.width * fraction))
                                .animation(.easeInOut(duration: 0.3), value: fraction)
                        }
                }
                .frame(height: 3)
                .padding(.horizontal, DesignSystem.Spacing.lg)
            }

            // Label
            HStack(spacing: DesignSystem.Spacing.xs) {
                if hasError || isOffline {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.Colors.signal)
                    if let err = appState.feed.feedError {
                        Text(err)
                            .font(DesignSystem.Fonts.provenanceDetail)
                            .lineLimit(2)
                    } else if isOffline {
                        Text("No internet connection")
                            .font(DesignSystem.Fonts.provenanceDetail)
                    }
                    Spacer()
                    if !isOffline {
                        Button("Dismiss") { appState.feed.feedError = nil }
                            .font(DesignSystem.Fonts.data(11))
                            .foregroundStyle(DesignSystem.Colors.signal)
                    }
                } else if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.Colors.github)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10))
                }
                if isComplete, let summary = appState.feed.refreshSummary {
                    Text(summary)
                        .font(DesignSystem.Fonts.provenanceDetail)
                } else if !hasError {
                    Text("\(p.completed)/\(p.total) sources")
                        .font(DesignSystem.Fonts.provenanceDetail)
                    Spacer()
                    Text("\(timeline.count) posts")
                        .font(DesignSystem.Fonts.provenanceDetail)
                        .foregroundStyle(DesignSystem.Colors.pencil)
                }
            }
            .foregroundStyle(DesignSystem.Colors.pencil)
            .padding(.horizontal, DesignSystem.Spacing.lg)
        }
        .padding(.top, DesignSystem.Spacing.xs)
        .padding(.bottom, DesignSystem.Spacing.xs)
        .background(hasError || isOffline ? DesignSystem.Colors.signal.opacity(0.08) : DesignSystem.Colors.surface.opacity(0.8))
        .animation(.easeInOut(duration: 0.3), value: isComplete)
        .animation(.easeInOut(duration: 0.3), value: hasError)
        .animation(.easeInOut(duration: 0.3), value: isOffline)
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

    // MARK: - Interleaving

    /// Pure round-robin by source: one card per provider per round, newest-first
    /// within each source. After interleaving, applies a diversity pass that
    /// swaps out consecutive same-type cards when a suitable alternative exists.
    ///
    /// Result: RSS → Mastodon → YouTube → Podcast → GitHub → RSS → Mastodon → …
    /// (never two of the same source in a row while enough variety remains).
    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        if appState.feed.isRefreshing || isInitialLoad {
            VStack(spacing: DesignSystem.Spacing.lg) {
                Spacer()
                ProgressView()
                    .scaleEffect(1.2)
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Text("Gathering your stream…")
                        .font(DesignSystem.Fonts.headline())
                        .foregroundStyle(DesignSystem.Colors.ink)
                    Text("Fetching the latest from \(appState.feed.subscriptionCount) sources")
                        .font(DesignSystem.Fonts.provenanceDetail)
                        .foregroundStyle(DesignSystem.Colors.pencil)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if appState.feed.subscriptionCount == 0 {
            ContentUnavailableView(
                "No sources yet",
                systemImage: "antenna.radiowaves.left.and.right",
                description: Text("Add RSS feeds or Mastodon accounts in Workshop to start your stream.")
            )
        } else {
            ContentUnavailableView(
                "No posts yet",
                systemImage: "waveform",
                description: Text("Pull to refresh or check back later.")
            )
        }
    }

    // MARK: - Helpers

    private func networkDisplayName(_ network: String) -> String {
        switch network.lowercased() {
        case "irc": return "IRC"
        case "mastodon": return "Mastodon"
        case "rss": return "RSS"
        case "github": return "GitHub"
        case "youtube": return "YouTube"
        case "podcast": return "Podcast"
        default: return network.capitalized
        }
    }
}
