import SwiftUI
import Observation

/// All IRC-related state and logic, extracted from AppState.
@Observable
@MainActor
final class IRCManager {
    // MARK: - Server configs
    var servers: [IRCConnectionConfig] = [] {
        didSet { saveServers() }
    }

    // MARK: - IRC Clients
    var clients: [UUID: IRCClient] = [:]

    // MARK: - Connection status
    var connectionStates: [UUID: ConnectionStatus] = [:]

    // MARK: - Channel state (keyed by "server|#channel")
    var channelTopics: [String: ChannelTopic] = [:]
    var channelUsers: [String: [ChannelUser]] = [:]
    var joinedChannels: [UUID: [String]] = [:]
    var serverChannelList: [UUID: [ListedChannel]] = [:]
    var isListing: [UUID: Bool] = [:]

    // MARK: - Sub-managers
    let automation = IRCAutomation()
    let channelManager: IRCChannelManager
    let orchestrator = ServerOrchestrator(servers: SuggestedServersLoader.servers)

    // MARK: - WOM pipeline
    private let ircToWOM = IRCToWOMAdapter()
    var onWOMObjects: (([WOMObject]) -> Void)?

    // MARK: - Types
    enum ConnectionStatus: Hashable { case disconnected, connecting, online }

    struct ChannelTopic: Hashable {
        var text: String; var setBy: String?; var setAt: Date?
    }

    struct ChannelUser: Hashable, Identifiable {
        var id: String { nick }; let nick: String; let prefix: String
    }

    struct ListedChannel: Hashable, Identifiable {
        var id: String { name }; let name: String; let users: Int; let topic: String
    }

    // MARK: - Init
    init(store: WOMStore) {
        channelManager = IRCChannelManager(store: store)
        loadServers()
    }

    // MARK: - Persistence
    private let serversKey = "wirc.servers"

    private func saveServers() {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        UserDefaults.standard.set(data, forKey: serversKey)
    }

    private func loadServers() {
        guard let data = UserDefaults.standard.data(forKey: serversKey),
              let saved = try? JSONDecoder().decode([IRCConnectionConfig].self, from: data) else { return }
        servers = saved
    }

    // MARK: - Helpers
    func client(for id: UUID) -> IRCClient? { clients[id] }
    func config(for id: UUID) -> IRCConnectionConfig? { servers.first(where: { $0.id == id }) }
    func localNick(for id: UUID) -> String { servers.first(where: { $0.id == id })?.nickname ?? "user" }
    func channelKey(serverId: UUID, channel: String) -> String {
        "\(servers.first(where: { $0.id == serverId })?.host ?? "")|\(channel.lowercased())"
    }

    // MARK: - Connection
    func connect(to configId: UUID) {
        guard let config = servers.first(where: { $0.id == configId }) else { return }
        connectionStates[configId] = .connecting
        let client = IRCClient(config: config)
        clients[configId] = client
        client.onEvent = { [weak self] event in
            Task { @MainActor in self?.handleEvent(event, serverId: configId) }
        }
        client.connect()
    }

    func disconnect(from configId: UUID) {
        clients[configId]?.disconnect()
        clients[configId] = nil
        connectionStates[configId] = .disconnected
        automation.onManualDisconnect(serverId: configId)
    }

    // MARK: - Channels
    func joinChannel(_ channel: String, serverId: UUID) {
        let ch = channel.hasPrefix("#") ? channel : "#\(channel)"
        clients[serverId]?.join(channel: ch)
        if !(joinedChannels[serverId]?.contains(ch) ?? false) {
            joinedChannels[serverId, default: []].append(ch)
        }
    }

    func partChannel(_ channel: String, serverId: UUID) {
        let ch = channel.hasPrefix("#") ? channel : "#\(channel)"
        clients[serverId]?.part(channel: ch)
        let key = channelKey(serverId: serverId, channel: ch)
        channelUsers.removeValue(forKey: key)
        joinedChannels[serverId]?.removeAll { $0 == ch }
    }

    func fetchChannelList(serverId: UUID) {
        guard let client = clients[serverId] else { return }
        serverChannelList[serverId] = []
        isListing[serverId] = true
        client.listChannels()
    }

