import Foundation

// MARK: - WOM 0.6 Classification, Descriptors & Mappings (§9)

/// Classification per WOM 0.6 §9.
struct WOMClassification: Codable, Equatable {
    var semanticType: String?       // e.g., "commerce.product", "social.post", "journalism.article"
    var dataSubject: String?        // e.g., "local_user", "remote_peer", "organisation"
    var origin: String?             // per WOMOrigin enum
    var sensitivity: String?        // per WOMDataSensitivity enum
    var category: WOMCategory?
    var topics: [String]?
    var confidence: Double?
}

struct WOMCategory: Codable, Equatable {
    var scheme: String?             // e.g., "schema.org", "iptc-media-topics"
    var value: String
}

/// Descriptor per WOM 0.6 §9 — faceted classification tags.
struct WOMDescriptor: Codable, Equatable {
    var scheme: String              // e.g., "wom.commerce.category"
    var value: String
    var weight: Double?
    var confidence: Double?
    var origin: String?             // per WOMOrigin enum
    var reviewStatus: String?       // per WOMReviewStatus enum
    var categoryRole: String?       // per WOMCategoryRole enum
}

/// External identifier mapping per WOM 0.6 §8.
struct WOMMapping: Codable, Equatable {
    var subject: String?            // WOM-internal entity ID
    var object: String              // external identifier
    var scheme: String?             // e.g., "isni", "doi", "wikidata", "twitter"
    var mappingStatus: String?      // "exact", "broad", "narrow", "related", "deprecated"
    var origin: String?             // per WOMOrigin enum
    var confidence: Double?
}
