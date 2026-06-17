import SwiftUI

struct StreamView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedFilter: StreamFilter = .all
    @State private var showingChannelPicker = false

    enum StreamFilter: String, CaseIterable {
        case all = "All"
        case messages = "Messages"
        case posts = "Posts"
        case media = "Media"
    }

    /// Capped timeline — last 200 objects, reverse chronological.
    private let maxTimelineItems = 200

    private var timeline: [WOMObject] {
        let objects = appState.womObjects
        let filtered: [WOMObject]
        switch selectedFilter {
        case .all:
            filtered = objects
        case .messages:
            filtered = objects.filter { $0.type.contains("wom:Message") }
        case .posts:
            filtered = objects.filter { $0.type.contains("wom:Post") }
        case .media:
            filtered = objects.filter { obj in
                obj.type.contains("external.youtube.video") ||
                obj.type.contains("external.podcast.episode") ||
                !obj.attachments.isEmpty
            }
        }
        return Array(filtered.sorted { $0.createdAt > $1.createdAt }.prefix(maxTimelineItems))
    }

    /// Whether any IRC server is currently online.
    private var hasOnlineServer: Bool {
        appState.connectionStates.values.contains(.online)
    }

    /// Whether any servers are configured.
    private var hasServersConfigured: Bool {
        !appState.servers.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Connection status bar
            if !hasOnlineServer && hasServersConfigured {
                connectionStatusBar
            }

            // Filter chips
            filterBar
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.vertical, DesignSystem.Spacing.sm)

            // Timeline
            if timeline.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(timeline) { object in
                            if object.type.contains("wom:SystemEvent") {
                                SystemEventPill(object: object)
                                    .padding(.vertical, 2)
                            } else if object.type.contains("wom:Message") && !object.type.contains("wom:SystemEvent") {
                                MessageCard(object: object, onTapChannel: { showingChannelPicker = true })
                            } else {
                                FeedCard(post: object)
                            }
                        }
                    }
                    .padding(.vertical, DesignSystem.Spacing.lg)
                }
            }
        }
        .background(DesignSystem.Colors.page)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingChannelPicker = true } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
            }
        }
        .sheet(isPresented: $showingChannelPicker) {
            ChannelFilterView()
        }
    }

    // MARK: - Connection Status Bar

    private var connectionStatusBar: some View {
        Button {
            showingChannelPicker = true
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                Text("Disconnected")
                    .font(DesignSystem.Fonts.caption())
                    .foregroundStyle(DesignSystem.Colors.ink)
                Spacer()
                Text("Tap to connect & join channels →")
                    .font(DesignSystem.Fonts.data(11))
                    .foregroundStyle(DesignSystem.Colors.signal)
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(DesignSystem.Colors.signal.opacity(0.08))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(StreamFilter.allCases, id: \.self) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedFilter = filter
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(DesignSystem.Fonts.chipLabel)
                            .foregroundStyle(selectedFilter == filter ? .white : DesignSystem.Colors.ink)
                            .padding(.horizontal, DesignSystem.Spacing.md)
                            .padding(.vertical, DesignSystem.Spacing.sm)
                            .background(selectedFilter == filter ? DesignSystem.Colors.signal : DesignSystem.Colors.border)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.chip))
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func findServerId(for host: String) -> UUID {
        appState.servers.first(where: { $0.host == host })?.id ?? UUID()
    }

    private func findOrCreateServerID(host: String, port: Int, useTLS: Bool) -> UUID {
        if let existing = appState.servers.first(where: { $0.host == host && $0.port == port }) {
            if appState.connectionStates[existing.id] != .online {
                appState.connect(to: existing.id)
            }
            return existing.id
        }
        let config = IRCConnectionConfig(host: host, port: port, useTLS: useTLS, nickname: "wirc_user")
        appState.servers.append(config)
        appState.connect(to: config.id)
        return config.id
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "No objects yet",
            systemImage: "waveform",
            description: Text("Connect an IRC server, add a feed, or link a Mastodon account in Workshop to start your stream.")
        )
    }
}

