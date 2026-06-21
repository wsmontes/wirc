import SwiftUI
import Observation
import BackgroundTasks
import os.log

/// Central coordinator. IRC state lives in `irc: IRCManager`, feed state in `feed: FeedManager`.
/// Keeps WOM store, Mastodon, debug, and cross-cutting adapters.
@Observable
@MainActor
final class AppState {

    // MARK: - Managers
    let irc: IRCManager
    let feed: FeedManager

    // MARK: - WOM Store
    let store: WOMStore = JSONFileStore()

    // MARK: - Debug logs
    var rawEvents: [DebugRawEvent] = [] {
        didSet { if rawEvents.count > 500 { rawEvents = Array(rawEvents.suffix(500)) } }
    }
    var womObjects: [WOMObject] = [] {
        didSet {
            // Cap in-memory objects to prevent unbounded growth
            if womObjects.count > 2000 {
                let dropped = womObjects.count - 2000
                os_log(.debug, "AppState: evicting %d objects from womObjects cap", dropped)
                womObjects = Array(womObjects.suffix(2000))
            }
            invalidateIndexes()
        }
    }

    // MARK: - Lazy indexes (rebuilt once per womObjects mutation, on-demand)
    private var _messagesByChannelKey: [String: [WOMObject]] = [:]
    private var _systemEventsByChannelKey: [String: [WOMObject]] = [:]
    private var _feedPosts: [WOMObject] = []
    private var indexesValid = false

    private func invalidateIndexes() { indexesValid = false }

    private func ensureIndexes() {
        guard !indexesValid else { return }
        var messages: [String: [WOMObject]] = [:]
        var systemEvents: [String: [WOMObject]] = [:]
        var posts: [WOMObject] = []

        for obj in womObjects {
            if obj.type.contains("wom:Message") {
                if let server = obj.data["server"], let channel = obj.data["channel"] {
                    let key = "\(server)|\(channel.lowercased())"
                    messages[key, default: []].append(obj)
                }
            }
            if obj.type.contains("wom:SystemEvent") {
                if let server = obj.data["server"] {
                    let channel = obj.data["channel"] ?? ""
                    let key = "\(server)|\(channel.lowercased())"
                    systemEvents[key, default: []].append(obj)
                }
            }
            if obj.type.contains("wom:Post") {
                posts.append(obj)
            }
        }

        // Sort each bucket once
        for key in messages.keys { messages[key]?.sort { $0.createdAt < $1.createdAt } }
        for key in systemEvents.keys { systemEvents[key]?.sort { $0.createdAt < $1.createdAt } }
        posts.sort { $0.createdAt > $1.createdAt }

        _messagesByChannelKey = messages
        _systemEventsByChannelKey = systemEvents
        _feedPosts = posts
        indexesValid = true
    }

    /// Pre-built messages index — O(1) lookup by channel key.
    var messagesByChannelKey: [String: [WOMObject]] {
        ensureIndexes()
        return _messagesByChannelKey
    }
    /// Pre-built system events index — O(1) lookup by channel key.
    var systemEventsByChannelKey: [String: [WOMObject]] {
        ensureIndexes()
        return _systemEventsByChannelKey
    }

    // MARK: - Mastodon
    var mastodonAccounts: [MastodonServerConfig] = [] { didSet { saveMastodonAccounts() } }
    private var mastodonClients: [UUID: MastodonClient] = [:]

    // MARK: - Adapters
    private let ircToWOM = IRCToWOMAdapter()

    // MARK: - Types
    struct DebugRawEvent: Identifiable {
        let id = UUID(); let timestamp: Date; let server: String; let raw: String; let parsedAs: String
    }

