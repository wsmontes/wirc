import SwiftUI
import Observation
import BackgroundTasks

@Observable
@MainActor
final class AppState {
    // MARK: - Server configs
    var servers: [IRCConnectionConfig] = [] {
        didSet { saveServers() }
    }

    // MARK: - WOM Store
    let store: WOMStore = JSONFileStore()

    // MARK: - IRC Clients
    private var clients: [UUID: IRCClient] = [:]

    // MARK: - Connection status
    var connectionStates: [UUID: ConnectionStatus] = [:]

    // MARK: - Channel state (keyed by "server|#channel")
    var channelTopics: [String: ChannelTopic] = [:]
    var channelUsers: [String: [ChannelUser]] = [:]
    var joinedChannels: [UUID: [String]] = [:]  // serverId → [channel names]
    var serverChannelList: [UUID: [ListedChannel]] = [:]  // serverId → LIST results
    var isListing: [UUID: Bool] = [:]

    struct ListedChannel: Hashable, Identifiable {
        var id: String { name }
        let name: String
        let users: Int
        let topic: String
    }

    // MARK: - Debug logs
    var rawEvents: [DebugRawEvent] = []
    var womObjects: [WOMObject] = []

    // MARK: - Server Orchestrator
    var orchestrator = ServerOrchestrator(servers: SuggestedServersLoader.servers)

    // MARK: - IRC Channel Manager
    let channelManager: IRCChannelManager

    // MARK: - Feed (RSS/Atom)
    let feedStore = FeedSubscriptionStore()
    private let feedFetcher = FeedFetcher()
    private let feedAdapter = FeedToWOMAdapter()

    // MARK: - Mastodon
    var mastodonAccounts: [MastodonServerConfig] = [] {
        didSet { saveMastodonAccounts() }
    }
    private var mastodonClients: [UUID: MastodonClient] = [:]
    var feedLoading = false
    var feedError: String?

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

