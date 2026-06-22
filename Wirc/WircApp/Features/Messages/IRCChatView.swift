import SwiftUI

/// Unified IRC chat view — server status bar + channel tabs + timeline + input.
/// Combines the compact chrome of the original ChatView with the visible
/// navigation of the MessageDeckView.
struct IRCChatView: View {
    @Environment(AppState.self) private var appState

    @State private var messageText = ""
    @State private var showSheet = false
    @State private var sheetHeight: PresentationDetent = .medium
    @State private var showBroadcastPicker = false
    @State private var expandedUsers: Set<String> = []
    @State private var loadMessagesTask: Task<Void, Never>?
    @State private var commandFeedback: String?
    @State private var commandFeedbackTask: Task<Void, Never>?
    @State private var showJoinSheet = false
    @State private var joinChannel = ""
    @State private var joinServerId: UUID?

    private var manager: IRCChannelManager { appState.irc.channelManager }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                if appState.irc.servers.isEmpty {
                    emptyState
                } else if manager.channels.isEmpty && manager.visibleMessages.isEmpty {
                    noChannelsState
                } else {
                    // Server status bar
                    serverStatusBar
                    Divider()

                    // Channel tabs
                    channelTabBar
                    Divider()

                    // Timeline
                    timelineView
                    Divider()

                    // Input bar
                    inputBar

                    // Drag handle
                    dragHandle
                }
            }
            .background(DesignSystem.Colors.page)
            .onAppear { refreshChannelList(); autoScanIfNeeded() }
            .onChange(of: appState.irc.servers.count) { _, _ in refreshChannelList() }
            .onChange(of: appState.irc.joinedChannels) { _, _ in refreshChannelList() }
            .onChange(of: appState.womObjects.count) { _, _ in
                loadMessagesTask?.cancel()
                loadMessagesTask = Task {
                    try? await Task.sleep(for: .milliseconds(120))
                    guard !Task.isCancelled else { return }
                    manager.loadMessages()
                }
            }
            .sheet(isPresented: $showSheet) {
                channelSheet
                    .presentationDetents([.medium, .large], selection: $sheetHeight)
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showBroadcastPicker) {
                BroadcastPicker(manager: manager)
            }
            .sheet(isPresented: $showJoinSheet) {
                JoinChannelSheet(serverId: $joinServerId, channel: $joinChannel) {
                    if let sid = joinServerId, !joinChannel.isEmpty {
                        appState.irc.joinChannel(joinChannel, serverId: sid)
                    }
                    joinChannel = ""
                    showJoinSheet = false
                }
            }

            // Command feedback toast
            if let feedback = commandFeedback {
                VStack {
                    Text(feedback)
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .background(DesignSystem.Colors.ink.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.chip))
                        .padding(.top, 60)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Server Status Bar

    private var serverStatusBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(appState.irc.servers) { server in
                    Button {
                        showSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusColor(appState.irc.connectionStates[server.id] ?? .disconnected))
                                .frame(width: 6, height: 6)
                            Text(server.name.isEmpty ? server.host : server.name)
                                .font(DesignSystem.Fonts.caption)
                                .foregroundStyle(DesignSystem.Colors.ink)
                        }
                        .padding(.horizontal, DesignSystem.Spacing.sm)
                        .padding(.vertical, 4)
                        .background(DesignSystem.Colors.border.opacity(0.5))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    showSheet = true
                    sheetHeight = .large
                } label: {
                    Image(systemName: "gear")
                        .font(DesignSystem.Fonts.caption)
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
                ChannelTab(
                    label: "All",
                    isActive: manager.isAllMode,
                    badge: manager.channels.count
                ) {
                    manager.setActiveChannel(nil)
                }

                ForEach(manager.channels) { ch in
                    ChannelTab(
                        label: ch.name,
                        isActive: manager.activeChannel?.id == ch.id,
                        badge: nil
                    ) {
                        manager.setActiveChannel(ch)
                    }
                }

                Button {
                    joinServerId = manager.activeChannel?.serverId ?? appState.irc.servers.first?.id
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
                    if manager.visibleMessages.isEmpty {
                        let sysEvents = appState.womObjects.filter {
                            $0.type.contains("wom:SystemEvent") && $0.type.contains("wom:TransportEnvelope")
                        }.sorted { $0.createdAt > $1.createdAt }.prefix(20)

                        if !sysEvents.isEmpty {
                            ForEach(Array(sysEvents)) { obj in
                                systemEventRow(obj)
                            }
                        } else {
                            VStack(spacing: DesignSystem.Spacing.md) {
                                Spacer().frame(height: 80)
                                ProgressView()
                                Text("Waiting for messages...")
                                    .font(DesignSystem.Fonts.caption)
                                    .foregroundStyle(DesignSystem.Colors.pencil)
                                Text("Joined \(manager.activeChannel?.name ?? "channels"). Messages appear when someone speaks.")
                                    .font(DesignSystem.Fonts.data(10))
                                    .foregroundStyle(DesignSystem.Colors.pencil)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    } else {
                        if !manager.isLoadingOlder {
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
                            if object.type.contains("wom:SystemEvent") {
                                systemEventRow(object)
                            } else {
                                chatMessageRow(object)
                            }
                        }
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
            }
            .defaultScrollAnchor(.bottom)
        }
    }

    private func chatMessageRow(_ object: WOMObject) -> some View {
        let isLocal = object.provenance?.isLocalUser ?? false
        let isAction = object.data["isAction"] == "true"
        let isBroadcast = object.data["isBroadcast"] == "true"
        let nick = object.attributedTo?.name ?? object.data["nick"] ?? "unknown"
        let text = object.content?.text ?? ""
        let channel = object.data["channel"]
        let isDM = object.data["visibility"] == "direct" || object.data["recipient"] != nil
        let network = object.data["network"] ?? "irc"

        let localNick = appState.irc.config(for: manager.activeChannel?.serverId ?? appState.irc.servers.first?.id ?? UUID())?.nickname ?? ""
        let mentionsMe = !isLocal && !localNick.isEmpty && text.localizedCaseInsensitiveContains(localNick)

        return VStack(alignment: .leading, spacing: 1) {
            if manager.isAllMode, let ch = channel {
                HStack(spacing: 4) {
                    Text(isDM ? "DM" : ch)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(isDM ? DesignSystem.Colors.mastodon : DesignSystem.Colors.forSource(network))
                }
            }
            if isBroadcast, let count = object.data["targetCount"] ?? object.data["broadcastCount"] {
                Text("📢 to \(count) channels")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.signal)
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

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Button {
                if manager.isAllMode && manager.hasBroadcastTargets {
                    showBroadcastPicker = true
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
            .accessibilityLabel("Send message")
            .accessibilityHint("Sends your message to the current channel")
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

    // MARK: - Drag Handle

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
                Section("Servers") {
                    ForEach(appState.irc.servers) { server in
                        serverSection(server)
                    }
                    Button {
                        showSheet = true
                        sheetHeight = .large
                    } label: {
                        Label("Add Server...", systemImage: "plus")
                    }
                }

                Section("Quick Join") {
                    QuickJoinField(servers: appState.irc.servers, activeServerId: manager.activeChannel?.serverId) { channel, serverId in
                        appState.irc.joinChannel(channel, serverId: serverId)
                    }
                }

                if !appState.irc.orchestrator.globalChannels.isEmpty {
                    Section("Popular") {
                        if appState.irc.orchestrator.isScanning {
                            HStack { ProgressView(); Text("Scanning...").font(DesignSystem.Fonts.caption) }
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
            HStack {
                Button(isOnline ? "Disconnect" : "Connect") {
                    if isOnline { appState.irc.disconnect(from: server.id) }
                    else { appState.irc.connect(to: server.id) }
                }
                .buttonStyle(.bordered)
                .tint(isOnline ? DesignSystem.Colors.signal : DesignSystem.Colors.github)
                .font(DesignSystem.Fonts.caption)
                Spacer()
                Text("\(server.host):\(server.port)")
                    .font(DesignSystem.Fonts.data(10))
                    .foregroundStyle(DesignSystem.Colors.pencil)
            }
            .padding(.top, 4)

            if channels.isEmpty {
                Text("No channels joined")
                    .font(DesignSystem.Fonts.caption)
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
                        Button {
                            if expandedUsers.contains(key) { expandedUsers.remove(key) }
                            else { expandedUsers.insert(key) }
                        } label: {
                            Image(systemName: "chevron.right")
                                .rotationEffect(.degrees(expandedUsers.contains(key) ? 90 : 0))
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if expandedUsers.contains(key), let users = appState.irc.channelUsers[key] {
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

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Spacer()
            ContentUnavailableView(
                "No IRC servers configured",
                systemImage: "antenna.radiowaves.left.and.right",
                description: Text("Add an IRC server in Settings to start chatting.")
            )
            Button {
                // Navigate to Settings
                showSheet = true
                sheetHeight = .large
            } label: {
                Label("Open Settings", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
            Spacer()
        }
    }

    private var noChannelsState: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Spacer()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(appState.irc.servers) { server in
                        serverStatusPill(server)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
            }
            .padding(.top, DesignSystem.Spacing.md)

            Spacer()

            ContentUnavailableView(
                "No channels joined",
                systemImage: "number",
                description: Text("Join a channel or use Quick Join in the channel sheet.")
            )

            if !appState.irc.orchestrator.globalChannels.isEmpty {
                VStack {
                    Text("Popular channels").font(DesignSystem.Fonts.caption).foregroundStyle(DesignSystem.Colors.pencil)
                    ForEach(appState.irc.orchestrator.globalChannels.prefix(10)) { ch in
                        Button {
                            if let sid = appState.irc.servers.first(where: { $0.host == ch.serverHost })?.id {
                                appState.irc.joinChannel(ch.name, serverId: sid)
                            }
                        } label: {
                            HStack {
                                Text(ch.name).font(DesignSystem.Fonts.data(13)).foregroundStyle(DesignSystem.Colors.ink)
                                Spacer()
                                Text("\(ch.users)").font(DesignSystem.Fonts.data(10)).foregroundStyle(DesignSystem.Colors.pencil)
                            }
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                            .padding(.vertical, 4)
                        }
                    }
                }
            } else {
                Button { appState.irc.orchestrator.startScan() } label: {
                    Label("Scan for channels", systemImage: "magnifyingglass")
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
    }

    private func serverStatusPill(_ server: IRCConnectionConfig) -> some View {
        let state = appState.irc.connectionStates[server.id] ?? .disconnected
        return Button {
            if state == .online { appState.irc.disconnect(from: server.id) }
            else { appState.irc.connect(to: server.id) }
        } label: {
            HStack(spacing: 4) {
                Circle().fill(statusColor(state)).frame(width: 6, height: 6)
                Text(server.name.isEmpty ? server.host : server.name)
                    .font(DesignSystem.Fonts.caption)
                Text(stateLabel(state))
                    .font(DesignSystem.Fonts.data(10))
            }
            .foregroundStyle(DesignSystem.Colors.ink)
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, 8)
            .background(DesignSystem.Colors.border.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.chip))
        }
        .buttonStyle(.plain)
    }

    private func statusColor(_ s: IRCManager.ConnectionStatus) -> Color {
        switch s { case .disconnected: return .gray; case .connecting: return .orange; case .online: return DesignSystem.Colors.github }
    }

    private func stateLabel(_ s: IRCManager.ConnectionStatus) -> String {
        switch s { case .disconnected: return "off"; case .connecting: return "connecting..."; case .online: return "on" }
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
            } else {
                let targets = manager.hasBroadcastTargets
                    ? Array(manager.broadcastTargets)
                    : manager.channels
                let localObj = WOMObject(
                    id: WOMIDGenerator.generate(type: "message"),
                    type: ["wom:Message", "wom:Broadcast"],
                    createdAt: Date(),
                    attributedTo: WOMReference(id: "local:user", type: ["wom:Person"], name: appState.irc.config(for: sid)?.nickname ?? "user"),
                    content: WOMContent(format: "text/plain", text: text),
                    data: ["network": "irc", "isBroadcast": "true", "targetCount": "\(targets.count)"],
                    provenance: .localUser()
                )
                Task { try? await appState.store.save(localObj); appState.womObjects.append(localObj) }
                for target in targets {
                    appState.sendMessage(text, channel: target.name, serverId: target.serverId)
                }
            }
        case .me(let action):
            let nick = appState.irc.config(for: sid)?.nickname ?? "user"
            let targets: [String] = manager.activeChannel.map { [$0.name] } ?? manager.channels.map { $0.name }
            // Send to ALL relevant targets (not just first)
            for target in targets {
                appState.irc.client(for: sid)?.sendMessage("\u{01}ACTION \(action)\u{01}", to: target)
            }
            let obj = WOMObject(id: WOMIDGenerator.generate(type: "message"), type: ["wom:Message", "wom:Action"],
                createdAt: Date(), attributedTo: WOMReference(id: "local:user", type: ["wom:Person"], name: nick),
                content: WOMContent(format: "text/plain", text: "* \(nick) \(action)"),
                data: ["network": "irc", "server": appState.irc.config(for: sid)?.host ?? "", "isAction": "true"],
                provenance: .localUser())
            Task { try? await appState.store.save(obj); appState.womObjects.append(obj) }
        default:
            let result = IRCCommandExecutor.execute(cmd, serverId: sid, appState: appState)
            if let feedback = result {
                commandFeedback = feedback
                commandFeedbackTask?.cancel()
                commandFeedbackTask = Task {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    commandFeedback = nil
                }
            }
        }
    }

    private func refreshChannelList() {
        manager.refreshChannelList(servers: appState.irc.servers, joinedChannels: appState.irc.joinedChannels, channelUsers: appState.irc.channelUsers)
        manager.loadMessages()
    }

    @State private var hasAutoScanned = false
    private func autoScanIfNeeded() {
        guard !hasAutoScanned else { return }
        hasAutoScanned = true
        if !appState.irc.servers.isEmpty && appState.irc.orchestrator.globalChannels.isEmpty {
            appState.irc.orchestrator.startScan()
        }
    }

    private func systemEventRow(_ object: WOMObject) -> some View {
        let eventType = object.data["eventType"] ?? object.data["event"] ?? ""
        let nick = object.data["nick"] ?? ""
        let text: String = {
            switch eventType {
            case "join": return "→ \(nick) joined"
            case "part": return "← \(nick) left" + (object.data["reason"].map { " (\($0))" } ?? "")
            case "quit": return "← \(nick) quit"
            case "kick": return "✕ \(nick) kicked"
            case "nick": return "~ \(object.data["oldNick"] ?? "") → \(object.data["newNick"] ?? "")"
            case "topic": return "# topic: \(object.data["topic"] ?? "")"
            default: return "· \(eventType)"
            }
        }()
        return Text(text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(DesignSystem.Colors.pencil)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 1)
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
    let activeServerId: UUID?
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
                guard !channel.isEmpty else { return }
                let sid = activeServerId ?? servers.first?.id
                guard let sid = sid else { return }
                let ch = channel.hasPrefix("#") ? channel : "#\(channel)"
                onJoin(ch, sid)
                channel = ""
            }
            .font(DesignSystem.Fonts.caption)
            .disabled(channel.isEmpty)
        }
    }
}
