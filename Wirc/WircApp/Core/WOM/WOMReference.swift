import Foundation

/// Reference to another WOM object, entity, or external resource.
/// Per WOM 0.6 §8 — references carry identity, not just pointers.
struct WOMReference: Codable, Equatable, Identifiable {
    var id: String
    var type: [String]?
    var name: String?
    /// Optional display label (alias, screen name).
    var displayName: String?
    /// URL for the referenced entity (profile, homepage, etc.).
    var url: String?
}
