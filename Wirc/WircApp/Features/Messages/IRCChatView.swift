import SwiftUI

/// Full-screen IRC chat with minimal header, timeline, input bar, and a bottom sheet
/// for server/channel/user management. Maximizes message space: only 113pt of fixed chrome.
struct IRCChatView: View {
    @Environment(AppState.self) private var appState

    @State private var messageText = ""
    @State private var showSheet = false
    @State private var sheetHeight: PresentationDetent = .medium
    @State private var showChannelDropdown = false
    @State private var showBroadcastPicker = false
    @State private var expandedUsers: Set<String> = []

    private var manager: IRCChannelManager { appState.irc.channelManager }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            headerBar
            Divider()

            // Timeline
            timelineView
            Divider()

            // Input bar
            inputBar

            // Drag handle
            dragHandle
        }
        .background(DesignSystem.Colors.page)
        .onAppear { refreshChannelList(); autoScanIfNeeded() }
        .onChange(of: appState.irc.servers.count) { _, _ in refreshChannelList() }
        .onChange(of: appState.irc.joinedChannels) { _, _ in refreshChannelList() }
        .onChange(of: appState.womObjects.count) { _, _ in
            Task { await manager.loadMessages() }
        }
        .sheet(isPresented: $showSheet) {
            channelSheet
                .presentationDetents([.medium, .large], selection: $sheetHeight)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showBroadcastPicker) {
            BroadcastPicker(manager: manager)
        }
    }

    // MARK: - Header Bar (44pt)

    private var headerBar: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            // Channel selector dropdown
            Button { showChannelDropdown = true } label: {
                HStack(spacing: 2) {
                    Text(headerTitle)
                        .font(DesignSystem.Fonts.data(12, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.ink)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.pencil)
                }
                .frame(width: 90, alignment: .leading)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showChannelDropdown) {
                channelDropdown
            }

            // Server info (tappable → sheet)
            Button { showSheet = true } label: {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 6, height: 6)
                    Text(serverInfo)
                        .font(DesignSystem.Fonts.data(10))
                        .foregroundStyle(DesignSystem.Colors.pencil)
                        .lineLimit(1)
                    if let active = manager.activeChannel {
                        Text("· \(active.name)")
                            .font(DesignSystem.Fonts.data(10))
                            .foregroundStyle(DesignSystem.Colors.ink)
                        Text("· \(active.userCount)")
                            .font(DesignSystem.Fonts.data(10))
                            .foregroundStyle(DesignSystem.Colors.pencil)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .frame(height: 44)
    }

    private var headerTitle: String {
        if let ch = manager.activeChannel { return ch.name }
        if manager.channels.isEmpty { return "All" }
        return "All \(manager.channels.count)"
    }

    private var connectionColor: Color {
        let states = appState.irc.connectionStates.values
        if states.contains(.online) { return DesignSystem.Colors.github }
        if states.contains(.connecting) { return .orange }
        return .gray
    }

    private var serverInfo: String {
        if let ch = manager.activeChannel {
            return ch.serverHost
        }
        if let first = appState.irc.servers.first {
            return first.name.isEmpty ? first.host : first.name
        }
        return "No servers"
    }

    // MARK: - Channel Dropdown

    private var channelDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                manager.setActiveChannel(nil)
                showChannelDropdown = false
            } label: {
                HStack {
                    Text("All \(manager.channels.count)")
                        .font(DesignSystem.Fonts.data(12, weight: manager.isAllMode ? .bold : .regular))
                    Spacer()
                    if manager.isAllMode { Image(systemName: "checkmark") }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
            }
            .buttonStyle(.plain)

            Divider()

            ForEach(manager.channels) { ch in
                Button {
                    manager.setActiveChannel(ch)
                    showChannelDropdown = false
                } label: {
                    HStack {
                        Text(ch.name)
                            .font(DesignSystem.Fonts.data(12, weight: manager.activeChannel?.id == ch.id ? .bold : .regular))
                        Spacer()
                        Text("\(ch.userCount)")
                            .font(DesignSystem.Fonts.data(10))
                            .foregroundStyle(DesignSystem.Colors.pencil)
                        if manager.activeChannel?.id == ch.id {
                            Image(systemName: "checkmark")
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 200)
        .frame(minHeight: min(CGFloat(manager.channels.count + 1) * 36, 300))
    }

    // MARK: - Timeline

    private var timelineView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if !manager.visibleMessages.isEmpty && !manager.isLoadingOlder {
                        Button {
                            Task { await manager.loadOlderMessages() }
                        } label: {
                            HStack {
                                Spacer()
                                Text("Load earlier messages")
                                    .font(DesignSystem.Fonts.data(10))
                                    .foregroundStyle(DesignSystem.Colors.pencil)
                                Spacer()
                            }
                            .padding(.vertical, DesignSystem.Spacing.sm)
                        }
                        .buttonStyle(.plain)
                    } else if manager.isLoadingOlder {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .padding(.vertical, DesignSystem.Spacing.sm)
                    }

                    ForEach(manager.visibleMessages.reversed()) { object in
                        chatMessageRow(object)
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

    private func chatMessageRow(_ object: WOMObject) -> some View {
        let isLocal = object.provenance?.isLocalUser ?? false
        let isAction = object.data["isAction"] == "true"
        let nick = object.attributedTo?.name ?? object.data["nick"] ?? "unknown"
        let text = object.content?.text ?? ""
        let channel = object.data["channel"]
        let isDM = object.data["visibility"] == "direct"
        let network = object.data["network"] ?? "irc"

        let localNick = appState.irc.config(for: manager.activeChannel?.serverId ?? appState.irc.servers.first?.id ?? UUID())?.nickname ?? ""
        let mentionsMe = !isLocal && !localNick.isEmpty && text.localizedCaseInsensitiveContains(localNick)

        return VStack(alignment: .leading, spacing: 1) {
            if manager.isAllMode, let ch = channel {
                Text(isDM ? "DM" : ch)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(isDM ? DesignSystem.Colors.mastodon : DesignSystem.Colors.forSource(network))
            }

            if isAction {
                Text(text)
                    .font(DesignSystem.Fonts.messageBody)
                    .italic()
                    .foregroundStyle(DesignSystem.Colors.pencil)
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

    // MARK: - Input Bar (48pt)

    private var inputBar: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            // Channel prefix (tappable for quick switch)
            Button {
                if manager.isAllMode && manager.hasBroadcastTargets {
                    showBroadcastPicker = true
                } else {
                    showChannelDropdown = true
                }
            } label: {
                HStack(spacing: 2) {
                    Text(inputPrefix)
                        .font(DesignSystem.Fonts.data(10))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 7))
                }
                .foregroundStyle(DesignSystem.Colors.signal)
                .padding(.horizontal, DesignSystem.Spacing.xs)
                .padding(.vertical, 3)
                .background(DesignSystem.Colors.signal.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)

            TextField("Message", text: $messageText)
                .textFieldStyle(.plain)
                .font(DesignSystem.Fonts.messageBody)

            Button { send() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(messageText.isEmpty ? DesignSystem.Colors.pencil : DesignSystem.Colors.signal)
            }
            .disabled(messageText.isEmpty)
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .frame(minHeight: 48)
        .background(.bar)
    }

    private var inputPrefix: String {
        if manager.isAllMode {
            let count = manager.hasBroadcastTargets ? manager.broadcastTargets.count : manager.channels.count
            return "All \(count)"
        }
        return manager.activeChannel?.name ?? ""
    }

    // MARK: - Drag Handle (20pt)

    private var dragHandle: some View {
        Button { showSheet = true } label: {
            RoundedRectangle(cornerRadius: 2)
                .fill(DesignSystem.Colors.border)
                .frame(width: 36, height: 5)
                .padding(.vertical, DesignSystem.Spacing.xs)
        }
        .buttonStyle(.plain)
        .frame(height: 20)
    }

    // MARK: - Channel Sheet

    private var channelSheet: some View {
        NavigationStack {
            List {
                // Servers section
                Section("Servers") {
                    ForEach(appState.irc.servers) { server in
                        serverSection(server)
                    }

                    Button { /* AddServerView sheet */ } label: {
                        Label("Add Server...", systemImage: "plus")
                            .font(DesignSystem.Fonts.caption())
                    }
                }

                // Quick Join
                Section("Quick Join") {
                    QuickJoinField(servers: appState.irc.servers) { channel, serverId in
                        appState.irc.joinChannel(channel, serverId: serverId)
                    }
                }

                // Popular channels
                if !appState.irc.orchestrator.globalChannels.isEmpty {
                    Section("Popular") {
                        if appState.irc.orchestrator.isScanning {
                            HStack { ProgressView(); Text("Scanning...").font(DesignSystem.Fonts.caption()) }
                        }
                        ForEach(appState.irc.orchestrator.globalChannels.prefix(25)) { ch in
                            Button {
                                if let sid = appState.irc.servers.first(where: { $0.host == ch.serverHost })?.id {
                                    appState.irc.joinChannel(ch.name, serverId: sid)
                                }
                                showSheet = false
                            } label: {
                                HStack {
                                    Text(ch.name).font(DesignSystem.Fonts.data(13)).foregroundStyle(DesignSystem.Colors.ink)
                                    Spacer()
                                    Text("\(ch.users)").font(DesignSystem.Fonts.data(10)).foregroundStyle(DesignSystem.Colors.pencil)
                                    Text(ch.serverHost).font(DesignSystem.Fonts.data(9)).foregroundStyle(DesignSystem.Colors.pencil)
                                }
                            }
                        }
                    }
                } else {
                    Section("Popular") {
                        Button { appState.irc.orchestrator.startScan() } label: {
                            Label("Scan for channels", systemImage: "magnifyingglass")
                        }
                    }
                }
            }
            .navigationTitle("Servers & Channels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showSheet = false }
                }
            }
        }
    }

    @ViewBuilder
    private func serverSection(_ server: IRCConnectionConfig) -> some View {
        let isOnline = appState.irc.connectionStates[server.id] == .online
        let channels = appState.irc.conversations(forServer: server.host)

        DisclosureGroup {
            // Connection controls
            HStack {
                Button(isOnline ? "Disconnect" : "Connect") {
                    if isOnline { appState.irc.disconnect(from: server.id) }
                    else { appState.irc.connect(to: server.id) }
                }
                .buttonStyle(.bordered)
                .tint(isOnline ? DesignSystem.Colors.signal : DesignSystem.Colors.github)
                .font(DesignSystem.Fonts.caption())
                Spacer()
                Text("\(server.host):\(server.port)")
                    .font(DesignSystem.Fonts.data(10))
                    .foregroundStyle(DesignSystem.Colors.pencil)
            }
            .padding(.top, 4)

            // Channel list
            if channels.isEmpty {
                Text("No channels joined")
                    .font(DesignSystem.Fonts.caption())
                    .foregroundStyle(DesignSystem.Colors.pencil)
            }
            ForEach(channels) { conv in
                let key = "\(server.host)|\(conv.name.lowercased())"
                let count = appState.irc.channelUsers[key]?.count ?? 0

                Button {
                    let handle = manager.channels.first(where: { $0.serverId == server.id && $0.name == conv.name })
                        ?? ChannelHandle(serverId: server.id, serverHost: server.host, name: conv.name, userCount: count)
                    manager.setActiveChannel(handle)
                    showSheet = false
                } label: {
                    HStack {
                        Text(conv.name)
                            .font(DesignSystem.Fonts.data(13))
                            .foregroundStyle(DesignSystem.Colors.ink)
                        Spacer()
                        if count > 0 { Text("\(count)").font(DesignSystem.Fonts.data(10)).foregroundStyle(DesignSystem.Colors.pencil) }
                        let unread = manager.unreadCounts[key] ?? 0
                        if unread > 0 {
                            Circle().fill(DesignSystem.Colors.signal).frame(width: 7, height: 7)
                            Text("\(unread)").font(DesignSystem.Fonts.data(9)).foregroundStyle(DesignSystem.Colors.signal)
                        }

                        // Expand user list button
                        Button {
                            if expandedUsers.contains(conv.name) { expandedUsers.remove(conv.name) }
                            else { expandedUsers.insert(conv.name) }
                        } label: {
                            Image(systemName: "chevron.right")
                                .rotationEffect(.degrees(expandedUsers.contains(conv.name) ? 90 : 0))
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Expanded user list
                if expandedUsers.contains(conv.name), let users = appState.irc.channelUsers[key] {
                    ForEach(users.prefix(50)) { user in
                        HStack(spacing: 2) {
                            Text(user.prefix)
                                .font(DesignSystem.Fonts.data(9))
                                .foregroundStyle(prefixColor(user.prefix))
                                .frame(width: 12, alignment: .trailing)
                            Text(user.nick)
                                .font(DesignSystem.Fonts.data(10))
                                .foregroundStyle(DesignSystem.Colors.pencil)
                        }
                        .padding(.leading, DesignSystem.Spacing.lg)
                    }
                    if users.count > 50 {
                        Text("... and \(users.count - 50) more")
                            .font(DesignSystem.Fonts.data(9))
                            .foregroundStyle(DesignSystem.Colors.pencil)
                            .padding(.leading, DesignSystem.Spacing.lg)
                    }
                }
            }
        } label: {
            HStack {
                Circle()
                    .fill(isOnline ? DesignSystem.Colors.github : .gray)
                    .frame(width: 8, height: 8)
                Text(server.name.isEmpty ? server.host : server.name)
                    .font(.system(size: 15, weight: .medium))
                Spacer()
                Text(isOnline ? "online" : "offline")
                    .font(DesignSystem.Fonts.data(10))
                    .foregroundStyle(isOnline ? DesignSystem.Colors.github : DesignSystem.Colors.pencil)
            }
        }
    }

    // MARK: - Actions

    private func send() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messageText = ""

        let expanded = appState.irc.automation.expandAlias(text) ?? text
        let cmd = IRCCommandParser.parse(expanded)
        let serverId = manager.activeChannel?.serverId ?? appState.irc.servers.first?.id

        guard let sid = serverId else { return }

        switch cmd {
        case .message:
            if let ch = manager.activeChannel {
                appState.sendMessage(text, channel: ch.name, serverId: ch.serverId)
            } else if manager.hasBroadcastTargets {
                for target in manager.broadcastTargets {
                    appState.sendMessage(text, channel: target.name, serverId: target.serverId)
                }
            } else if let first = manager.channels.first {
                appState.sendMessage(text, channel: first.name, serverId: first.serverId)
            }
        case .me(let action):
            let nick = appState.irc.config(for: sid)?.nickname ?? "user"
            let targets: [String] = manager.activeChannel.map { [$0.name] } ?? manager.channels.map { $0.name }
            for target in targets.prefix(1) {
                appState.irc.client(for: sid)?.sendMessage("\u{01}ACTION \(action)\u{01}", to: target)
            }
            let obj = WOMObject(id: WOMIDGenerator.generate(type: "message"), type: ["wom:Message", "wom:Action"],
                createdAt: Date(), attributedTo: WOMReference(id: "local:user", type: ["wom:Person"], name: nick),
                content: WOMContent(format: "text/plain", text: "* \(nick) \(action)"),
                data: ["network": "irc", "server": appState.irc.config(for: sid)?.host ?? "", "isAction": "true"],
                provenance: .localUser())
            Task { try? await appState.store.save(obj); appState.womObjects.append(obj) }
        default:
            _ = IRCCommandExecutor.execute(cmd, serverId: sid, appState: appState)
        }
    }

    private func refreshChannelList() {
        manager.refreshChannelList(servers: appState.irc.servers, joinedChannels: appState.irc.joinedChannels, channelUsers: appState.irc.channelUsers)
        Task { await manager.loadMessages() }
    }

    @State private var hasAutoScanned = false
    private func autoScanIfNeeded() {
        guard !hasAutoScanned else { return }
        hasAutoScanned = true
        if !appState.irc.servers.isEmpty && appState.irc.orchestrator.globalChannels.isEmpty {
            appState.irc.orchestrator.startScan()
        }
    }

    private func prefixColor(_ p: String) -> Color {
        switch p {
        case "~": return .purple
        case "&": return .red
        case "@": return DesignSystem.Colors.github
        case "%": return .blue
        case "+": return .orange
        default: return .secondary
        }
    }
}

// MARK: - Quick Join Field

struct QuickJoinField: View {
    let servers: [IRCConnectionConfig]
    let onJoin: (String, UUID) -> Void
    @State private var channel = ""

    var body: some View {
        HStack {
            TextField("#channel", text: $channel)
                .textFieldStyle(.plain)
                .font(DesignSystem.Fonts.data(13))
                .autocapitalization(.none)
                .autocorrectionDisabled()
            Button("Join") {
                guard !channel.isEmpty, let sid = servers.first(where: { $0.id == servers.first?.id })?.id ?? servers.first?.id else { return }
                let ch = channel.hasPrefix("#") ? channel : "#\(channel)"
                onJoin(ch, sid)
                channel = ""
            }
            .font(DesignSystem.Fonts.caption())
            .disabled(channel.isEmpty)
        }
    }
}
