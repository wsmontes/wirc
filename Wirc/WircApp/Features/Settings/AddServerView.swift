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

    private var portBinding: Binding<Int> {
        Binding(
            get: { port },
            set: { port = max(1, min(65535, $0)) }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Display Name", text: $name)
                    TextField("Host (e.g. irc.libera.chat)", text: $host)
                    HStack {
                        Text("Port")
                        TextField("6667", value: portBinding, format: .number)
                            .keyboardType(.numberPad)
                    }
                    Toggle("Use TLS/SSL", isOn: $useTLS)
                    TextField("Password (optional)", text: $password)
                }

                Section("Identity") {
                    TextField("Nickname", text: $nickname)
                    TextField("Username (optional)", text: $username)
                    TextField("Real Name (optional)", text: $realName)
                }

                Section("Auto-join") {
                    TextField("Channels (comma-separated, e.g. #general,#dev)", text: $autoJoinChannels)
                }
            }
            .navigationTitle("Add Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(host.isEmpty || nickname.isEmpty)
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
