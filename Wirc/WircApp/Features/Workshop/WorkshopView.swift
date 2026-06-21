import SwiftUI

struct WorkshopView: View {
    @Environment(AppState.self) private var appState

    @State private var showAddFeed = false
    @State private var showDebug = false

    // Governance defaults (persisted in AppStorage)
    @AppStorage("wirc.governance.adsUse") private var adsUse: String = WOMAdsUse.notAllowed.rawValue
    @AppStorage("wirc.governance.agentUse") private var agentUse: String = "allowed"
    @AppStorage("wirc.governance.sharing") private var defaultSharing: String = WOMSharing.friendsOnly.rawValue
    @AppStorage("wirc.governance.retention") private var retention: String = "forever"

    var body: some View {
        List {
            transportsSection
            governanceSection
            dataSection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DesignSystem.Colors.page)
        .sheet(isPresented: $showAddFeed) {
            AddFeedView()
        }
        .sheet(isPresented: $showDebug) {
            DebugView()
        }
    }

    // MARK: - Transports

    private var transportsSection: some View {
        Section {
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
                        Text("\(appState.feed.subscriptionStore.getAll().count) subscription\(appState.feed.subscriptionStore.getAll().count == 1 ? "" : "s")")
                            .font(DesignSystem.Fonts.caption)
                            .foregroundStyle(DesignSystem.Colors.pencil)
                    }
                }
            }

            // Add buttons
            Button { showAddFeed = true } label: {
                Label("Add Feed", systemImage: "plus")
                    .font(DesignSystem.Fonts.caption)
            }
            .buttonStyle(.bordered)
            .tint(DesignSystem.Colors.rss)
        } header: {
            Text("Transports".uppercased())
                .font(DesignSystem.Fonts.data(11))
                .foregroundStyle(DesignSystem.Colors.pencil)
        }
    }

    // MARK: - Governance Defaults

    private var governanceSection: some View {
        Section {
            Picker("Ads use", selection: $adsUse) {
                Text("Not allowed").tag(WOMAdsUse.notAllowed.rawValue)
                Text("Allowed").tag(WOMAdsUse.allowed.rawValue)
            }
            Picker("Agent use", selection: $agentUse) {
                Text("Allowed").tag("allowed")
                Text("Restricted").tag("restricted")
                Text("Prohibited").tag("prohibited")
            }
            Picker("Default sharing", selection: $defaultSharing) {
                ForEach(WOMSharing.allCases, id: \.rawValue) { level in
                    Text(level.rawValue.capitalized).tag(level.rawValue)
                }
            }
            Picker("Retention", selection: $retention) {
                Text("Forever").tag("forever")
                Text("1 year").tag("1y")
                Text("90 days").tag("90d")
                Text("30 days").tag("30d")
            }
        } header: {
            Text("Governance Defaults".uppercased())
                .font(DesignSystem.Fonts.data(11))
                .foregroundStyle(DesignSystem.Colors.pencil)
        } footer: {
            Text("Applied to new objects created from this device. Existing objects are not modified.")
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
                    .font(DesignSystem.Fonts.caption)
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

// MARK: - Feed Transport Detail

struct FeedTransportDetail: View {
    @Environment(AppState.self) private var appState
    @State private var showAddFeed = false

    var body: some View {
        List {
            let feeds = appState.feed.subscriptionStore.getAll()
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
                let feeds = appState.feed.subscriptionStore.getAll()
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
