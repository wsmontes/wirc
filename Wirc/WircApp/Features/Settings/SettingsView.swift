import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showingAddServer = false
    @State private var showingAddMastodon = false

    var body: some View {
        NavigationStack {
            List {
                // IRC Servers
                Section("IRC Servers") {
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
                    Button { showingAddServer = true } label: {
                        Label("Add IRC Server", systemImage: "plus")
                    }
                }

                // Mastodon Accounts
                Section("Mastodon") {
                    ForEach(appState.mastodonAccounts) { acct in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(acct.name).font(.subheadline)
                                Text(acct.instanceURL).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                appState.refreshMastodonFeed(accountId: acct.id)
                            } label: {
                                Image(systemName: "arrow.clockwise").font(.caption)
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

                // Debug
                Section {
                    NavigationLink {
                        DebugView()
                    } label: {
                        Label("Debug", systemImage: "wrench.and.screwdriver")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingAddServer) {
                AddServerView { config in appState.servers.append(config) }
            }
            .sheet(isPresented: $showingAddMastodon) {
                AddMastodonView { name, url, token in
                    appState.addMastodonAccount(name: name, instanceURL: url, token: token)
                }
            }
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
