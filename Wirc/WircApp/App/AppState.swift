import SwiftUI
import Observation

@Observable
@MainActor
final class AppState {
    // MARK: - Server configs
    var servers: [IRCConnectionConfig] = [] {
        didSet { saveServers() }
    }

    // MARK: - WOM Store
    let store: WOMStore = InMemoryWOMStore()

    // MARK: - IRC Clients
    private var clients: [UUID: IRCClient] = [:]

    // MARK: - Connection status
    var connectionStates: [UUID: ConnectionStatus] = [:]

    // MARK: - Channel state (keyed by "server|#channel")
    var channelTopics: [String: ChannelTopic] = [:]
    var channelUsers: [String: [ChannelUser]] = [:]
    var joinedChannels: [UUID: [String]] = [:]  // serverId → [channel names]

    // MARK: - Debug logs
    var rawEvents: [DebugRawEvent] = []
    var womObjects: [WOMObject] = []

    // MARK: - Adapters
    private let ircToWOM = IRCToWOMAdapter()

    enum ConnectionStatus: Hashable {
        case disconnected
        case connecting
        case online
    }

    struct ChannelTopic: Hashable {
        var text: String
        var setBy: String?
        var setAt: Date?
    }

    struct ChannelUser: Hashable, Identifiable {
        var id: String { nick }
        var nick: String
        var prefix: String  // "@" op, "+" voice, "" normal
    }

    struct DebugRawEvent: Identifiable {
        let id = UUID()
        let timestamp: Date
        let server: String
        let raw: String
        let parsedAs: String
    }

    // MARK: - Init

    init() { loadServers() }

