import Foundation

/// Represents a trust relationship from the local user to a remote identity.
/// Not functional in MVP — type definition for future social layer.
struct TrustRelation: Codable, Identifiable {
    var id: String
    var trustedIdentityId: String
    var topic: String?
    var weight: String?          // "low", "medium", "high"
    var allowedSignals: [SocialSignalType]?
    var maxDepth: Int?           // max hops for transitive trust
    var createdAt: Date
    var updatedAt: Date?
}
