import SwiftUI

/// Server & Channel management sheet — add/remove servers, join/part channels, connect/disconnect.
struct IRCServerManagerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var showAddServer = false
    @State private var showJoinSheet = false
    @State private var joinChannel = ""
    @State private var joinServerId: UUID?

    var body: some View {
        NavigationStack {
            List {
                ForEach(appState.servers) { server in
                    Section {
                        // Server header
                        HStack {
                            Circle()
                                .fill(statusColor(appState.connectionStates[server.id] ?? .disconnected))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(server.name.isEmpty ? server.host : server.name)
                                    .font(.system(size: 15, weight: .medium))
                                Text("\(server.host):\(server.port) · \(server.nickname)")
                                    .font(DesignSystem.Fonts.data(10))
                                    .foregroundStyle(DesignSystem.Colors.pencil)
                            }
                        }

                        // Channel list
                        let conversations = appState.conversations(forServer: server.host)
                        ForEach(conversations) { conv in
                            HStack {
                                Text(conv.name)
                                    .font(DesignSystem.Fonts.data(13))
                                Spacer()
                                let key = keyFor(server: server, channel: conv.name)
                                let count = appState.channelUsers[key]?.count ?? 0
                                if count > 0 {
                                    Text("\(count)")
                                        .font(DesignSystem.Fonts.data(10))
                                        .foregroundStyle(DesignSystem.Colors.pencil)
                                }
                                Button {
                                    appState.partChannel(conv.name, serverId: server.id)
                                } label: {
                                    Image(systemName: "xmark.circle")
                                        .font(.caption)
                                        .foregroundStyle(DesignSystem.Colors.pencil)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Join channel button
                        Button {
                            joinServerId = server.id
                            joinChannel = ""
                            showJoinSheet = true
                        } label: {
                            Label("Join channel...", systemImage: "plus")
                                .font(DesignSystem.Fonts.caption())
                        }

                        // Connect/Disconnect + Remove
                        HStack {
                            Button(statusLabel(server.id)) {
                                toggleConnection(server.id)
                            }
                            .buttonStyle(.bordered)
                            .tint(statusTint(server.id))

                            Spacer()

                            Button("Remove", role: .destructive) {
                                appState.disconnect(from: server.id)
                                if let idx = appState.servers.firstIndex(where: { $0.id == server.id }) {
                                    appState.servers.remove(at: idx)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                // Add server
                Section {
                    Button {
                        showAddServer = true
                    } label: {
                        Label("Add Server...", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Servers & Channels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showAddServer) {
                AddServerView { config in
                    appState.servers.append(config)
                }
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
        }
    }

    private func keyFor(server: IRCConnectionConfig, channel: String) -> String {
        "\(server.host)|\(channel.lowercased())"
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