    // MARK: - Server persistence

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
    }

    // MARK: - Channel operations

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

    // MARK: - Messages

    func sendMessage(_ text: String, channel: String, serverId: UUID) {
        guard let config = servers.first(where: { $0.id == serverId }) else { return }
        let objectId = WOMIDGenerator.generate(type: "message")
        let womObj = WOMObject(
            id: objectId,
            type: ["wom:Message"],
            createdAt: Date(),
            attributedTo: WOMReference(id: "local:user", type: ["wom:Person"], name: config.nickname),
            content: WOMContent(format: "text/plain", text: text),
            data: ["network": "irc", "server": config.host, "channel": channel],
            provenance: WOMProvenance(origin: "localUser", createdAt: Date(), confidence: 1.0, reviewStatus: "none")
        )
        clients[serverId]?.sendMessage(text, to: channel)
        Task {
            try? await store.save(womObj)
            womObjects.append(womObj)
        }
    }

    // MARK: - Event handling

    private func handleEvent(_ event: IRCEvent, serverId: UUID) {
        guard let config = servers.first(where: { $0.id == serverId }) else { return }

        switch event {
        case .connected:
            connectionStates[serverId] = .online
            // Track auto-join channels
            if let cfg = servers.first(where: { $0.id == serverId }) {
                for ch in cfg.autoJoinChannels {
                    if !(joinedChannels[serverId]?.contains(ch) ?? false) {
                        joinedChannels[serverId, default: []].append(ch)
                    }
                }
            }
        case .disconnected:
            connectionStates[serverId] = .disconnected
            channelUsers.removeAll()
            joinedChannels.removeValue(forKey: serverId)
        case .rawLine(let line):
            rawEvents.append(DebugRawEvent(timestamp: Date(), server: config.host, raw: line, parsedAs: "raw"))
        case .error(let msg):
            rawEvents.append(DebugRawEvent(timestamp: Date(), server: config.host, raw: msg, parsedAs: "error"))
        case .names(let channel, let names):
            let users = names.map { raw -> ChannelUser in
                let prefixChars: Set<Character> = ["@", "+", "&", "~", "%"]
                if let first = raw.first, prefixChars.contains(first) {
                    return ChannelUser(nick: String(raw.dropFirst()), prefix: String(first))
                }
                return ChannelUser(nick: raw, prefix: "")
            }
            channelUsers[channelKey(serverId: serverId, channel: channel)] = users
        case .topic(let channel, let topic):
            let key = channelKey(serverId: serverId, channel: channel)
            var ct = channelTopics[key] ?? ChannelTopic(text: "")
            ct.text = topic
            channelTopics[key] = ct
        case .topicWho(let channel, let setBy, let setAt):
            let key = channelKey(serverId: serverId, channel: channel)
            var ct = channelTopics[key] ?? ChannelTopic(text: "")
            ct.setBy = setBy
            ct.setAt = setAt
            channelTopics[key] = ct
        case .join(let channel, let nick):
            let key = channelKey(serverId: serverId, channel: channel)
            // Track joined channel
            if !(joinedChannels[serverId]?.contains(channel) ?? false) {
                joinedChannels[serverId, default: []].append(channel)
            }
            // Add user
            if !(channelUsers[key]?.contains(where: { $0.nick == nick }) ?? false) {
                let user = ChannelUser(nick: nick, prefix: "")
                channelUsers[key, default: []].append(user)
            }
        case .part(let channel, let nick, _):
            let key = channelKey(serverId: serverId, channel: channel)
            channelUsers[key]?.removeAll { $0.nick == nick }
        case .quit(let nick, _):
            for (key, _) in channelUsers {
                channelUsers[key]?.removeAll { $0.nick == nick }
            }
        case .nickChange(let oldNick, let newNick):
            for (key, _) in channelUsers {
                if let idx = channelUsers[key]?.firstIndex(where: { $0.nick == oldNick }) {
                    channelUsers[key]?[idx] = ChannelUser(nick: newNick, prefix: channelUsers[key]![idx].prefix)
                }
            }
        case .kick(let channel, let nick, _, _):
            let key = channelKey(serverId: serverId, channel: channel)
            channelUsers[key]?.removeAll { $0.nick == nick }
        default:
            break
        }

        // Convert to WOM and save
        let objects = ircToWOM.convert(event, config: config)
        if !objects.isEmpty {
            Task {
                try? await store.saveMany(objects)
                womObjects.append(contentsOf: objects)
            }
        }
    }

    // MARK: - Queries

    func messagesFor(server: String, channel: String) -> [WOMObject] {
        womObjects.filter { obj in
            guard obj.type.contains("wom:Message") else { return false }
            return obj.data["server"] == server && obj.data["channel"] == channel
        }.sorted { $0.createdAt < $1.createdAt }
    }

    func systemEventsFor(server: String, channel: String) -> [WOMObject] {
        womObjects.filter { obj in
            guard obj.type.contains("wom:SystemEvent") else { return false }
            guard obj.data["server"] == server else { return false }
            let evtChannel = obj.data["channel"] ?? ""
            let evtNick = obj.data["nick"] ?? ""
            return evtChannel == channel || !evtChannel.isEmpty
        }.sorted { $0.createdAt < $1.createdAt }
    }

    func conversations(forServer server: String) -> [Conversation] {
        var channelSet = Set<String>()

        // Include joined channels (even if empty of messages)
        for (serverId, channels) in joinedChannels {
            guard let cfg = servers.first(where: { $0.id == serverId }),
                  cfg.host == server else { continue }
            for ch in channels {
                channelSet.insert(ch)
            }
        }

        // Also include channels that have messages
        for obj in womObjects where obj.type.contains("wom:Message") && obj.data["server"] == server {
            if let channel = obj.data["channel"], !channel.isEmpty {
                channelSet.insert(channel)
            }
        }

        return channelSet.map { .channel($0) }.sorted { $0.name < $1.name }
    }

    var feedObjects: [WOMObject] {
        womObjects.filter { $0.type.contains("wom:Post") }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func channelKey(serverId: UUID, channel: String) -> String {
        let server = servers.first(where: { $0.id == serverId })?.host ?? ""
        return "\(server)|\(channel.lowercased())"
    }

    enum Conversation: Identifiable, Hashable {
        case channel(String)
        case dm(String)
        var id: String { name }
        var name: String {
            switch self {
            case .channel(let n): return n
            case .dm(let n): return n
            }
        }
    }
}
