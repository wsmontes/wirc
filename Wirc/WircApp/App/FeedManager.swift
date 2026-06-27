import SwiftUI
import BackgroundTasks
import Network

/// All feed-related state and logic, extracted from AppState.
@Observable
@MainActor
final class FeedManager {
    let subscriptionStore = FeedSubscriptionStore()
    private let fetcher = FeedFetcher()
    private let adapter = FeedToWOMAdapter()
    private let maxConsecutiveErrors = 5

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "wirc.reachability")
    var isOnline = true

    var feedError: String?
    /// Incremental progress during batch refresh — updated on each batch completion.
    var refreshProgress: (completed: Int, total: Int) = (0, 0)
    /// Number of genuinely new posts added during the most recent refresh.
    var newPostCount: Int = 0
    /// Called per batch during refresh so consumers can show incremental results.
    var onIncrementalBatch: (([WOMObject]) -> Void)?
    var isRefreshing = false
    /// Completion summary that lingers after refresh ends (auto-clears after 4s).
    var refreshSummary: String?
    var subscriptionCount: Int { subscriptionStore.getAll().count }
    /// Target language for on-device translation of feed content. "off" means no translation.
    var preferredLanguage: String = "off"

    // MARK: - Init

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = (path.status == .satisfied)
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - Feed Management

    func addFeed(url: String, sourceType: FeedSourceType? = nil, womStore: WOMStore) async throws -> [WOMObject] {
        guard let feedURL = URL(string: url) else { throw FeedError.invalidURL(url) }

        let finalURL: String
        let detectedType: FeedSourceType

        if url.hasSuffix(".xml") || url.hasSuffix(".rss") || url.contains("/feed") {
            finalURL = url
            detectedType = sourceType ?? .rss
        } else {
            let discovered = try await fetcher.discoverFeed(from: feedURL)
            guard let first = discovered.first else { throw FeedError.invalidURL("No feed found at \(url)") }
            finalURL = first.absoluteString
            detectedType = sourceType ?? detectSourceType(from: finalURL)
        }

        var tempSub = FeedSubscription(feedURL: finalURL, sourceType: detectedType)
        do {
            let (data, _) = try await fetcher.fetch(subscription: tempSub)
            let result = try FeedParser.parse(data: data, sourceURL: finalURL)
            tempSub.title = result.title ?? finalURL
        } catch { tempSub.title = finalURL }

        subscriptionStore.add(tempSub)
        return await refreshFeed(tempSub, womStore: womStore)
    }

    func removeFeed(_ subscription: FeedSubscription) {
        subscriptionStore.remove(id: subscription.id)
    }

    func importOPML(data: Data) async throws -> Int {
        let outlines = try fetcher.parseOPML(data)
        var count = 0
        for outline in outlines {
            let xmlURL = outline.xmlURL
            let sourceType = detectSourceType(from: xmlURL)
            var tags: [String] = []
            if let folder = outline.folderName { tags.append(folder) }
            subscriptionStore.add(FeedSubscription(feedURL: xmlURL, title: outline.title ?? xmlURL, sourceType: sourceType, tags: tags))
            count += 1
        }
        return count
    }

    @discardableResult
    func refreshAllFeeds(womStore: WOMStore) async -> [WOMObject] {
        for sub in subscriptionStore.getAll() where sub.errorCount >= maxConsecutiveErrors {
            var reset = sub; reset.errorCount = 0; subscriptionStore.update(reset)
        }
        var allNew: [WOMObject] = []
        for sub in subscriptionStore.getAll() {
            allNew.append(contentsOf: await refreshFeed(sub, womStore: womStore))
        }
        return allNew
    }

    @discardableResult
    func refreshAllFeedsBatched(womStore: WOMStore) async -> [WOMObject] {
        guard isOnline else {
            feedError = "No internet connection"
            return []
        }
        let all = subscriptionStore.getAll()
        let batchSize = 15
        isRefreshing = true
        refreshSummary = nil
        refreshProgress = (0, all.count)

        var allNew: [WOMObject] = []
        var completed = 0
        for batch in stride(from: 0, to: all.count, by: batchSize) {
            let end = min(batch + batchSize, all.count)
            let batchSubs = Array(all[batch..<end])

            // Fetch batch concurrently
            let batchResults: [[WOMObject]] = await withTaskGroup(of: [WOMObject].self) { group in
                for sub in batchSubs {
                    group.addTask { await self.refreshFeed(sub, womStore: womStore) }
                }
                var results: [[WOMObject]] = []
                for await items in group { results.append(items) }
                return results
            }

            let batchItems = batchResults.flatMap { $0 }
            allNew.append(contentsOf: batchItems)
            completed += batchSubs.count
            refreshProgress = (completed, all.count)
            // Publish incremental results so UI updates as each batch arrives
            if !batchItems.isEmpty, let onBatch = onIncrementalBatch {
                await MainActor.run { onBatch(batchItems) }
            }
            // Respect cancellation so the task stops when the user navigates away
            if Task.isCancelled { break }
            try? await Task.sleep(for: .milliseconds(100))
        }

        // Completion summary — lingers for 4s then auto-clears
        isRefreshing = false
        newPostCount = allNew.count
        refreshProgress = (all.count, all.count)
        refreshSummary = "✓ \(all.count) sources · \(allNew.count) new posts"
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if refreshSummary == "✓ \(all.count) sources · \(allNew.count) new posts" {
                refreshSummary = nil
            }
        }
        return allNew
    }

    func discoverFeedURL(from url: String) async throws -> [String] {
        guard let feedURL = URL(string: url) else { throw FeedError.invalidURL(url) }
        return try await fetcher.discoverFeed(from: feedURL).map { $0.absoluteString }
    }

    // MARK: - Private
    /// Refresh one feed. Returns new WOMObjects that were saved.
    func refreshFeed(_ subscription: FeedSubscription, womStore: WOMStore) async -> [WOMObject] {
        if subscription.errorCount >= maxConsecutiveErrors { return [] }
        do {
            let (data, response) = try await fetcher.fetch(subscription: subscription)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 304 {
                var sub = subscription; sub.lastFetchedAt = Date(); sub.errorCount = 0; subscriptionStore.update(sub)
                return []
            }
            let result = try FeedParser.parse(data: data, sourceURL: subscription.feedURL)
            var sub = subscription
            if let title = result.title { sub.title = title }
            sub.lastFetchedAt = Date(); sub.errorCount = 0
            if let httpResponse = response as? HTTPURLResponse {
                sub.etag = (httpResponse.allHeaderFields["ETag"] as? String) ?? (httpResponse.allHeaderFields["Etag"] as? String)
                sub.lastModified = httpResponse.allHeaderFields["Last-Modified"] as? String
            }
            subscriptionStore.update(sub)
            return await adapter.convert(items: result.items, subscription: sub, store: womStore, preferredLanguage: preferredLanguage)
        } catch {
            var sub = subscription; sub.errorCount += 1; sub.lastFetchedAt = Date(); subscriptionStore.update(sub)
            feedError = error.localizedDescription
            return []
        }
    }

    private func detectSourceType(from url: String) -> FeedSourceType {
        if url.contains("youtube.com") { return .youtube }
        if url.contains("github.com") { return .github }
        if url.contains("/podcast") || url.contains("itunes") { return .podcast }
        return .rss
    }

    func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.wirc.feed-refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