    // MARK: - Init
    init() {
        irc = IRCManager(store: store)
        feed = FeedManager()
        // Wire IRC events → WOM pipeline
        irc.onWOMObjects = { [weak self] objects in
            guard let self else { return }
            Task {
                try? await self.store.saveMany(objects)
                await MainActor.run {
                    self.womObjects.append(contentsOf: objects)
                    self.irc.channelManager.allObjects = self.womObjects
                    for obj in objects where obj.type.contains("wom:Message") {
                        if let s = obj.data["server"], let ch = obj.data["channel"] {
                            self.irc.channelManager.incrementUnread(for: "\(s)|\(ch.lowercased())")
                        }
                    }
                }
            }
        }
        loadMastodonAccounts()
        let loaded = DefaultFeedsLoader.loadIfEmpty(into: feed.subscriptionStore)
        // Load previously saved objects from disk first, then fetch new content.
        // Without this, every launch starts with an empty timeline and only shows
        // items published since the last session (favouring frequently-updated feeds).
        Task { [weak self] in
            guard let self else { return }
            // 1. Restore existing items from persistent store
            if let existing = try? await self.store.all(), !existing.isEmpty {
                await MainActor.run { self.womObjects = Array(existing.suffix(2000)) }
            }
            // 2. Fetch new items and append
            let allNew = await self.feed.refreshAllFeedsBatched(womStore: self.store)
            if !allNew.isEmpty {
                await MainActor.run { self.womObjects.append(contentsOf: allNew) }
            }
        }
    }

    // MARK: - IRC (delegates to IRCManager + saves WOM)
    func sendMessage(_ text: String, channel: String, serverId: UUID) {
        guard irc.automation.checkFlood(serverId: serverId) else { return }
        guard let config = irc.config(for: serverId) else { return }
        let objectId = WOMIDGenerator.generate(type: "message")
        let obj = WOMObject(
            id: objectId, type: ["wom:Message"], createdAt: Date(), schema: WOMSchema.message,
            attributedTo: WOMReference(id: "local:user", type: ["wom:Person"], name: config.nickname),
            content: WOMContent(format: "text/plain", text: text, language: "en"),
            data: ["network": "irc", "server": config.host, "channel": channel],
            provenance: .localUser(),
            governance: WOMGovernance(purpose: ["messaging"], adsUse: WOMAdsUse.notAllowed.rawValue, agentUse: "allowed", sharing: WOMSharing.groupOnly.rawValue, retention: "forever"),
            classification: WOMClassification(semanticType: "social.message", dataSubject: "local_user", origin: WOMOrigin.userProvided.rawValue, sensitivity: WOMDataSensitivity.personal.rawValue),
            bindings: WOMBindings(irc: WOMIRCBinding(server: config.host, channel: channel, nick: config.nickname))
        )
        irc.clients[serverId]?.sendMessage(text, to: channel)
        Task {
            try? await store.save(obj)
            womObjects.append(obj)
        }
    }

    func saveSentDM(text: String, to nick: String, server: String, serverId: UUID) {
        let objectId = WOMIDGenerator.generate(type: "message")
        let obj = WOMObject(
            id: objectId, type: ["wom:Message"], createdAt: Date(), schema: WOMSchema.message,
            attributedTo: WOMReference(id: "local:user", type: ["wom:Person"], name: irc.localNick(for: serverId)),
            content: WOMContent(format: "text/plain", text: text),
            data: ["network": "irc", "server": server, "recipient": nick, "visibility": "direct"],
            provenance: .localUser(),
            governance: WOMGovernance(purpose: ["messaging"], adsUse: WOMAdsUse.notAllowed.rawValue, agentUse: "allowed", sharing: WOMSharing.directRecipient.rawValue),
            bindings: WOMBindings(irc: WOMIRCBinding(server: server, nick: irc.localNick(for: serverId)))
        )
        Task { try? await store.save(obj); womObjects.append(obj) }
    }

    // MARK: - Event pipeline (IRC → WOM)
    func processIRCEvent(_ event: IRCEvent, serverId: UUID) {
        guard let config = irc.config(for: serverId) else { return }
        irc.handleEvent(event, serverId: serverId)

        switch event {
        case .rawLine(let line):
            rawEvents.append(DebugRawEvent(timestamp: Date(), server: config.host, raw: line, parsedAs: "raw"))
        case .error(let msg):
            rawEvents.append(DebugRawEvent(timestamp: Date(), server: config.host, raw: msg, parsedAs: "error"))
        default: break
        }

        let objects = ircToWOM.convert(event, config: config)
        if !objects.isEmpty {
            Task { try? await store.saveMany(objects); womObjects.append(contentsOf: objects) }
        }
    }