    init() {
        channelManager = IRCChannelManager(store: store)
        loadServers()
        loadMastodonAccounts()
        // Preload ~200 default feeds if feed store is empty (first launch)
        let loaded = DefaultFeedsLoader.loadIfEmpty(into: feedStore)
        if loaded > 0 {
            // Refresh all feeds in the background — batched to avoid UI block
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.refreshAllFeedsBatched()
            }
        }
    }

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

    /// Connect to a server if needed, then join a channel once online.
    func connectAndJoin(channel: String, serverId: UUID) {
        let ch = channel.hasPrefix("#") ? channel : "#\(channel)"
        if !(joinedChannels[serverId]?.contains(ch) ?? false) {
            joinedChannels[serverId, default: []].append(ch)
        }
        switch connectionStates[serverId] ?? .disconnected {
        case .online:
            clients[serverId]?.join(channel: ch)
        case .connecting:
            break // Will join when .connected fires
        case .disconnected:
            connect(to: serverId) // Will join when .connected fires
        }
    }

    func fetchChannelList(serverId: UUID) {
        guard let client = clients[serverId] else { return }
        serverChannelList[serverId] = []
        isListing[serverId] = true
        client.listChannels()
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
            schema: WOMSchema.message,
            attributedTo: WOMReference(id: "local:user", type: ["wom:Person"], name: config.nickname),
            content: WOMContent(format: "text/plain", text: text, language: "en"),
            data: ["network": "irc", "server": config.host, "channel": channel],
            provenance: .localUser(),
            governance: WOMGovernance(
                purpose: ["messaging"],
                adsUse: WOMAdsUse.notAllowed.rawValue,
                agentUse: "allowed",
                sharing: WOMSharing.groupOnly.rawValue,
                retention: "forever"
            ),
            classification: WOMClassification(
                semanticType: "social.message",
                dataSubject: "local_user",
                origin: WOMOrigin.userProvided.rawValue,
                sensitivity: WOMDataSensitivity.personal.rawValue
            ),
            bindings: WOMBindings(irc: WOMIRCBinding(
                server: config.host,
                channel: channel,
                nick: config.nickname
            ))
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
            // Join all pending channels
            if let pending = joinedChannels[serverId] {
                for ch in pending {
                    clients[serverId]?.join(channel: ch)
                }
            }
            // Also join auto-join from config
            if let cfg = servers.first(where: { $0.id == serverId }) {
                for ch in cfg.autoJoinChannels {
                    let c = ch.hasPrefix("#") ? ch : "#\(ch)"
                    if !(joinedChannels[serverId]?.contains(c) ?? false) {
                        joinedChannels[serverId, default: []].append(c)
                        clients[serverId]?.join(channel: c)
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
        case .listStart:
            serverChannelList[serverId] = []
            isListing[serverId] = true
        case .listItem(let channel, let users, let topic):
            serverChannelList[serverId, default: []].append(ListedChannel(name: channel, users: users, topic: topic))
        case .listEnd:
            isListing[serverId] = false
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

    // MARK: - Mastodon

    private let mastodonAccountsKey = "wirc.mastodonAccounts"

    private func saveMastodonAccounts() {
        guard let d = try? JSONEncoder().encode(mastodonAccounts) else { return }
        UserDefaults.standard.set(d, forKey: mastodonAccountsKey)
    }

    private func loadMastodonAccounts() {
        // 1. Load from UserDefaults (manually added accounts)
        if let d = UserDefaults.standard.data(forKey: mastodonAccountsKey),
           let a = try? JSONDecoder().decode([MastodonServerConfig].self, from: d),
           !a.isEmpty {
            mastodonAccounts = a
        }
        // 2. Also load from bundle config file (auto-installed)
        else if let url = Bundle.main.url(forResource: "mastodon_config", withExtension: "json"),
                let data = try? Data(contentsOf: url),
                let cfg = try? JSONDecoder().decode(MastodonServerConfig.self, from: data) {
            mastodonAccounts = [cfg]
            saveMastodonAccounts()
        } else {
            return
        }
        // Init clients and refresh
        for acct in mastodonAccounts {
            mastodonClients[acct.id] = MastodonClient(config: acct)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            for acct in mastodonAccounts {
                refreshMastodonFeed(accountId: acct.id)
            }
        }
    }

    func addMastodonAccount(name: String, instanceURL: String, token: String) {
        let c = MastodonServerConfig(name: name, instanceURL: instanceURL, accessToken: token)
        mastodonAccounts.append(c)
        mastodonClients[c.id] = MastodonClient(config: c)
        refreshMastodonFeed(accountId: c.id)
    }

    func removeMastodonAccount(id: UUID) {
        mastodonAccounts.removeAll { $0.id == id }
        mastodonClients.removeValue(forKey: id)
    }

    func refreshMastodonFeed(accountId: UUID) {
        guard let client = mastodonClients[accountId] ?? {
            if let acct = mastodonAccounts.first(where: { $0.id == accountId }) {
                let c = MastodonClient(config: acct)
                mastodonClients[accountId] = c
                return c
            }
            return nil
        }() else { return }

        feedLoading = true
        feedError = nil
        let adapter = MastodonToWOMAdapter(instanceURL: client.config.instanceURL)

        Task { @MainActor in
            do {
                let timeline = try await client.homeTimeline(limit: 40)
                for status in timeline {
                    let obj = adapter.convert(status: status)
                    try? await store.save(obj)
                    if !womObjects.contains(where: { $0.id == obj.id }) {
                        womObjects.append(obj)
                    }
                }
                feedLoading = false
            } catch {
                feedError = error.localizedDescription
                feedLoading = false
                rawEvents.append(DebugRawEvent(
                    timestamp: Date(), server: client.config.instanceURL,
                    raw: error.localizedDescription, parsedAs: "mastodon_error"
                ))
            }
        }
    }

    func postToMastodon(_ text: String, accountId: UUID, visibility: String = "public") {
        guard let client = mastodonClients[accountId] else { return }
        Task { @MainActor in
            do {
                let status = try await client.postStatus(text, visibility: visibility)
                let adapter = MastodonToWOMAdapter(instanceURL: client.config.instanceURL)
                let obj = adapter.convert(status: status)
                var localObj = obj
                localObj.provenance = .localUser()
                localObj.governance = WOMGovernance(
                    purpose: ["messaging"],
                    adsUse: WOMAdsUse.notAllowed.rawValue,
                    agentUse: "allowed",
                    sharing: WOMSharing.public.rawValue,
                    retention: "forever"
                )
                try? await store.save(localObj)
                womObjects.append(localObj)
            } catch {
                rawEvents.append(DebugRawEvent(
                    timestamp: Date(), server: client.config.instanceURL,
                    raw: error.localizedDescription, parsedAs: "mastodon_post_error"
                ))
            }
        }
    }

    func boostMastodonStatus(_ statusId: String, accountId: UUID) {
        guard let client = mastodonClients[accountId] else { return }
        Task { @MainActor in
            _ = try? await client.boost(statusId: statusId)
        }
    }

    func favouriteMastodonStatus(_ statusId: String, accountId: UUID) {
        guard let client = mastodonClients[accountId] else { return }
        Task { @MainActor in
            _ = try? await client.favourite(statusId: statusId)
        }
    }

    // MARK: - Feed management

    func addFeed(url: String, sourceType: FeedSourceType? = nil) async throws {
        guard let feedURL = URL(string: url) else {
            throw FeedError.invalidURL(url)
        }

        // Capture sendable references before crossing async boundaries
        let fetcher = feedFetcher

        // If it looks like a website URL, auto-discover
        let finalURL: String
        let detectedType: FeedSourceType

        if url.hasSuffix(".xml") || url.hasSuffix(".rss") || url.contains("/feed") {
            finalURL = url
            detectedType = sourceType ?? .rss
        } else {
            let discovered = try await fetcher.discoverFeed(from: feedURL)
            guard let first = discovered.first else {
                throw FeedError.invalidURL("No feed found at \(url)")
            }
            finalURL = first.absoluteString
            detectedType = sourceType ?? detectSourceType(from: finalURL)
        }

        // Create a temporary subscription to fetch title
        var tempSub = FeedSubscription(feedURL: finalURL, sourceType: detectedType)
        do {
            let (data, _) = try await fetcher.fetch(subscription: tempSub)
            let result = try FeedParser.parse(data: data, sourceURL: finalURL)
            tempSub.title = result.title ?? finalURL
        } catch {
            tempSub.title = finalURL // use URL as fallback title
        }

        feedStore.add(tempSub)

        // Fetch items for this feed immediately
        Task { await refreshFeed(tempSub) }
    }

    func removeFeed(_ subscription: FeedSubscription) {
        feedStore.remove(id: subscription.id)
    }

    func importOPML(data: Data) async throws -> Int {
        let outlines = try feedFetcher.parseOPML(data)
        var count = 0
        for outline in outlines {
            let xmlURL = outline.xmlURL
            let sourceType = detectSourceType(from: xmlURL)
            var tags: [String] = []
            if let folder = outline.folderName { tags.append(folder) }
            let sub = FeedSubscription(
                feedURL: xmlURL,
                title: outline.title ?? xmlURL,
                sourceType: sourceType,
                tags: tags
            )
            feedStore.add(sub)
            count += 1
            // Fetch lazily — just store the subscription; first refresh picks up items
        }
        return count
    }

    /// Refresh all feeds in small batches, yielding to the main thread between each
    /// to prevent UI freezes when processing hundreds of feeds with thousands of items.
    func refreshAllFeedsBatched() async {
        let all = feedStore.getAll()
        let batchSize = 5
        for batch in stride(from: 0, to: all.count, by: batchSize) {
            let end = min(batch + batchSize, all.count)
            for i in batch..<end {
                await refreshFeed(all[i])
            }
            // Yield to the main thread between batches
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    func refreshAllFeeds() async {
        // Reset error counts for paused feeds so they are retried on manual refresh
        for sub in feedStore.getAll() where sub.errorCount >= maxConsecutiveErrors {
            var reset = sub
            reset.errorCount = 0
            feedStore.update(reset)
        }
        for sub in feedStore.getAll() {
            await refreshFeed(sub)
        }
    }

    func discoverFeedURL(from url: String) async throws -> [String] {
        guard let feedURL = URL(string: url) else {
            throw FeedError.invalidURL(url)
        }
        let fetcher = feedFetcher
        let discovered = try await fetcher.discoverFeed(from: feedURL)
        return discovered.map { $0.absoluteString }
    }

    // MARK: - Feed refresh (private)

    private let maxConsecutiveErrors = 5

    private func refreshFeed(_ subscription: FeedSubscription) async {
        // Skip feeds that have exceeded the max consecutive error threshold
        if subscription.errorCount >= maxConsecutiveErrors {
            rawEvents.append(DebugRawEvent(
                timestamp: Date(), server: subscription.feedURL,
                raw: "Skipping feed refresh — \(subscription.errorCount) consecutive errors (max \(maxConsecutiveErrors))",
                parsedAs: "feed_error"
            ))
            return
        }

        let fetcher = feedFetcher
        let adapter = feedAdapter
        do {
            let (data, response) = try await fetcher.fetch(subscription: subscription)

            // Check for 304 Not Modified
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 304 {
                var sub = subscription
                sub.lastFetchedAt = Date()
                sub.errorCount = 0
                feedStore.update(sub)
                return
            }

            let result = try FeedParser.parse(data: data, sourceURL: subscription.feedURL)

            // Update subscription with parsed title and headers
            var sub = subscription
            if let title = result.title { sub.title = title }
            sub.lastFetchedAt = Date()
            sub.errorCount = 0
            if let httpResponse = response as? HTTPURLResponse {
                sub.etag = httpResponse.allHeaderFields["ETag"] as? String ?? httpResponse.allHeaderFields["Etag"] as? String
                sub.lastModified = httpResponse.allHeaderFields["Last-Modified"] as? String
            }
            feedStore.update(sub)

            // Convert items to WOM and save (dedup + save happen atomically inside convert)
            let objects = await adapter.convert(items: result.items, subscription: sub, store: store)
            if !objects.isEmpty {
                womObjects.append(contentsOf: objects)
            }
        } catch {
            var sub = subscription
            sub.errorCount += 1
            sub.lastFetchedAt = Date()
            feedStore.update(sub)

            if sub.errorCount >= maxConsecutiveErrors {
                rawEvents.append(DebugRawEvent(
                    timestamp: Date(), server: sub.feedURL,
                    raw: "Feed \(sub.feedURL) hit \(sub.errorCount) consecutive errors — giving up until next app launch",
                    parsedAs: "feed_error"
                ))
            }
        }
    }

    private func detectSourceType(from url: String) -> FeedSourceType {
        if url.contains("youtube.com") { return .youtube }
        if url.contains("github.com") { return .github }
        // Check for podcast indicators in URL
        if url.contains("/podcast") || url.contains("itunes") { return .podcast }
        return .rss
    }

    func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.wirc.feed-refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
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
