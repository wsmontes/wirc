import SwiftUI
import BackgroundTasks

/// All feed-related state and logic, extracted from AppState.
@Observable
@MainActor
final class FeedManager {
    let subscriptionStore = FeedSubscriptionStore()
    private let fetcher = FeedFetcher()
    private let adapter = FeedToWOMAdapter()
    private let maxConsecutiveErrors = 5

    var feedLoading = false
    var feedError: String?

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
    func refreshAllFeedsBatched(womStore: WOMStore, onBatch: (([WOMObject]) async -> Void)? = nil) async -> [WOMObject] {
        let all = subscriptionStore.getAll()
        let batchSize = 5
        var allNew: [WOMObject] = []
        for batch in stride(from: 0, to: all.count, by: batchSize) {
            let end = min(batch + batchSize, all.count)
            var batchItems: [WOMObject] = []
            for i in batch..<end {
                batchItems.append(contentsOf: await refreshFeed(all[i], womStore: womStore))
            }
            allNew.append(contentsOf: batchItems)
            if !batchItems.isEmpty { await onBatch?(batchItems) }
            try? await Task.sleep(for: .milliseconds(100))
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
        feedLoading = true; feedError = nil
        defer { feedLoading = false }
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
            return await adapter.convert(items: result.items, subscription: sub, store: womStore)
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
