import Foundation

/// Represents a remote person/account known to the system.
/// Not functional in MVP — type definition for future social layer.
struct RemoteIdentity: Codable, Identifiable {
    var id: String              // irc://server/nick, did:key:..., @user@mastodon.server
    var displayName: String
    var protocolType: String    // "irc", "mastodon", "bluesky", "nostr"
    var avatarURL: String?
    var profileURL: String?
    var knownServers: [String]?
    var lastSeen: Date?
    var createdAt: Date
}
