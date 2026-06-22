import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showingAddServer = false
    @State private var showingAddMastodon = false
    @State private var showingAddFeed = false
    @State private var showingDebug = false

    // Governance defaults (persisted in AppStorage)
    @AppStorage("wirc.governance.adsUse") private var adsUse: String = WOMAdsUse.notAllowed.rawValue
    @AppStorage("wirc.governance.agentUse") private var agentUse: String = "allowed"
    @AppStorage("wirc.governance.sharing") private var defaultSharing: String = WOMSharing.friendsOnly.rawValue
    @AppStorage("wirc.governance.retention") private var retention: String = "forever"

    var body: some View {
        NavigationStack {
            List {
                // IRC Servers
                Section("IRC Servers") {
                    ForEach(appState.irc.servers) { server in
                        ServerRow(server: server)
                    }
                    .onDelete { indexSet in
                        for idx in indexSet {
                            let server = appState.irc.servers[idx]
                            appState.irc.disconnect(from: server.id)
                        }
                        appState.irc.servers.remove(atOffsets: indexSet)
                    }
                    Button { showingAddServer = true } label: {
                        Label("Add IRC Server", systemImage: "plus")
                    }
                }

                // Mastodon Accounts
                Section("Mastodon") {
                    ForEach(appState.mastodonAccounts) { acct in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(acct.name).font(DesignSystem.Fonts.body())
                                Text(acct.instanceURL).font(DesignSystem.Fonts.caption).foregroundStyle(DesignSystem.Colors.pencil)
                            }
                            Spacer()
                            Button {
                                appState.refreshMastodonFeed(accountId: acct.id)
                            } label: {
                                Image(systemName: "arrow.clockwise").font(DesignSystem.Fonts.caption)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for idx in indexSet {
                            appState.removeMastodonAccount(id: appState.mastodonAccounts[idx].id)
                        }
                    }
                    Button { showingAddMastodon = true } label: {
                        Label("Add Mastodon Account", systemImage: "plus")
                    }
                }

                // RSS/Atom Feeds
                Section("Feeds") {
                    if appState.feed.subscriptionStore.getAll().isEmpty {
                        Text("No feeds subscribed")
                            .font(DesignSystem.Fonts.body())
                            .foregroundStyle(DesignSystem.Colors.pencil)
                    } else {
                        ForEach(appState.feed.subscriptionStore.getAll()) { sub in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sub.title)
                                        .font(DesignSystem.Fonts.body())
                                    HStack(spacing: 4) {
                                        Image(systemName: sourceTypeIcon(sub.sourceType))
                                            .font(DesignSystem.Fonts.data(11))
                                        Text(sub.sourceType.rawValue.capitalized)
                                            .font(DesignSystem.Fonts.caption)
                                        if let fetched = sub.lastFetchedAt {
                                            Text("· fetched \(fetched, style: .relative) ago")
                                                .font(DesignSystem.Fonts.data(11))
                                        }
                                    }
                                    .foregroundStyle(DesignSystem.Colors.pencil)
                                    if !sub.tags.isEmpty {
                                        Text(sub.tags.joined(separator: ", "))
                                            .font(DesignSystem.Fonts.data(11))
                                            .foregroundStyle(DesignSystem.Colors.signal)
                                    }
                                    if sub.errorCount > 0 {
                                        Text("\(sub.errorCount) errors")
                                            .font(DesignSystem.Fonts.data(11))
                                            .foregroundStyle(DesignSystem.Colors.signal)
                                    }
                                }
                                Spacer()
                                Button {
                                    Task { await appState.refreshAllFeeds() }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(DesignSystem.Fonts.caption)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            let allSubs = appState.feed.subscriptionStore.getAll()
                            for idx in indexSet {
                                let sub = allSubs[idx]
                                appState.removeFeed(sub)
                            }
                        }
                    }
                    Button { showingAddFeed = true } label: {
                        Label("Add Feed", systemImage: "plus")
                    }
                    Button {
                        // OPML import via AddFeedView
                        showingAddFeed = true
                    } label: {
                        Label("Import OPML", systemImage: "doc.text")
                    }
                }

                // Governance Defaults
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
                    Text("Governance Defaults")
                } footer: {
                    Text("Applied to new objects created from this device. Existing objects are not modified.")
                        .font(DesignSystem.Fonts.data(10))
                        .foregroundStyle(DesignSystem.Colors.pencil)
                }

                // Data
                Section {
                    Button { exportLibrary() } label: {
                        Label("Export Library...", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Data")
                }

                // About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("0.1 (WOM 0.7)")
                            .foregroundStyle(DesignSystem.Colors.pencil)
                    }
                    .onLongPressGesture { showingDebug = true }
                } header: {
                    Text("About")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(DesignSystem.Colors.page)
            .navigationTitle("Settings")
            .sheet(isPresented: $showingAddServer) {
                AddServerView { config in appState.irc.servers.append(config) }
            }
            .sheet(isPresented: $showingAddMastodon) {
                AddMastodonView { name, url, token in
                    appState.addMastodonAccount(name: name, instanceURL: url, token: token)
                }
            }
            .sheet(isPresented: $showingAddFeed) {
                AddFeedView()
            }
            .sheet(isPresented: $showingDebug) {
                NavigationStack {
                    DebugView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { showingDebug = false }
                            }
                        }
                }
            }
        }
    }

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

    private func sourceTypeIcon(_ type: FeedSourceType) -> String {
        switch type {
        case .rss, .atom: return "dot.radiowaves.left.and.right"
        case .youtube: return "play.rectangle.fill"
        case .github: return "tag.fill"
        case .podcast: return "waveform"
        }
    }
}

struct AddMastodonView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (String, String, String) -> Void

    @State private var name = ""
    @State private var instanceURL = "https://"
    @State private var token = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. My Mastodon)", text: $name)
                    TextField("Instance URL (e.g. https://mastodon.social)", text: $instanceURL)
                        .autocapitalization(.none).autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Section {
                    TextField("Access Token", text: $token)
                        .autocapitalization(.none).autocorrectionDisabled()
                } footer: {
                    Text("Get your access token from Preferences → Development → New Application on your Mastodon instance.")
                }
            }
            .navigationTitle("Add Mastodon").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name, instanceURL, token)
                        dismiss()
                    }.disabled(name.isEmpty || instanceURL.isEmpty || token.isEmpty)
                }
            }
        }
    }
}

struct ServerRow: View {
    @Environment(AppState.self) private var appState
    let server: IRCConnectionConfig

    private var status: IRCManager.ConnectionStatus {
        appState.irc.connectionStates[server.id] ?? .disconnected
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(server.name.isEmpty ? server.host : server.name)
                    .font(DesignSystem.Fonts.headline())
                Text("\(server.host):\(server.port) as \(server.nickname)")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(DesignSystem.Colors.pencil)
            }

            Spacer()

            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            Button(action: toggleConnection) {
                Text(status == .online ? "Disconnect" : "Connect")
                    .font(DesignSystem.Fonts.caption)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch status {
        case .disconnected: return DesignSystem.Colors.pencil
        case .connecting: return DesignSystem.Colors.signal
        case .online: return DesignSystem.Colors.github
        }
    }

    private func toggleConnection() {
        switch status {
        case .disconnected:
            appState.irc.connect(to: server.id)
        case .connecting, .online:
            appState.irc.disconnect(from: server.id)
        }
    }
}
