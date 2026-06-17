import Foundation

/// Represents a social signal: like, recommend, block, mute, follow, etc.
/// Not functional in MVP — type definition for future social layer.
enum SocialSignalType: String, Codable {
    case liked
    case saved
    case recommended
    case followed
    case blocked
    case muted
    case confirmed
    case rejected
    case shared
    case watched
    case read
    case joined
}

struct SocialSignal: Codable, Identifiable {
    var id: String
    var signalType: SocialSignalType
    var strength: String?     // "low", "medium", "high"
    var topic: String?
    var visibility: String?   // "public", "friends", "private"
    var attributedTo: WOMReference
    var objectRef: String?    // ID of the object this signal references
    var createdAt: Date
    var provenance: WOMProvenance?
}