    // MARK: - Conversations
    func conversations(forServer server: String) -> [Conversation] {
        var channelSet = Set<String>()
        for (sId, channels) in joinedChannels {
            guard let cfg = servers.first(where: { $0.id == sId }), cfg.host == server else { continue }
            for ch in channels { channelSet.insert(ch) }
        }
        return channelSet.map { .channel($0) }.sorted { $0.name < $1.name }
    }

    enum Conversation: Identifiable, Hashable {
        case channel(String)
        var id: String { name }
        var name: String {
            switch self { case .channel(let n): return n }
        }
    }

    // MARK: - Event Handling
    func handleEvent(_ event: IRCEvent, serverId: UUID) {
        guard let config = servers.first(where: { $0.id == serverId }) else { return }

        switch event {
        case .connected:
            connectionStates[serverId] = .online
            if let client = clients[serverId] {
                automation.autoIdentify(serverHost: config.host, client: client)
            }
            if let pending = joinedChannels[serverId] {
                for ch in pending { clients[serverId]?.join(channel: ch) }
            }
            for ch in config.autoJoinChannels {
                let c = ch.hasPrefix("#") ? ch : "#\(ch)"
                if !(joinedChannels[serverId]?.contains(c) ?? false) {
                    joinedChannels[serverId, default: []].append(c)
                    clients[serverId]?.join(channel: c)
                }
            }
        case .disconnected(let reason):
            connectionStates[serverId] = .disconnected
            channelUsers.removeAll()
            if reason != nil { automation.onDisconnect(serverId: serverId) }
        case .names(let channel, let names):
            let chList = joinedChannels[serverId] ?? []
            automation.recordJoinedChannels(serverId: serverId, channels: chList)
            let users = names.map { raw -> ChannelUser in
                let prefixChars: Set<Character> = ["@", "+", "&", "~", "%"]
                if let first = raw.first, prefixChars.contains(first) {
                    return ChannelUser(nick: String(raw.dropFirst()), prefix: String(first))
                }
                return ChannelUser(nick: raw, prefix: "")
            }
            channelUsers[channelKey(serverId: serverId, channel: channel)] = users
        case .topic(let channel, let topic):
            var ct = channelTopics[channelKey(serverId: serverId, channel: channel)] ?? ChannelTopic(text: "")
            ct.text = topic; channelTopics[channelKey(serverId: serverId, channel: channel)] = ct
        case .topicWho(let channel, let setBy, let setAt):
            var ct = channelTopics[channelKey(serverId: serverId, channel: channel)] ?? ChannelTopic(text: "")
            ct.setBy = setBy; ct.setAt = setAt; channelTopics[channelKey(serverId: serverId, channel: channel)] = ct
        case .join(let channel, let nick):
            if !(joinedChannels[serverId]?.contains(channel) ?? false) {
                joinedChannels[serverId, default: []].append(channel)
            }
            let key = channelKey(serverId: serverId, channel: channel)
            if !(channelUsers[key]?.contains(where: { $0.nick == nick }) ?? false) {
                channelUsers[key, default: []].append(ChannelUser(nick: nick, prefix: ""))
            }
        case .part(let channel, let nick, _):
            channelUsers[channelKey(serverId: serverId, channel: channel)]?.removeAll { $0.nick == nick }
        case .quit(let nick, _):
            for (key, _) in channelUsers { channelUsers[key]?.removeAll { $0.nick == nick } }
        case .nickChange(let oldNick, let newNick):
            for (key, _) in channelUsers {
                if let idx = channelUsers[key]?.firstIndex(where: { $0.nick == oldNick }) {
                    channelUsers[key]?[idx] = ChannelUser(nick: newNick, prefix: channelUsers[key]![idx].prefix)
                }
            }
        case .kick(let channel, let nick, _, _):
            channelUsers[channelKey(serverId: serverId, channel: channel)]?.removeAll { $0.nick == nick }
        case .listStart: serverChannelList[serverId] = []; isListing[serverId] = true
        case .listItem(let channel, let users, let topic):
            serverChannelList[serverId, default: []].append(ListedChannel(name: channel, users: users, topic: topic))
        case .listEnd: isListing[serverId] = false
        default: break
        }

        // Convert IRC event to WOM objects and emit
        let objects = ircToWOM.convert(event, config: config)
        if !objects.isEmpty {
            onWOMObjects?(objects)
        }
    }
}
