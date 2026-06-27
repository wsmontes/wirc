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

    // MARK: - Onboarding
    /// Stored property so @Observable tracks changes. Synced to UserDefaults on write.
    var onboardingCompleted: Bool = UserDefaults.standard.bool(forKey: "wirc.onboarding.completed") {
        didSet { UserDefaults.standard.set(onboardingCompleted, forKey: "wirc.onboarding.completed") }
    }

    // MARK: - Translation
    /// Target language for on-device feed translation. "off" means no translation.
    var preferredLanguage: String = UserDefaults.standard.string(forKey: "wirc.translation.language") ?? "off" {
        didSet {
            UserDefaults.standard.set(preferredLanguage, forKey: "wirc.translation.language")
            if preferredLanguage != oldValue {
                Task { await TranslationService.shared.clearCache() }
            }
        }
    }

    // MARK: - Retranslation

    /// Translates all existing feed post content to the current preferredLanguage.
    /// Runs in a background task; persists translated text back to the store.
    func retranslateAllFeedContent() {
        let language = preferredLanguage
        guard language != "off" else { return }
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            let objects = await MainActor.run { self.womObjects.filter { $0.type.contains("wom:Post") } }
            for i in 0..<objects.count {
                var obj = objects[i]
                if let text = obj.content?.text, !text.isEmpty {
                    let translated = await TranslationService.shared.translate(text, to: language)
                    if translated != text {
                        obj.data["translatedText"] = translated
                        try? await self.store.save(obj)
                    }
                }
            }
            await MainActor.run {
                self.invalidateIndexes()
            }
        }
    }

    // MARK: - Debug logs
    var rawEvents: [DebugRawEvent] = [] {
        didSet { if rawEvents.count > 500 { rawEvents = Array(rawEvents.suffix(500)) } }
    }
    private var isTrimming = false
    var womObjects: [WOMObject] = [] {
        didSet {
            guard !isTrimming else { return }
            if womObjects.count > 2000 {
                isTrimming = true
                let feedPosts = womObjects.filter { $0.type.contains("wom:Post") }
                let ircMessages = womObjects.filter { !$0.type.contains("wom:Post") }
                // Keep all feed posts + most recent IRC messages up to 2000 total
                let feedCap = min(feedPosts.count, 400)
                let keptFeed = Array(feedPosts.prefix(feedCap))
                let ircCap = 2000 - keptFeed.count
                let keptIRC = Array(ircMessages.suffix(ircCap))
                womObjects = keptFeed + keptIRC
                isTrimming = false
                let totalDropped = oldValue.count - womObjects.count
                if totalDropped > 0 {
                    os_log(.debug, "AppState: evicted %d objects (kept %d feed, %d IRC)", totalDropped, keptFeed.count, keptIRC.count)
                }
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
        feed.preferredLanguage = preferredLanguage
        // Publish incremental feed results so cards appear as each batch arrives
        feed.onIncrementalBatch = { [weak self] batch in
            self?.womObjects.append(contentsOf: batch)
        }
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
        let defaultsLoaded = UserDefaults.standard.bool(forKey: "wirc.feeds.defaultsLoaded")
        if !defaultsLoaded {
            DefaultFeedsLoader.loadIfEmpty(into: feed.subscriptionStore)
            UserDefaults.standard.set(true, forKey: "wirc.feeds.defaultsLoaded")
        }
        // Load saved objects once the store is ready, then refresh feeds.
        Task { [weak self] in
            guard let self else { return }
            // Wait for the store's background index load to complete
            while !store.isReady { try? await Task.sleep(for: .milliseconds(50)) }
            let existingCount = store.diskCount
            if existingCount > 0, let existing = try? store.allSync() {
                await MainActor.run {
                    womObjects = Array(existing.suffix(2000))
                }
                os_log(.info, "AppState: loaded %d objects from persistent store", existing.count)
            }
            // Fetch new items in background
            _ = await self.feed.refreshAllFeedsBatched(womStore: self.store)
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
        // handleEvent does its own WOM conversion + delivery via onWOMObjects callback.
        // Do NOT convert again here — that would double every object in womObjects.
        irc.handleEvent(event, serverId: serverId)

        switch event {
        case .rawLine(let line):
            rawEvents.append(DebugRawEvent(timestamp: Date(), server: config.host, raw: line, parsedAs: "raw"))
        case .error(let msg):
            rawEvents.append(DebugRawEvent(timestamp: Date(), server: config.host, raw: msg, parsedAs: "error"))
        default: break
        }
    }

    // MARK: - Mastodon
    private let mastodonAccountsKey = "wirc.mastodonAccounts"
    private func saveMastodonAccounts() {
        // Store token in Keychain, rest in UserDefaults
        var safeAccounts: [MastodonStoredConfig] = []
        for account in mastodonAccounts {
            let key = "wirc.mastodon.token.\(account.id.uuidString)"
            if let tokenData = account.accessToken.data(using: .utf8) {
                KeychainStore.save(key: key, data: tokenData)
            }
            safeAccounts.append(MastodonStoredConfig(id: account.id, name: account.name, instanceURL: account.instanceURL))
        }
        if let d = try? JSONEncoder().encode(safeAccounts) {
            UserDefaults.standard.set(d, forKey: mastodonAccountsKey)
        }
    }
    private func loadMastodonAccounts() {
        guard let data = UserDefaults.standard.data(forKey: mastodonAccountsKey) else { return }
        if let storedAccounts = try? JSONDecoder().decode([MastodonStoredConfig].self, from: data) {
            mastodonAccounts = storedAccounts.compactMap { stored in
                let key = "wirc.mastodon.token.\(stored.id.uuidString)"
                guard let tokenData = KeychainStore.load(key: key),
                      let token = String(data: tokenData, encoding: .utf8) else { return nil }
                return MastodonServerConfig(id: stored.id, name: stored.name, instanceURL: stored.instanceURL, accessToken: token)
            }
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
        adapter.preferredLanguage = preferredLanguage
        Task { @MainActor in
            do {
                let lastId = mastodonAccounts.first(where: { $0.id == accountId })?.lastFetchedId
                let timeline = try await client.homeTimeline(maxId: lastId, limit: 40)
                for status in timeline {
                    let obj = await adapter.convertWithTranslation(status: status)
                    try? await store.save(obj)
                    if !womObjects.contains(where: { $0.id == obj.id }) { womObjects.append(obj) }
                }
                // Store last ID for next refresh
                if let latestStatus = timeline.first,
                   let idx = mastodonAccounts.firstIndex(where: { $0.id == accountId }) {
                    mastodonAccounts[idx].lastFetchedId = latestStatus.id
                    saveMastodonAccounts()
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
                adapter.preferredLanguage = preferredLanguage
                let obj = await adapter.convertWithTranslation(status: status)
                var localObj = obj; localObj.provenance = .localUser()
                try? await store.save(localObj); womObjects.append(localObj)
            } catch { rawEvents.append(DebugRawEvent(timestamp: Date(), server: client.config.instanceURL, raw: error.localizedDescription, parsedAs: "mastodon_post_error")) }
        }
    }

    // MARK: - OAuth

    /// Pending OAuth state — set before opening the browser, read on callback.
    private struct PendingOAuth: Sendable {
        let accountName: String
        let instance: String
        let clientId: String
        let clientSecret: String
    }
    private var pendingOAuth: PendingOAuth?

    /// Start the OAuth flow: register app on instance, then open browser for authorization.
    func startMastodonOAuth(instance: String, accountName: String) async throws {
        let registration = try await MastodonClient.registerApp(instance: instance)
        pendingOAuth = PendingOAuth(
            accountName: accountName,
            instance: instance,
            clientId: registration.clientId,
            clientSecret: registration.clientSecret
        )
        let url = try MastodonClient.oauthURL(instance: instance, clientId: registration.clientId)
        await MainActor.run {
            UIApplication.shared.open(url)
        }
    }

    /// Handle OAuth callback URL — exchange code for token and save account.
    func handleOAuthCallback(url: URL) {
        guard url.scheme == "wirc",
              url.host == "oauth",
              url.path == "/callback" || url.path == "callback",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let pending = pendingOAuth else { return }

        Task {
            defer { Task { @MainActor in self.pendingOAuth = nil } }
            do {
                let token = try await MastodonClient.exchangeCode(
                    code: code,
                    instance: pending.instance,
                    clientId: pending.clientId,
                    clientSecret: pending.clientSecret
                )
                let instanceURL = "https://\(pending.instance)"
                await MainActor.run {
                    addMastodonAccount(name: pending.accountName, instanceURL: instanceURL, token: token)
                }
            } catch {
                await MainActor.run {
                    rawEvents.append(DebugRawEvent(
                        timestamp: Date(),
                        server: pending.instance,
                        raw: "OAuth token exchange failed: \(error.localizedDescription)",
                        parsedAs: "mastodon_oauth_error"
                    ))
                }
            }
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

    // MARK: - Bookmarks

    func toggleBookmark(_ object: WOMObject) {
        let existingId = womObjects.first(where: {
            $0.type.contains("wom:Signal") && $0.data["signalType"] == "bookmarked" && $0.data["targetId"] == object.id
        })?.id
        if let eid = existingId {
            // Remove bookmark
            womObjects.removeAll { $0.id == eid }
            Task { try? await store.delete(id: eid) }
        } else {
            // Add bookmark
            let signal = WOMObject(
                id: WOMIDGenerator.generate(type: "signal"),
                type: ["wom:Signal"],
                createdAt: Date(),
                data: ["signalType": "bookmarked", "targetId": object.id, "targetTitle": object.name ?? object.content.flatMap { String($0.text?.prefix(100) ?? "") } ?? ""],
                provenance: .localUser()
            )
            Task { try? await store.save(signal); await MainActor.run { womObjects.append(signal) } }
        }
    }

    func isBookmarked(_ object: WOMObject) -> Bool {
        womObjects.contains(where: {
            $0.type.contains("wom:Signal") && $0.data["signalType"] == "bookmarked" && $0.data["targetId"] == object.id
        })
    }
}
