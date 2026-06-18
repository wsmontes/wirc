import Foundation

// MARK: - WOM 0.6 Identity Layer (§8)

/// Identity model per WOM 0.6 §8: separates entity, name, external identifier,
/// variant, version, and representation.
struct WOMIdentity: Codable, Equatable {
    var canonicalId: String?
    var variantOf: String?
    var versionOf: String?
    var representationOf: String?
    var workId: String?
    var instanceId: String?
    var itemId: String?
    var canonicalStatus: String?  // "canonical", "variant", "representation", "instance", "item"
}

/// A label or name for an entity, per WOM 0.6 §8.
struct WOMLabel: Codable, Equatable {
    var value: String
    var language: String?
    var role: String?  // "preferred", "alias", "display", "sort", "index"
}
