import SwiftUI

struct WorkshopView: View {
    @Environment(AppState.self) private var appState

    @State private var showAddServer = false
    @State private var showAddFeed = false
    @State private var showDebug = false

    // Governance defaults (stored in AppState)
    @State private var adsUse: String = WOMAdsUse.notAllowed.rawValue
    @State private var agentUse: String = "allowed"
    @State private var defaultSharing: String = WOMSharing.friendsOnly.rawValue
    @State private var retention: String = "forever"

    var body: some View {
        NavigationStack {
            List {
                // MARK: Transports
                transportsSection

                // MARK: Governance Defaults
                governanceSection

                // MARK: Data
                dataSection

                // MARK: About
                aboutSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(DesignSystem.Colors.page)
            .navigationTitle("Workshop")
            .sheet(isPresented: $showAddServer) {
                AddServerView { config in
                    appState.servers.append(config)
                }
            }
            .sheet(isPresented: $showAddFeed) {
                AddFeedView()
            }
            .sheet(isPresented: $showDebug) {
                DebugView()
            }
        }
    }

    // MARK: - Transports

    private var transportsSection: some View {
        Section {
            // Mastodon
            NavigationLink {
                MastodonTransportDetail()
            } label: {
                HStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "m.circle")
                        .foregroundStyle(DesignSystem.Colors.mastodon)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mastodon")
                            .font(.system(size: 15, weight: .medium))
                        Text("\(appState.mastodonAccounts.count) account\(appState.mastodonAccounts.count == 1 ? "" : "s")")
                            .font(DesignSystem.Fonts.caption())
                            .foregroundStyle(DesignSystem.Colors.pencil)
                    }
                }
            }

            // Feeds
            NavigationLink {
                FeedTransportDetail()
            } label: {
                HStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(DesignSystem.Colors.rss)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Feeds")
                            .font(.system(size: 15, weight: .medium))
                        Text("\(appState.feedStore.getAll().count) subscription\(appState.feedStore.getAll().count == 1 ? "" : "s")")
                            .font(DesignSystem.Fonts.caption())
                            .foregroundStyle(DesignSystem.Colors.pencil)
                    }
                }
            }

            // Add buttons
            HStack(spacing: DesignSystem.Spacing.md) {
                Button { showAddServer = true } label: {
                    Label("Add Server", systemImage: "plus")
                        .font(DesignSystem.Fonts.caption())
                }
                .buttonStyle(.bordered)
                .tint(DesignSystem.Colors.irc)

                Button { showAddFeed = true } label: {
                    Label("Add Feed", systemImage: "plus")
                        .font(DesignSystem.Fonts.caption())
                }
                .buttonStyle(.bordered)
                .tint(DesignSystem.Colors.rss)
            }
        } header: {
            Text("Transports".uppercased())
                .font(DesignSystem.Fonts.data(11))
                .foregroundStyle(DesignSystem.Colors.pencil)
        }
    }

    // MARK: - Governance Defaults

    private var governanceSection: some View {
        Section {
            HStack {
                Text("Ads use")
                Spacer()
                Text(adsUse)
                    .font(DesignSystem.Fonts.data(11))
                    .foregroundStyle(DesignSystem.Colors.pencil)
            }
            HStack {
                Text("Agent use")
                Spacer()
                Text(agentUse)
                    .font(DesignSystem.Fonts.data(11))
                    .foregroundStyle(DesignSystem.Colors.pencil)
            }
            HStack {
                Text("Default sharing")
                Spacer()
                Text(defaultSharing)
                    .font(DesignSystem.Fonts.data(11))
                    .foregroundStyle(DesignSystem.Colors.pencil)
            }
            HStack {
                Text("Retention")
                Spacer()
                Text(retention)
                    .font(DesignSystem.Fonts.data(11))
                    .foregroundStyle(DesignSystem.Colors.pencil)
            }
        } header: {
            Text("Governance Defaults".uppercased())
                .font(DesignSystem.Fonts.data(11))
                .foregroundStyle(DesignSystem.Colors.pencil)
        } footer: {
            Text("These defaults apply to new objects. Changing them does not retroactively modify existing objects.")
                .font(DesignSystem.Fonts.data(10))
                .foregroundStyle(DesignSystem.Colors.pencil)
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        Section {
            Button { exportLibrary() } label: {
                Label("Export Library...", systemImage: "square.and.arrow.up")
            }
            Button { /* file picker stub */ } label: {
                Label("Import WOM Bundle...", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Data".uppercased())
                .font(DesignSystem.Fonts.data(11))
                .foregroundStyle(DesignSystem.Colors.pencil)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack {
                Text("WOM")
                Spacer()
                Text("0.6")
                    .font(DesignSystem.Fonts.data(11))
                    .foregroundStyle(DesignSystem.Colors.pencil)
            }
            HStack {
                Text("Wirc")
                Spacer()
                Text("0.1")
                    .font(DesignSystem.Fonts.data(11))
                    .foregroundStyle(DesignSystem.Colors.pencil)
            }
            Button { showDebug = true } label: {
                Label("Debug", systemImage: "wrench.and.screwdriver")
                    .font(DesignSystem.Fonts.caption())
                    .foregroundStyle(DesignSystem.Colors.pencil)
            }
        } header: {
            Text("About".uppercased())
                .font(DesignSystem.Fonts.data(11))
                .foregroundStyle(DesignSystem.Colors.pencil)
        }
    }

    // MARK: - Helpers

    private func exportLibrary() {
        guard let data = try? JSONEncoder().encode(appState.womObjects),
              let json = String(data: data, encoding: .utf8) else { return }
        let activityVC = UIActivityViewController(
            activityItems: [json],
            applicationActivities: nil
        )
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = windowScene.windows.first?.rootViewController {
            root.present(activityVC, animated: true)
        }
    }
}

// MARK: - IRC Transport Detail

// MARK: - Mastodon Transport Detail (stub)

struct MastodonTransportDetail: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            if appState.mastodonAccounts.isEmpty {
                ContentUnavailableView("No Mastodon accounts", systemImage: "m.circle")
            }
            ForEach(appState.mastodonAccounts) { account in
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text(account.name)
                        .font(.system(size: 15, weight: .medium))
                    Text(account.instanceURL)
                        .font(DesignSystem.Fonts.data(11))
                        .foregroundStyle(DesignSystem.Colors.pencil)
                }
            }
        }
        .navigationTitle("Mastodon")
    }
}

