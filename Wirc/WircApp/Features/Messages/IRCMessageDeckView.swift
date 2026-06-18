import SwiftUI

/// Full Messages tab: server status bar + channel tabs + timeline + input bar.
/// Channel Deck paradigm — handles hundreds of channels via IRCChannelManager.
struct IRCMessageDeckView: View {
    @Environment(AppState.self) private var appState

    @State private var messageText = ""
    @State private var showServerManager = false
    @State private var showJoinSheet = false
    @State private var showBroadcastPicker = false
    @State private var joinChannel = ""
    @State private var joinServerId: UUID?

    private var manager: IRCChannelManager { appState.channelManager }

    var body: some View {
        VStack(spacing: 0) {
            // Server status bar
            serverStatusBar
            Divider()

            // Channel tabs
            channelTabBar
            Divider()

            // Timeline
            timelineView

            // Input bar
            inputBar
        }
        .background(DesignSystem.Colors.page)
        .onAppear { refreshChannelList() }
        .onChange(of: appState.joinedChannels) { _, _ in refreshChannelList() }
        .onChange(of: appState.womObjects.count) { _, _ in
            // Reload when new messages arrive (debounced by SwiftUI batching)
            Task { await manager.loadMessages() }
        }
        .sheet(isPresented: $showServerManager) {
            IRCServerManagerSheet()
        }
        .sheet(isPresented: $showJoinSheet) {
            JoinChannelSheet(serverId: $joinServerId, channel: $joinChannel) {
                if let sid = joinServerId, !joinChannel.isEmpty {
                    appState.joinChannel(joinChannel, serverId: sid)
                }
                joinChannel = ""
                showJoinSheet = false
            }
        }
        .sheet(isPresented: $showBroadcastPicker) {
            BroadcastPicker(manager: manager)
        }
    }

    // MARK: - Server Status Bar

    private var serverStatusBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(appState.servers) { server in
                    Button {
                        showServerManager = true
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusColor(appState.connectionStates[server.id] ?? .disconnected))
                                .frame(width: 6, height: 6)
                            Text(server.name.isEmpty ? server.host : server.name)
                                .font(DesignSystem.Fonts.caption())
                                .foregroundStyle(DesignSystem.Colors.ink)
                        }
                        .padding(.horizontal, DesignSystem.Spacing.sm)
                        .padding(.vertical, 4)
                        .background(DesignSystem.Colors.border.opacity(0.5))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if appState.servers.isEmpty {
                    Button {
                        showServerManager = true
                    } label: {
                        Label("Add Server", systemImage: "plus")
                            .font(DesignSystem.Fonts.caption())
                    }
                    .buttonStyle(.bordered)
                    .tint(DesignSystem.Colors.signal)
                }

