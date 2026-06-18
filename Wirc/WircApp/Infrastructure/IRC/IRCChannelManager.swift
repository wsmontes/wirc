import Foundation
import os.log

/// Lightweight handle for a joined IRC channel.
struct ChannelHandle: Identifiable, Hashable, Codable {
    let serverId: UUID
    let serverHost: String
    let name: String
    var userCount: Int
    var lastPreview: String?
    var id: String { "\(serverId)|\(name)" }
}

/// Windowed message manager for the Channel Deck — @MainActor for UI safety.
@Observable
@MainActor
final class IRCChannelManager {

    var channels: [ChannelHandle] = []
    var activeChannel: ChannelHandle?
    var isAllMode: Bool { activeChannel == nil }
    var visibleMessages: [WOMObject] = []
    var broadcastTargets: Set<ChannelHandle> = []
    private(set) var isLoadingOlder = false
    private let store: WOMStore
    private var oldestVisibleTimestamp: Date?

    init(store: WOMStore) {
        self.store = store
    }

    // MARK: - Channel management

    func refreshChannelList(
        servers: [IRCConnectionConfig],
        joinedChannels: [UUID: [String]],
        channelUsers: [String: [AppState.ChannelUser]]
    ) {
        var newChannels: [ChannelHandle] = []
        for server in servers {
            guard let names = joinedChannels[server.id] else { continue }
            for name in names {
                let key = "\(server.host)|\(name.lowercased())"
                let count = channelUsers[key]?.count ?? 0
                var handle = ChannelHandle(serverId: server.id, serverHost: server.host, name: name, userCount: count)
                if let existing = channels.first(where: { $0.id == handle.id }) {
                    handle.lastPreview = existing.lastPreview
                }
                newChannels.append(handle)
            }
        }
        channels = newChannels
    }

    func setActiveChannel(_ channel: ChannelHandle?) {
        activeChannel = channel
        oldestVisibleTimestamp = nil
        Task { await loadMessages() }
    }

    // MARK: - Message loading

    func loadMessages() async {
        do {
            let all = try await store.all()
            let filtered: [WOMObject]

            if let ch = activeChannel {
                filtered = all.filter { obj in
                    obj.type.contains("wom:Message") &&
                    obj.data["server"] == ch.serverHost &&
                    obj.data["channel"] == ch.name
                }
            } else {
                let channelIds = Set(channels.map { $0.id })
                filtered = all.filter { obj in
                    guard obj.type.contains("wom:Message") else { return false }
                    guard let server = obj.data["server"],
                          let channel = obj.data["channel"] else { return false }
                    return channelIds.contains("\(server)|\(channel)") ||
                           channelIds.contains(where: { $0.hasSuffix("|\(channel)") })
                }
            }

            let sorted = filtered.sorted { $0.createdAt > $1.createdAt }
            visibleMessages = Array(sorted.prefix(200))
            oldestVisibleTimestamp = visibleMessages.last?.createdAt
        } catch {
            os_log(.error, "IRCChannelManager.loadMessages failed: %{public}@", error.localizedDescription)
        }
    }

    func loadOlderMessages() async {
        guard !isLoadingOlder, let oldest = oldestVisibleTimestamp else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }

        do {
            let all = try await store.all()
            let filtered: [WOMObject]

            if let ch = activeChannel {
                filtered = all.filter { obj in
                    obj.type.contains("wom:Message") &&
                    obj.data["server"] == ch.serverHost &&
                    obj.data["channel"] == ch.name &&
                    obj.createdAt < oldest
                }
            } else {
                let channelIds = Set(channels.map { $0.id })
                filtered = all.filter { obj in
                    guard obj.type.contains("wom:Message"), obj.createdAt < oldest else { return false }
                    guard let server = obj.data["server"],
                          let channel = obj.data["channel"] else { return false }
                    return channelIds.contains("\(server)|\(channel)") ||
                           channelIds.contains(where: { $0.hasSuffix("|\(channel)") })
                }
            }

            let older = filtered.sorted { $0.createdAt > $1.createdAt }.prefix(50)
            visibleMessages.append(contentsOf: older)
            oldestVisibleTimestamp = visibleMessages.last?.createdAt
        } catch {
            os_log(.error, "IRCChannelManager.loadOlderMessages failed: %{public}@", error.localizedDescription)
        }
    }

    func updatePreview(for channelId: String, text: String) {
        guard let idx = channels.firstIndex(where: { $0.id == channelId }) else { return }
        channels[idx].lastPreview = String(text.prefix(80))
    }

    var hasBroadcastTargets: Bool { !broadcastTargets.isEmpty }
}