    // MARK: - Mastodon
    private let mastodonAccountsKey = "wirc.mastodonAccounts"
    private func saveMastodonAccounts() { if let d = try? JSONEncoder().encode(mastodonAccounts) { UserDefaults.standard.set(d, forKey: mastodonAccountsKey) } }
    private func loadMastodonAccounts() {
        guard let data = UserDefaults.standard.data(forKey: mastodonAccountsKey) else { return }
        if let accounts = try? JSONDecoder().decode([MastodonServerConfig].self, from: data) {
            mastodonAccounts = accounts
        }
    }

    func addMastodonAccount(name: String, instanceURL: String, token: String) {
        let account = MastodonServerConfig(id: UUID(), name: name, instanceURL: instanceURL, accessToken: token)
        mastodonAccounts.append(account)
    }
    func removeMastodonAccount(id: UUID) { mastodonAccounts.removeAll { $0.id == id }; mastodonClients.removeValue(forKey: id) }

    func refreshMastodonFeed(accountId: UUID) {
        guard let client = mastodonClients[accountId] ?? { if let acct = mastodonAccounts.first(where: { $0.id == accountId }) { let c = MastodonClient(config: acct); mastodonClients[accountId] = c; return c }; return nil }() else { return }
        feed.feedError = nil
        let adapter = MastodonToWOMAdapter(instanceURL: client.config.instanceURL)
        Task { @MainActor in
            do {
                let timeline = try await client.homeTimeline(limit: 40)
                for status in timeline {
                    let obj = adapter.convert(status: status)
                    try? await store.save(obj)
                    if !womObjects.contains(where: { $0.id == obj.id }) { womObjects.append(obj) }
                }
            } catch { feed.feedError = error.localizedDescription }
        }
    }

    func postToMastodon(_ text: String, accountId: UUID, visibility: String = "public") {
        guard let client = mastodonClients[accountId] else { return }
        Task { @MainActor in
            do {
                let status = try await client.postStatus(text, visibility: visibility)
                let adapter = MastodonToWOMAdapter(instanceURL: client.config.instanceURL)
                let obj = adapter.convert(status: status)
                var localObj = obj; localObj.provenance = .localUser()
                try? await store.save(localObj); womObjects.append(localObj)
            } catch { rawEvents.append(DebugRawEvent(timestamp: Date(), server: client.config.instanceURL, raw: error.localizedDescription, parsedAs: "mastodon_post_error")) }
        }
    }

    // MARK: - Feed delegations
    func addFeed(url: String, sourceType: FeedSourceType? = nil) async throws {
        let newObjects = try await feed.addFeed(url: url, sourceType: sourceType, womStore: store)
        womObjects.append(contentsOf: newObjects)
    }
    func removeFeed(_ sub: FeedSubscription) { feed.removeFeed(sub) }
    func discoverFeedURL(from url: String) async throws -> [String] { try await feed.discoverFeedURL(from: url) }
    func importOPML(data: Data) async throws -> Int { try await feed.importOPML(data: data) }
    func refreshAllFeeds() async {
        let newObjects = await feed.refreshAllFeedsBatched(womStore: store)
        womObjects.append(contentsOf: newObjects)
    }
    func scheduleNextRefresh() { feed.scheduleNextRefresh() }

    // MARK: - Convenience delegations (for old views)
    func connectAndJoin(channel: String, serverId: UUID) {
        let ch = channel.hasPrefix("#") ? channel : "#\(channel)"
        if !(irc.joinedChannels[serverId]?.contains(ch) ?? false) {
            irc.joinedChannels[serverId, default: []].append(ch)
        }
        switch irc.connectionStates[serverId] ?? .disconnected {
        case .online: irc.clients[serverId]?.join(channel: ch)
        case .connecting: break
        case .disconnected: irc.connect(to: serverId)
        }
    }

    func conversations(forServer server: String) -> [IRCManager.Conversation] { irc.conversations(forServer: server) }

    func messagesFor(server: String, channel: String) -> [WOMObject] {
        let key = "\(server)|\(channel.lowercased())"
        return messagesByChannelKey[key] ?? []
    }

    func systemEventsFor(server: String, channel: String) -> [WOMObject] {
        let msgs = systemEventsByChannelKey.flatMap { key, events in
            key.hasPrefix("\(server)|") ? events : []
        }
        return msgs.filter { obj in
            let c = obj.data["channel"] ?? ""
            return c == channel
        }.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Queries
    var feedObjects: [WOMObject] {
        ensureIndexes()
        return _feedPosts
    }
}