                Button {
                    showServerManager = true
                } label: {
                    Image(systemName: "gear")
                        .font(DesignSystem.Fonts.caption())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.xs)
        }
    }

    // MARK: - Channel Tab Bar

    private var channelTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 2) {
                // All tab
                ChannelTab(
                    label: "All",
                    isActive: manager.isAllMode,
                    badge: manager.channels.count
                ) {
                    manager.setActiveChannel(nil)
                }

                // Individual channels — LazyHStack only renders visible ones
                ForEach(manager.channels) { ch in
                    ChannelTab(
                        label: ch.name,
                        isActive: manager.activeChannel?.id == ch.id,
                        badge: nil
                    ) {
                        manager.setActiveChannel(ch)
                    }
                }

                // Add button
                Button {
                    joinServerId = appState.servers.first?.id
                    showJoinSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.Colors.pencil)
                        .padding(.horizontal, DesignSystem.Spacing.sm)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, DesignSystem.Spacing.xs)
        }
    }

    // MARK: - Timeline

    private var timelineView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    // Pagination: manual load button at top
                    if !manager.visibleMessages.isEmpty && !manager.isLoadingOlder {
                        Button {
                            Task { await manager.loadOlderMessages() }
                        } label: {
                            HStack {
                                Spacer()
                                if manager.isLoadingOlder {
                                    ProgressView()
                                } else {
                                    Text("Load earlier messages")
                                        .font(DesignSystem.Fonts.data(10))
                                        .foregroundStyle(DesignSystem.Colors.pencil)
                                }
                                Spacer()
                            }
                            .padding(.vertical, DesignSystem.Spacing.sm)
                        }
                        .buttonStyle(.plain)
                    } else if manager.isLoadingOlder {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, DesignSystem.Spacing.sm)
                    }

                    ForEach(manager.visibleMessages.reversed()) { object in
                        deckMessageRow(object)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: manager.visibleMessages.count) { _, _ in
                if let last = manager.visibleMessages.first {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func deckMessageRow(_ object: WOMObject) -> some View {
        let isLocal = object.provenance?.isLocalUser ?? false
        let isAction = object.data["isAction"] == "true"
        let nick = object.attributedTo?.name ?? object.data["nick"] ?? "unknown"
        let text = object.content?.text ?? ""
        let channel = object.data["channel"]
        let isDM = object.data["visibility"] == "direct" || object.data["recipient"] != nil
        let network = object.data["network"] ?? "irc"

        // Mention detection
        let localNick = appState.serverConfig(for: manager.activeChannel?.serverId ?? appState.servers.first?.id ?? UUID())?.nickname ?? ""
        let mentionsMe = !isLocal && !localNick.isEmpty && text.localizedCaseInsensitiveContains(localNick)

        VStack(alignment: .leading, spacing: 1) {
            // Channel label (All mode only) or DM indicator
            if manager.isAllMode, let ch = channel {
                Text(isDM ? "DM" : ch)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(isDM ? DesignSystem.Colors.mastodon : DesignSystem.Colors.forSource(network))
            }

            if isAction {
                // /me action — italic rendering
                HStack(spacing: 6) {
                    Text(text)
                        .font(DesignSystem.Fonts.messageBody)
                        .italic()
                        .foregroundStyle(DesignSystem.Colors.pencil)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(nick)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(isLocal ? DesignSystem.Colors.signal : DesignSystem.Colors.forSource(network))
                        .frame(width: 72, alignment: .trailing)
                        .lineLimit(1)

                    Text(text)
                        .font(DesignSystem.Fonts.messageBody)
                        .foregroundStyle(mentionsMe ? DesignSystem.Colors.signal : DesignSystem.Colors.ink)
                        .fontWeight(mentionsMe ? .bold : .regular)
                }
            }
        }
        .padding(.vertical, 2)
        .background(mentionsMe ? DesignSystem.Colors.signal.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .id(object.id)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            // Target indicator
            Button {
                if manager.isAllMode {
                    showBroadcastPicker = true
                }
            } label: {
                HStack(spacing: 4) {
                    if manager.isAllMode {
                        Text("All \(manager.channels.count)")
                            .font(DesignSystem.Fonts.data(11))
                    } else {
                        Text(manager.activeChannel?.name ?? "")
                            .font(DesignSystem.Fonts.data(11))
                    }
                    if manager.isAllMode {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                    }
                }
                .foregroundStyle(DesignSystem.Colors.signal)
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, 4)
                .background(DesignSystem.Colors.signal.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)

            TextField("Message", text: $messageText)
                .textFieldStyle(.roundedBorder)
                .font(DesignSystem.Fonts.messageBody)

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(messageText.isEmpty ? DesignSystem.Colors.pencil : DesignSystem.Colors.signal)
            }
            .disabled(messageText.isEmpty)
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(.bar)
    }

    // MARK: - Actions

    private func send() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messageText = ""

        // Expand aliases before parsing
        let expanded = appState.automation.expandAlias(text) ?? text
        let cmd = IRCCommandParser.parse(expanded)
        let serverId = manager.activeChannel?.serverId ?? appState.servers.first?.id

        guard let sid = serverId else { return }

        // Handle plain messages vs commands
        switch cmd {
        case .message:
            if let ch = manager.activeChannel {
                appState.sendMessage(text, channel: ch.name, serverId: ch.serverId)
            } else if manager.hasBroadcastTargets {
                for target in manager.broadcastTargets {
                    appState.sendMessage(text, channel: target.name, serverId: target.serverId)
                }
            } else {
                showBroadcastPicker = true
                messageText = text
            }

        case .me(let action):
            // Send CTCP ACTION to channel
            let target = manager.activeChannel?.name ?? ""
            let nick = appState.serverConfig(for: sid)?.nickname ?? "user"
            if !target.isEmpty {
                clientsSendCTCPAction(action, to: target, serverId: sid)
            }
            // Save locally
            let objId = WOMIDGenerator.generate(type: "message")
            let obj = WOMObject(
                id: objId, type: ["wom:Message", "wom:Action"], createdAt: Date(),
                attributedTo: WOMReference(id: "local:user", type: ["wom:Person"], name: nick),
                content: WOMContent(format: "text/plain", text: "* \(nick) \(action)"),
                data: ["network": "irc", "server": appState.serverConfig(for: sid)?.host ?? "", "isAction": "true"],
                provenance: .localUser()
            )
            Task {
                try? await appState.store.save(obj)
                appState.womObjects.append(obj)
            }

        default:
            // Execute IRC command
            _ = IRCCommandExecutor.execute(cmd, serverId: sid, appState: appState)
        }
    }

    private func clientsSendCTCPAction(_ action: String, to target: String, serverId: UUID) {
        guard let client = appState.client(for: serverId) else { return }
        client.sendMessage("\u{01}ACTION \(action)\u{01}", to: target)
    }

    private func refreshChannelList() {
        manager.refreshChannelList(
            servers: appState.servers,
            joinedChannels: appState.joinedChannels,
            channelUsers: appState.channelUsers
        )
        Task { await manager.loadMessages() }
    }

    private func statusColor(_ s: AppState.ConnectionStatus) -> Color {
        switch s { case .disconnected: return .gray; case .connecting: return .orange; case .online: return DesignSystem.Colors.github }
    }
}

