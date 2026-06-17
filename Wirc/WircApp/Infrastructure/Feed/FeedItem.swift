import Foundation

/// Intermediate struct representing one item parsed from an RSS or Atom feed.
/// Analogous to IRCMessage — raw parsed data before conversion to WOM.
struct FeedItem: Codable, Equatable {
    let id: String              // guid (RSS) or id (Atom), fallback: link
    let title: String
    let link: String            // canonical URL
    let description: String?    // plain text or HTML summary
    let publishedAt: Date?

    let author: String?
    let category: String?
    let enclosureURL: String?   // media: image, audio, video thumbnail
    let enclosureType: String?  // MIME type
    let duration: String?       // podcast/YouTube duration string
}