// MARK: - Message Card (IRC message in Stream context)

struct MessageCard: View {
    let object: WOMObject
    var onTapChannel: (() -> Void)? = nil
    @State private var showInspector = false

    private var network: String { object.data["network"] ?? "irc" }
    private var sourceColor: Color { DesignSystem.Colors.forSource(network) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Provenance badge
            Button {
                showInspector = true
            } label: {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Circle().fill(sourceColor).frame(width: 6, height: 6)
                    Text("IRC")
                        .font(DesignSystem.Fonts.provenanceLabel)
                        .foregroundStyle(DesignSystem.Colors.ink)
                    if let server = object.data["server"] {
                        Text("· \(server)")
                            .font(DesignSystem.Fonts.provenanceDetail)
                            .foregroundStyle(DesignSystem.Colors.pencil)
                    }
                    Text("·")
                        .foregroundStyle(DesignSystem.Colors.pencil)
                    Text(object.createdAt, style: .relative)
                        .font(DesignSystem.Fonts.timestamp)
                        .foregroundStyle(DesignSystem.Colors.pencil)
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
            }
            .buttonStyle(.plain)

            // Hairline
            Rectangle()
                .fill(sourceColor)
                .frame(height: 1)
                .padding(.horizontal, DesignSystem.Spacing.md)

            // Content
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    if let nick = object.attributedTo?.name ?? object.data["nick"] {
                        Text(nick)
                            .font(DesignSystem.Fonts.senderName)
                            .foregroundStyle(sourceColor)
                    }
                    if let text = object.content?.text {
                        Text(text)
                            .font(DesignSystem.Fonts.messageBody)
                            .foregroundStyle(DesignSystem.Colors.ink)
                            .lineLimit(12)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.md)
                Spacer(minLength: 40)
            }

            // Footer — tappable channel opens filter sheet
            if let channel = object.data["channel"] {
                Button {
                    onTapChannel?()
                } label: {
                    HStack {
                        Text(channel)
                            .font(DesignSystem.Fonts.footer)
                            .foregroundStyle(DesignSystem.Colors.signal)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(DesignSystem.Colors.pencil)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.bottom, DesignSystem.Spacing.sm)
            }
        }
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.card))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .sheet(isPresented: $showInspector) {
            ObjectInspectorSheet(object: object)
        }
    }
}

// MARK: - Channel Filter (uses simple sheet presentation — no NavigationLinks)