// MARK: - Channel Tab

struct ChannelTab: View {
    let label: String
    let isActive: Bool
    var badge: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(isActive ? DesignSystem.Fonts.data(12, weight: .bold) : DesignSystem.Fonts.data(12))
                if let b = badge, b > 0 {
                    Text("\(b)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                }
            }
            .foregroundStyle(isActive ? .white : DesignSystem.Colors.ink)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, 6)
            .background(isActive ? DesignSystem.Colors.signal : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.chip))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Broadcast Picker

struct BroadcastPicker: View {
    let manager: IRCChannelManager
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<ChannelHandle> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Select All") { selected = Set(manager.channels) }
                    Button("Deselect All") { selected = [] }
                }

                Section("Channels") {
                    ForEach(manager.channels) { ch in
                        Button {
                            if selected.contains(ch) { selected.remove(ch) }
                            else { selected.insert(ch) }
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(ch) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(ch) ? DesignSystem.Colors.signal : DesignSystem.Colors.pencil)
                                Text(ch.name)
                                    .foregroundStyle(DesignSystem.Colors.ink)
                                Spacer()
                                Text(ch.serverHost)
                                    .font(DesignSystem.Fonts.data(10))
                                    .foregroundStyle(DesignSystem.Colors.pencil)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Broadcast to...")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") {
                        manager.broadcastTargets = selected
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Join Channel Sheet

struct JoinChannelSheet: View {
    @Binding var serverId: UUID?
    @Binding var channel: String
    let onJoin: () -> Void
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    Picker("Server", selection: $serverId) {
                        ForEach(appState.servers) { server in
                            Text(server.name.isEmpty ? server.host : server.name)
                                .tag(Optional(server.id))
                        }
                    }
                }
                Section("Channel") {
                    TextField("#channel", text: $channel)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Join Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") { onJoin() }
                        .disabled(channel.isEmpty)
                }
            }
        }
    }
}
