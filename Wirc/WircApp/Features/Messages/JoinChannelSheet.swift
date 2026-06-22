import SwiftUI

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
                        ForEach(appState.irc.servers) { server in
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
