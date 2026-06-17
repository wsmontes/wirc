import SwiftUI

struct ConversationListView: View {
    @Environment(AppState.self) private var appState
    @State private var showJoinSheet = false
    @State private var selectedServerId: UUID?
    @State private var joinChannelName = ""

    var body: some View {
        List {
            ForEach(appState.servers) { server in
                Section {
                    let status = appState.connectionStates[server.id] ?? .disconnected
                    HStack {
                        Circle()
                            .fill(statusColor(status))
                            .frame(width: 8, height: 8)
                        Text(server.host)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if case .online = status {
                            Button {
                                selectedServerId = server.id
                                joinChannelName = ""
                                showJoinSheet = true
                            } label: {
                                Image(systemName: "plus.circle")
                                    .font(.caption)
                            }
                        }
                    }

                    let conversations = appState.conversations(forServer: server.host)
                    if conversations.isEmpty {
                        HStack {
                            Text("No channels joined")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                    } else {
                        ForEach(conversations) { conv in
                            NavigationLink(value: ChatDestination(serverId: server.id, serverHost: server.host, conversation: conv)) {
                                HStack {
                                    Image(systemName: icon(for: conv))
                                        .foregroundStyle(.secondary)
                                    Text(conv.name)
                                    Spacer()
                                    if case .channel(let ch) = conv {
                                        let key = "\(server.host)|\(ch.lowercased())"
                                        let userCount = appState.channelUsers[key]?.count ?? 0
                                        if userCount > 0 {
                                            Text("\(userCount)")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color(.systemGray5))
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text(server.name.isEmpty ? server.host : server.name)
                }
            }
        }
        .navigationDestination(for: ChatDestination.self) { dest in
            MessageView(serverId: dest.serverId, serverHost: dest.serverHost, conversation: dest.conversation)
        }
        .overlay {
            if appState.servers.isEmpty {
                ContentUnavailableView(
                    "No Servers",
                    systemImage: "server.rack",
                    description: Text("Add an IRC server in Settings to start chatting.")
                )
            }
        }
        .sheet(isPresented: $showJoinSheet) {
            JoinChannelSheet(serverId: $selectedServerId, channel: $joinChannelName)
        }
    }

    private func statusColor(_ status: AppState.ConnectionStatus) -> Color {
        switch status {
        case .disconnected: return .gray
        case .connecting: return .orange
        case .online: return .green
        }
    }

    private func icon(for conv: AppState.Conversation) -> String {
        switch conv {
        case .channel: return "number"
        case .dm: return "person"
        }
    }
}

struct ChatDestination: Hashable {
    let serverId: UUID
    let serverHost: String
    let conversation: AppState.Conversation
}

struct JoinChannelSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Binding var serverId: UUID?
    @Binding var channel: String

    var body: some View {
        NavigationStack {
            Form {
                TextField("#channel", text: $channel)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
            }
            .navigationTitle("Join Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        if let id = serverId, !channel.isEmpty {
                            appState.joinChannel(channel, serverId: id)
                        }
                        dismiss()
                    }
                    .disabled((serverId == nil) || channel.isEmpty)
                }
            }
        }
        .presentationDetents([.height(150)])
    }
}
