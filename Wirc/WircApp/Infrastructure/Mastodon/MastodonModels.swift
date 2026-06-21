import Foundation

// MARK: - Server Config

struct MastodonServerConfig: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var instanceURL: String
    var accessToken: String

    enum CodingKeys: String, CodingKey {
        case name, instanceURL, accessToken
    }
}

/// Lightweight persisted config — no accessToken; token goes in Keychain instead.
struct MastodonStoredConfig: Codable, Identifiable {
    var id: UUID
    var name: String
    var instanceURL: String
}

// MARK: - Account

struct MastodonAccount: Codable, Identifiable {
    let id: String
    let username: String
    let acct: String
    let displayName: String
    let avatar: String?       // URL
    let avatarStatic: String?
    let url: String?          // profile URL
    let note: String?         // bio (HTML)
    let followersCount: Int?
    let followingCount: Int?
    let statusesCount: Int?
}

// MARK: - Status (Post)

struct MastodonStatus: Codable, Identifiable {
    let id: String
    let uri: String?
    let createdAt: String     // ISO 8601
    let account: MastodonAccount
    let content: String?      // HTML
    let visibility: String?   // public, unlisted, private, direct
    let sensitive: Bool?
    let spoilerText: String?
    let mediaAttachments: [MastodonMedia]?
    let reblog: MastodonReblog?
    let favourited: Bool?
    let reblogged: Bool?
    let favouritesCount: Int?
    let reblogsCount: Int?
    let repliesCount: Int?
    let url: String?
    let card: MastodonCard?
    let application: MastodonApplication?
    let language: String?

    var isReblog: Bool { reblog != nil }

    // Decode dates manually or use a decoder strategy
    var parsedDate: Date? {
        let fmts = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZ",
        ]
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        for fmt in fmts {
            parser.dateFormat = fmt
            if let d = parser.date(from: createdAt) { return d }
        }
        return nil
    }
}

struct MastodonReblog: Codable {
    let id: String?
    let account: MastodonAccount?
    let content: String?
    let createdAt: String?
    let url: String?
    let mediaAttachments: [MastodonMedia]?

    enum CodingKeys: String, CodingKey {
        case id, account, content, url
        case createdAt = "created_at"
        case mediaAttachments = "media_attachments"
    }
}

// MARK: - Media

struct MastodonMedia: Codable, Identifiable {
    let id: String
    let type: String?         // image, video, gifv, audio
    let url: String?
    let previewUrl: String?
    let description: String?
}

// MARK: - Card (Link Preview)

struct MastodonCard: Codable {
    let url: String?
    let title: String?
    let description: String?
    let image: String?
}

// MARK: - Application

struct MastodonApplication: Codable {
    let name: String?
    let website: String?
}

// MARK: - API Response Arrays

typealias MastodonTimeline = [MastodonStatus]

// MARK: - Tag/Hashtag

struct MastodonTag: Codable, Identifiable {
    let name: String
    let url: String?
    var id: String { name }
}