struct ChannelFilterView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedChannel: ChannelSelection?
    @State private var showJoinAlert = false
    @State private var joinChannel = ""
    @State private var joinServerId: UUID?

    var body: some View {
        NavigationStack {
            List {
                // Quick-join global channels
                if !appState.orchestrator.globalChannels.isEmpty {
                    Section("Global Channels") {
                        ForEach(appState.orchestrator.globalChannels) { entry in
                            Button {
                                let sid = findOrCreateServer(host: entry.serverHost, port: entry.serverPort, useTLS: entry.serverUseTLS)
                                selectedChannel = ChannelSelection(serverId: sid, serverHost: entry.serverHost, channel: entry.name)
                            } label: {
                                HStack {
                                    Text(entry.name)
                                        .font(DesignSystem.Fonts.data(13))
                                        .foregroundStyle(DesignSystem.Colors.ink)
                                    Spacer()
                                    Text("\(entry.users)")
                                        .font(DesignSystem.Fonts.data(11))
                                        .foregroundStyle(DesignSystem.Colors.pencil)
                                    Text(entry.serverHost)
                                        .font(DesignSystem.Fonts.data(10))
                                        .foregroundStyle(DesignSystem.Colors.pencil)
                                }
                            }
                        }
                    }
                }

                // User-configured servers
                ForEach(appState.servers) { server in
                    Section(server.name.isEmpty ? server.host : server.name) {
                        // Connection row
                        HStack {
                            Circle()
                                .fill(statusColor(appState.connectionStates[server.id] ?? .disconnected))
                                .frame(width: 8, height: 8)
                            Text(server.host)
                                .font(DesignSystem.Fonts.data(13))
                            Spacer()
                            Button(statusLabel(server.id)) {
                                toggleConnection(server.id)
                            }
                            .font(DesignSystem.Fonts.caption())
                            .buttonStyle(.bordered)
                            .tint(statusTint(server.id))
                        }

                        // Channel list
                        let conversations = appState.conversations(forServer: server.host)
                        if conversations.isEmpty {
                            HStack {
                                Text("No channels joined")
                                    .font(DesignSystem.Fonts.caption())
                                    .foregroundStyle(DesignSystem.Colors.pencil)
                                Spacer()
                                Button("Join...") {
                                    joinServerId = server.id
                                    joinChannel = ""
                                    showJoinAlert = true
                                }
                                .font(DesignSystem.Fonts.caption())
                            }
                        }
                        ForEach(conversations) { conv in
                            Button {
                                selectedChannel = ChannelSelection(serverId: server.id, serverHost: server.host, channel: conv.name)
                            } label: {
                                HStack {
                                    Image(systemName: "number")
                                        .font(.caption)
                                        .foregroundStyle(DesignSystem.Colors.irc)
                                    Text(conv.name)
                                        .font(DesignSystem.Fonts.data(13))
                                        .foregroundStyle(DesignSystem.Colors.ink)
                                }
                            }
                        }
                    }
                }

                if appState.servers.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No servers configured",
                            systemImage: "server.rack",
                            description: Text("Add an IRC server in Workshop to start chatting.")
                        )
                    }
                }
            }
            .navigationTitle("Channels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedChannel) { sel in
                MessageView(serverId: sel.serverId, serverHost: sel.serverHost, conversation: .channel(sel.channel))
            }
            .alert("Join Channel", isPresented: $showJoinAlert) {
                TextField("#channel", text: $joinChannel)
                Button("Join") {
                    if let sid = joinServerId, !joinChannel.isEmpty {
                        appState.joinChannel(joinChannel, serverId: sid)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter the channel name to join on this server.")
            }
        }
    }

    // MARK: - Helpers

    private func findOrCreateServer(host: String, port: Int, useTLS: Bool) -> UUID {
        if let existing = appState.servers.first(where: { $0.host == host && $0.port == port }) {
            if appState.connectionStates[existing.id] != .online {
                appState.connect(to: existing.id)
            }
            return existing.id
        }
        let config = IRCConnectionConfig(host: host, port: port, useTLS: useTLS, nickname: "wirc_user")
        appState.servers.append(config)
        appState.connect(to: config.id)
        return config.id
    }

    private func statusColor(_ s: AppState.ConnectionStatus) -> Color {
        switch s { case .disconnected: return .gray; case .connecting: return .orange; case .online: return DesignSystem.Colors.github }
    }
    private func statusLabel(_ id: UUID) -> String {
        switch appState.connectionStates[id] ?? .disconnected {
        case .disconnected: return "Connect"
        case .connecting: return "Connecting..."
        case .online: return "Disconnect"
        }
    }
    private func statusTint(_ id: UUID) -> Color {
        switch appState.connectionStates[id] ?? .disconnected {
        case .disconnected: return DesignSystem.Colors.github
        case .connecting: return .orange
        case .online: return DesignSystem.Colors.signal
        }
    }
    private func toggleConnection(_ id: UUID) {
        switch appState.connectionStates[id] ?? .disconnected {
        case .disconnected: appState.connect(to: id)
        case .connecting, .online: appState.disconnect(from: id)
        }
    }
}

struct ChannelSelection: Identifiable {
    let serverId: UUID
    let serverHost: String
    let channel: String
    var id: String { "\(serverId)|\(channel)" }
}
