import SwiftUI

// MARK: - Chat Route (simple, stable)

enum ChatRoute: Hashable {
    case userChannel(serverId: UUID, serverHost: String, channel: String)
    case globalChannel(serverHost: String, serverPort: Int, serverUseTLS: Bool, channel: String)
}

// MARK: - Conversation List View

struct ConversationListView: View {
    @Environment(AppState.self) private var appState
    @State private var navPath = NavigationPath()
    @State private var showJoinSheet = false
    @State private var selectedServerId: UUID?
    @State private var joinChannel = ""

    var body: some View {
        NavigationStack(path: $navPath) {
            List {
                scanAllButton
                if !appState.irc.orchestrator.globalChannels.isEmpty { orchestratorChannels }
                userServers
            }
            .navigationTitle("Chat")
            .navigationDestination(for: ChatRoute.self) { route in
                destination(for: route)
            }
            .sheet(isPresented: $showJoinSheet) {
                JoinSheet(serverId: $selectedServerId, channel: $joinChannel)
            }
        }
    }

    // MARK: - Scan All Button

    private var scanAllButton: some View {
        Section {
            Button { appState.irc.orchestrator.startScan() } label: {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        if appState.irc.orchestrator.isScanning {
                            ProgressView().scaleEffect(1.5)
                            Text(appState.irc.orchestrator.scanProgress).font(.headline).multilineTextAlignment(.center)
                        } else if !appState.irc.orchestrator.globalChannels.isEmpty {
                            Image(systemName: "globe.americas.fill").font(.largeTitle).foregroundStyle(DesignSystem.Colors.signal)
                            Text("\(appState.irc.orchestrator.globalChannels.count) channels").font(.headline)
                            Text("Tap to re-scan all \(SuggestedServersLoader.servers.count) servers").font(.caption).foregroundStyle(DesignSystem.Colors.pencil)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right").font(.largeTitle).foregroundStyle(DesignSystem.Colors.signal)
                            Text("Connect All Networks").font(.headline)
                            Text("Scans \(SuggestedServersLoader.servers.count) IRC servers for channels").font(.caption).foregroundStyle(DesignSystem.Colors.pencil)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 24)
            }
        }
    }

    // MARK: - Orchestrator Channels

    private var orchestratorChannels: some View {
        Section("All Servers · \(appState.irc.orchestrator.globalChannels.count) channels") {
            ForEach(appState.irc.orchestrator.globalChannels.prefix(1000)) { gc in
                Button {
                    navPath.append(ChatRoute.globalChannel(
                        serverHost: gc.serverHost,
                        serverPort: gc.serverPort,
                        serverUseTLS: gc.serverUseTLS,
                        channel: gc.name
                    ))
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(gc.name).font(.body).lineLimit(1)
                            Text(gc.topic).font(.caption).foregroundStyle(DesignSystem.Colors.pencil).lineLimit(1)
                            Text(gc.serverName).font(.caption2).foregroundStyle(DesignSystem.Colors.signal)
                        }
                        Spacer()
                        Text("\(gc.users)").font(.caption).foregroundStyle(DesignSystem.Colors.signal)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(.systemGray6)).clipShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: - User Configured Servers

    private var userServers: some View {
        ForEach(appState.irc.servers) { server in
            Section {
                HStack {
                    Circle().fill(dot(appState.irc.connectionStates[server.id] ?? .disconnected)).frame(width: 8, height: 8)
                    Text(server.host).font(.caption).foregroundStyle(DesignSystem.Colors.pencil)
                    Spacer()
                    if case .online = appState.irc.connectionStates[server.id] ?? .disconnected {
                        Button {
                            selectedServerId = server.id; joinChannel = ""; showJoinSheet = true
                        } label: { Image(systemName: "plus.circle").font(.caption) }
                    }
                }
                let list = appState.irc.conversations(forServer: server.host)
                if list.isEmpty {
                    Text("No channels joined").font(.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(list) { conv in
                        NavigationLink(value: ChatRoute.userChannel(
                            serverId: server.id, serverHost: server.host, channel: conv.name
                        )) {
                            HStack {
                                Image(systemName: "number").foregroundStyle(DesignSystem.Colors.pencil)
                                Text(conv.name)
                                Spacer()
                                if case .channel(let ch) = conv {
                                    let k = "\(server.host)|\(ch.lowercased())"
                                    if let c = appState.irc.channelUsers[k]?.count, c > 0 {
                                        Text("\(c)").font(.caption2).foregroundStyle(.tertiary)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color(.systemGray5)).clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }
                }
            } header: { Text(server.name.isEmpty ? server.host : server.name) }
        }
    }

    // MARK: - Destination

    @ViewBuilder
    private func destination(for route: ChatRoute) -> some View {
        switch route {
        case .userChannel(let serverId, let host, let channel):
            MessageView(serverId: serverId, serverHost: host, conversation: .channel(channel))
        case .globalChannel(let host, let port, let useTLS, let channel):
            GlobalJoinView(host: host, port: port, useTLS: useTLS, channel: channel)
        }
    }

    private func dot(_ s: IRCManager.ConnectionStatus) -> Color {
        switch s { case .disconnected: .gray; case .connecting: .orange; case .online: .green }
    }
}

// MARK: - Global Join View

struct GlobalJoinView: View {
    @Environment(AppState.self) private var appState
    let host: String; let port: Int; let useTLS: Bool; let channel: String
    @State private var serverId: UUID?

    var body: some View {
        Group {
            if let sid = serverId {
                MessageView(serverId: sid, serverHost: host, conversation: .channel(channel))
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Connecting to \(host)...").font(.headline)
                    Text(channel).font(.caption).foregroundStyle(DesignSystem.Colors.pencil)
                }
                .onAppear { connect() }
            }
        }
    }

    private func connect() {
        let id: UUID
        if let existing = appState.irc.servers.first(where: { $0.host == host && $0.port == port }) {
            id = existing.id
        } else {
            let cfg = IRCConnectionConfig(
                name: host, host: host, port: port, useTLS: useTLS,
                nickname: "virc_\(Int.random(in: 100...999))",
                autoJoinChannels: []
            )
            appState.irc.servers.append(cfg)
            id = cfg.id
        }
        serverId = id
        appState.connectAndJoin(channel: channel, serverId: id)
    }
}

// MARK: - Join Sheet

struct JoinSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Binding var serverId: UUID?
    @Binding var channel: String

    var body: some View {
        NavigationStack {
            Form {
                TextField("#channel", text: $channel).autocapitalization(.none).autocorrectionDisabled()
            }
            .navigationTitle("Join Channel").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        if let id = serverId, !channel.isEmpty { appState.irc.joinChannel(channel, serverId: id) }
                        dismiss()
                    }.disabled(serverId == nil || channel.isEmpty)
                }
            }
        }.presentationDetents([.height(150)])
    }
}
