import SwiftUI

// MARK: - Broadcast Picker

struct BroadcastPicker: View {
    let manager: IRCChannelManager
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<ChannelHandle> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Select All") { selected = Set(manager.channels) }
                    Button("Deselect All") { selected = [] }
                }

                Section("Channels") {
                    ForEach(manager.channels) { ch in
                        Button {
                            if selected.contains(ch) { selected.remove(ch) }
                            else { selected.insert(ch) }
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(ch) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(ch) ? DesignSystem.Colors.signal : DesignSystem.Colors.pencil)
                                Text(ch.name)
                                    .foregroundStyle(DesignSystem.Colors.ink)
                                Spacer()
                                Text(ch.serverHost)
                                    .font(DesignSystem.Fonts.data(10))
                                    .foregroundStyle(DesignSystem.Colors.pencil)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Broadcast to...")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") {
                        manager.broadcastTargets = selected
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
