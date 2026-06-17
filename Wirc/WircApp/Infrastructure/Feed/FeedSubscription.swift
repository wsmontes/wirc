import Foundation

enum FeedSourceType: String, Codable, CaseIterable {
    case rss
    case atom
    case youtube
    case github
    case podcast
}

struct FeedSubscription: Codable, Identifiable, Equatable {
    let id: UUID
    var feedURL: String             // https://example.com/feed.xml
    var title: String               // parsed from feed on first fetch
    var sourceType: FeedSourceType  // determines WOM type mapping
    var tags: [String]              // user-assigned; AI later
    var lastFetchedAt: Date?
    var etag: String?               // HTTP ETag for conditional GET
    var lastModified: String?       // HTTP Last-Modified header
    var errorCount: Int             // consecutive failures; auto-pause after threshold

    init(
        id: UUID = UUID(),
        feedURL: String,
        title: String = "",
        sourceType: FeedSourceType = .rss,
        tags: [String] = [],
        lastFetchedAt: Date? = nil,
        etag: String? = nil,
        lastModified: String? = nil,
        errorCount: Int = 0
    ) {
        self.id = id
        self.feedURL = feedURL
        self.title = title
        self.sourceType = sourceType
        self.tags = tags
        self.lastFetchedAt = lastFetchedAt
        self.etag = etag
        self.lastModified = lastModified
        self.errorCount = errorCount
    }
}

/// Result of parsing a feed: feed-level metadata + items
struct FeedParseResult {
    let title: String?
    let description: String?
    let link: String?
    let items: [FeedItem]
}
