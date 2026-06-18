import Foundation

// MARK: - WOM 0.6 Knowledge Layer (§10)

/// A claim — assertion pending verification, inferred, or contested.
struct WOMClaim: Codable, Equatable {
    var subject: String?            // entity the claim is about
    var property: String?           // predicate / property
    var value: String?              // asserted value
    var qualifiers: [WOMQualifier]?
    var references: [WOMReference]?
    var rank: String?               // preferred, normal, deprecated, contested
    var verificationStatus: String? // verified, unverified, disputed, pending
    var confidence: Double?
}

/// A statement — verified, structured assertion with references and rank.
struct WOMStatement: Codable, Equatable {
    var id: String?
    var type: [String]?             // ["wom:Statement"]
    var subject: String
    var property: String
    var value: String
    var qualifiers: [WOMQualifier]?
    var references: [WOMReference]?
    var rank: String?               // preferred, normal, deprecated, contested
    var verificationStatus: String? // verified, unverified, disputed, pending
}

struct WOMQualifier: Codable, Equatable {
    var property: String            // e.g., "wom:datePrecision"
    var value: String               // e.g., "year"
}

/// A source — citable or consultable origin of information.
struct WOMSource: Codable, Equatable {
    var id: String?
    var type: [String]?             // ["wom:Source"]
    var name: String?
    var description: String?
    var url: String?
    var reliability: String?        // verified, trusted, unknown, disputed, unreliable
    var sourceKind: String?         // human_source, official_document, public_record, etc.
    var attributionStatus: String?  // on_the_record, anonymous, on_background, etc.
    var protectionLevel: String?    // none, low, medium, high
}

/// Evidence — specific material: excerpt, message, document, audio, event.
struct WOMEvidence: Codable, Equatable {
    var id: String?
    var type: [String]?             // ["wom:Evidence"]
    var source: WOMReference?       // points to source
    var selector: WOMSelector?      // fragment within source
    var artifact: WOMReference?     // points to artifact (image, audio, document)
    var capturedAt: Date?
    var format: String?             // MIME type of evidence
}

/// Citation per WOM 0.6 §10.
struct WOMCitation: Codable, Equatable {
    var id: String?
    var reference: WOMReference     // the source/evidence being cited
    var context: String?            // why this citation is relevant
    var position: String?           // "body", "footnote", "endnote", "inline"
}