// MARK: - Feed Transport Detail (stub)

struct FeedTransportDetail: View {
    @Environment(AppState.self) private var appState
    @State private var showAddFeed = false

    var body: some View {
        List {
            let feeds = appState.feedStore.getAll()
            if feeds.isEmpty {
                ContentUnavailableView("No feed subscriptions", systemImage: "dot.radiowaves.left.and.right")
            }
            ForEach(feeds) { sub in
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text(sub.title.isEmpty ? sub.feedURL : sub.title)
                        .font(.system(size: 15, weight: .medium))
                    Text(sub.feedURL)
                        .font(DesignSystem.Fonts.data(10))
                        .foregroundStyle(DesignSystem.Colors.pencil)
                        .lineLimit(1)
                    HStack(spacing: DesignSystem.Spacing.md) {
                        pill(sub.sourceType.rawValue.capitalized,
                             color: DesignSystem.Colors.forSource(sub.sourceType.rawValue))
                        if let last = sub.lastFetchedAt {
                            Text("Updated \(last, style: .relative)")
                                .font(.caption2)
                                .foregroundStyle(DesignSystem.Colors.pencil)
                        }
                        if sub.errorCount > 0 {
                            Text("\(sub.errorCount) errors")
                                .font(.caption2)
                                .foregroundStyle(DesignSystem.Colors.signal)
                        }
                    }
                }
            }
            .onDelete { indexSet in
                let feeds = appState.feedStore.getAll()
                for idx in indexSet {
                    appState.removeFeed(feeds[idx])
                }
            }

            Button { showAddFeed = true } label: {
                Label("Add Feed", systemImage: "plus")
            }
        }
        .navigationTitle("Feeds")
        .sheet(isPresented: $showAddFeed) {
            AddFeedView()
        }
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(color)
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.badge))
    }
}
