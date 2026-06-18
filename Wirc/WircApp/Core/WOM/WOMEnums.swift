import Foundation

// MARK: - WOM 0.6 Shared Enumerations & Constants

/// Provenance origin values per WOM 0.6 §10 / §11.
enum WOMOrigin: String, Codable, CaseIterable {
    case userProvided = "user_provided"
    case observed = "observed"
    case inferred = "inferred"
    case modeled = "modeled"
    case imported = "imported"
    case assistantGenerated = "assistant_generated"
    case remotePeer = "remote_peer"
    case systemGenerated = "system_generated"
    case sensor = "sensor"
    case externalProtocol = "external_protocol"
    case editorial = "editorial"
    case machine = "machine"
    /// Legacy value from WOM 0.1 — mapped to user_provided on read.
    case localUser = "local_user"
}

/// Sensitivity levels per WOM 0.6 §9.
enum WOMDataSensitivity: String, Codable {
    case `public` = "public"
    case personal = "personal"
    case `private` = "private"
    case sensitive = "sensitive"
    case commercialBehavior = "commercial_behavior"
    case location = "location"
    case identity = "identity"
    case credential = "credential"
    case financial = "financial"
    case sourceProtected = "source_protected"
    case embargoed = "embargoed"
    case unknown = "unknown"
}

/// Governance purpose per WOM 0.6 §13.
enum WOMPurpose: String, Codable {
    case personalUse = "personal_use"
    case messaging = "messaging"
    case curation = "curation"
    case personalization = "personalization"
    case analytics = "analytics"
    case commercialMeasurement = "commercial_measurement"
    case advertising = "advertising"
    case agentResponse = "agent_response"
    case research = "research"
    case export = "export"
    case backup = "backup"
    case journalism = "journalism"
    case publication = "publication"
    case archive = "archive"
}

/// Ads/agent use policy per WOM 0.6 §13.
enum WOMAdsUse: String, Codable {
    case notAllowed = "not_allowed"
    case allowed = "allowed"
    case requiresExplicitConsent = "requires_explicit_consent"
    case aggregatedOnly = "aggregated_only"
    case contextualOnly = "contextual_only"
    case localOnly = "local_only"
    case unknown = "unknown"
}

/// Sharing constraint per WOM 0.6 §13.
enum WOMSharing: String, Codable {
    case localOnly = "local_only"
    case directRecipient = "direct_recipient"
    case friendsOnly = "friends_only"
    case groupOnly = "group_only"
    case `public` = "public"
    case aggregatedOnly = "aggregated_only"
    case cleanRoomOnly = "clean_room_only"
    case restricted = "restricted"
    case notAllowed = "not_allowed"
}

/// Review status per WOM 0.6 §11.
enum WOMReviewStatus: String, Codable {
    case none = "none"
    case pending = "pending"
    case verified = "verified"
    case rejected = "rejected"
    case needsReview = "needs_review"
}

/// Canonical status per WOM 0.6 §8.
enum WOMCanonicalStatus: String, Codable {
    case canonical = "canonical"
    case variant = "variant"
    case representation = "representation"
    case instance = "instance"
    case item = "item"
}

/// Rank for statements/claims per WOM 0.6 §10.
enum WOMRank: String, Codable {
    case preferred = "preferred"
    case normal = "normal"
    case deprecated = "deprecated"
    case contested = "contested"
}

/// Category role for descriptors per WOM 0.6 §9.
enum WOMCategoryRole: String, Codable {
    case ontological = "ontological"
    case navigation = "navigation"
    case editorial = "editorial"
    case maintenance = "maintenance"
    case commercial = "commercial"
    case personal = "personal"
    case temporary = "temporary"
    case journalistic = "journalistic"
    case archive = "archive"
}

/// Standard WOM 0.6 JSON-LD contexts.
enum WOMStandardContext {
    static let schemaOrg = "https://schema.org"
    static let activityStreams = "https://www.w3.org/ns/activitystreams"
    static let wom = "https://wawasoft.net/ns/wom/v0"

    static let defaults: [String] = [
        schemaOrg,
        activityStreams,
        wom
    ]
}

/// WOM schema identifiers for profiles.
enum WOMSchema {
    static let note = "wom.note.v0"
    static let message = "wom.message.v0"
    static let post = "wom.post.v0"
    static let signal = "wom.signal.v0"
    static let event = "wom.event.v0"
    static let statement = "wom.statement.v0"
    static let claim = "wom.claim.v0"
    static let product = "wom.product.v0"
    static let newsItem = "wom.newsItem.v0"
    static let archiveItem = "wom.archiveItem.v0"
    static let bundle = "wom.bundle.v0"
}
