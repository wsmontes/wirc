import Foundation

/// Loads default feeds from the bundled DefaultFeeds.json.
/// Used on first launch to pre-populate with ~200 feeds across categories.
enum DefaultFeedsLoader {
    struct DefaultFeed: Codable {
        let title: String
        let url: String
        let type: String
    }

    static var feeds: [DefaultFeed] {
        guard let url = Bundle.main.url(forResource: "DefaultFeeds", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let feeds = try? JSONDecoder().decode([DefaultFeed].self, from: data)
        else { return [] }
        return feeds
    }

    /// Load default feeds into a FeedSubscriptionStore if it's empty.
    /// Returns the number of feeds loaded.
    @discardableResult
    static func loadIfEmpty(into store: FeedSubscriptionStore) -> Int {
        guard store.getAll().isEmpty else { return 0 }
        let subscriptions = feeds.map { feed in
            let sourceType = FeedSourceType(rawValue: feed.type) ?? .rss
            return FeedSubscription(
                feedURL: feed.url,
                title: feed.title,
                sourceType: sourceType
            )
        }
        store.addMany(subscriptions)
        return subscriptions.count
    }
}
