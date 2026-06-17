import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showingAddServer = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(appState.servers) { server in
                    ServerRow(server: server)
                }
                .onDelete { indexSet in
                    for idx in indexSet {
                        let server = appState.servers[idx]
                        appState.disconnect(from: server.id)
                    }
                    appState.servers.remove(atOffsets: indexSet)
                }

                Section {
                    NavigationLink {
                        DebugView()
                    } label: {
                        Label("Debug", systemImage: "wrench.and.screwdriver")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAddServer = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddServer) {
                AddServerView { config in
                    appState.servers.append(config)
                }
            }
            .overlay {
                if appState.servers.isEmpty {
                    ContentUnavailableView(
                        "No Servers",
                        systemImage: "server.rack",
                        description: Text("Tap + to add an IRC server.")
                    )
                }
            }
        }
    }
}

struct ServerRow: View {
    @Environment(AppState.self) private var appState
    let server: IRCConnectionConfig

    private var status: AppState.ConnectionStatus {
        appState.connectionStates[server.id] ?? .disconnected
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(server.name.isEmpty ? server.host : server.name)
                    .font(.headline)
                Text("\(server.host):\(server.port) as \(server.nickname)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            Button(action: toggleConnection) {
                Text(status == .online ? "Disconnect" : "Connect")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch status {
        case .disconnected: return .gray
        case .connecting: return .orange
        case .online: return .green
        }
    }

    private func toggleConnection() {
        switch status {
        case .disconnected:
            appState.connect(to: server.id)
        case .connecting, .online:
            appState.disconnect(from: server.id)
        }
    }
}
