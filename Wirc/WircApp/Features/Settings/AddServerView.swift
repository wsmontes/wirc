import SwiftUI

struct AddServerView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (IRCConnectionConfig) -> Void

    @State private var name = ""
    @State private var host = ""
    @State private var port = 6667
    @State private var useTLS = false
    @State private var nickname = ""
    @State private var username = ""
    @State private var realName = ""
    @State private var password = ""
    @State private var autoJoinChannels = ""
    @State private var showSuggested = false

    var body: some View {
        NavigationStack {
            Form {
                if !showSuggested {
                    serverForm
                } else {
                    suggestedList
                }
            }
            .scrollContentBackground(.hidden)
            .background(DesignSystem.Colors.page)
            .navigationTitle("Add Server")
            .navigationBarTitleDisplayMode(.inline)
            .tint(DesignSystem.Colors.signal)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if !showSuggested {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showSuggested = true } label: {
                            Image(systemName: "globe")
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(host.isEmpty || nickname.isEmpty)
                    }
                }
            }
        }
    }

    private var serverForm: some View {
        Group {
            Section("Server") {
                TextField("Display Name", text: $name)
                TextField("Host (e.g. irc.libera.chat)", text: $host)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                HStack {
                    Text("Port")
                    TextField("6667", value: Binding(get: { port }, set: { port = max(1, min(65535, $0)) }), format: .number)
                        .keyboardType(.numberPad)
                }
                Toggle("Use TLS/SSL", isOn: $useTLS)
                TextField("Password (optional)", text: $password)
            }

            Section("Identity") {
                TextField("Nickname", text: $nickname)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                TextField("Username (optional)", text: $username)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                TextField("Real Name (optional)", text: $realName)
            }

            Section("Auto-join") {
                TextField("Channels (comma-separated, e.g. #general,#dev)", text: $autoJoinChannels)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
            }
        }
    }

    private var suggestedList: some View {
        Group {
            Section {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                    Text("Tap a server to pre-fill the form, then set your nickname and Save.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Suggested Servers (\(SuggestedServersLoader.servers.count))") {
                ForEach(SuggestedServersLoader.servers) { server in
                    Button {
                        name = server.name
                        host = server.host
                        port = server.port
                        useTLS = server.useTLS
                        showSuggested = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(server.name)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Text("\(server.host):\(server.port) \(server.useTLS ? "🔒" : "") · \(server.description)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "arrow.right.circle")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
    }

    private func save() {
        let channels = autoJoinChannels
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let config = IRCConnectionConfig(
            name: name,
            host: host,
            port: port,
            useTLS: useTLS,
            nickname: nickname,
            username: username.isEmpty ? nil : username,
            realName: realName.isEmpty ? nil : realName,
            password: password.isEmpty ? nil : password,
            autoJoinChannels: channels
        )
        onSave(config)
        dismiss()
    }
}
