import Foundation

/// WOM 0.6 Wawa Object Model core object.
/// Mandatory fields: wom, id, type, createdAt.
/// All other fields are optional per WOM 0.6 §6.
struct WOMObject: Codable, Identifiable, Equatable {

    // MARK: - Required (WOM 0.6 §6)

    let wom: String             // "0.7"
    let id: String
    var type: [String]          // ["wom:Message"], ["wom:Post"], etc.
    var createdAt: Date

    // MARK: - Core metadata

    var schema: String?         // "wom.note.v0", "wom.message.v0", etc.
    var context: [String]?      // JSON-LD contexts: schema.org, activitystreams, wom/v0
    var name: String?
    var summary: String?
    var updatedAt: Date?
    var expiresAt: Date?
    var languages: [String]?
    var attributedTo: WOMReference?
    var content: WOMContent?

    // MARK: - Identity layer (§8)

    var identity: WOMIdentity?
    var labels: [WOMLabel]?

    // MARK: - Semantic layers (§7)

    var entities: [WOMReference]?
    var events: [WOMReference]?
    var signals: [WOMReference]?
    var statements: [WOMStatement]?
    var claims: [WOMClaim]?

    // MARK: - Relations & annotations

    var relationships: [WOMRelation]
    var annotations: [WOMAnnotation]?
    var attachments: [WOMReference]

    // MARK: - Classification (§9)

    var classification: WOMClassification?
    var descriptors: [WOMDescriptor]?
    var mappings: [WOMMapping]?
    var availability: [WOMAvailability]?

    // MARK: - Knowledge layer (§10)

    var provenance: WOMProvenance?
    var sources: [WOMSource]?
    var evidence: [WOMEvidence]?
    var references: [WOMReference]?

    // MARK: - Governance (§13)

    var governance: WOMGovernance?

    // MARK: - WOM 0.7 (§9–§12)

    var address: String?          // pseudonymous author address
    var _lite: WOMLite?           // compact transmission metadata
    var _encrypted: WOMEncryptedPayload?  // encrypted content payload

    // MARK: - Space & Time (§10 of WIRC_SPEC)

    var location: WOMLocation?
    var temporal: WOMTemporal?

    // MARK: - Domain-specific layers (§14, §17, §19)

    var measurement: WOMMeasurement?
    var commercial: WOMCommercial?
    var quality: WOMQuality?
    var editorial: WOMEditorial?
    var journalism: WOMJournalism?
    var publication: WOMPublication?
    var rights: WOMRights?
    var archive: WOMArchive?
    var sourceProtection: WOMSourceProtection?

    // MARK: - Integrity & transport (§11, §16)

    var revision: WOMRevision?
    var proof: WOMProof?
    var bindings: WOMBindings?

    // MARK: - Extension data

    var data: [String: String]

    // MARK: - Init

    init(
        id: String,
        type: [String],
        createdAt: Date = Date(),
        schema: String? = nil,
        context: [String]? = nil,
        name: String? = nil,
        summary: String? = nil,
        updatedAt: Date? = nil,
        attributedTo: WOMReference? = nil,
        content: WOMContent? = nil,
        data: [String: String] = [:],
        provenance: WOMProvenance? = nil,
        governance: WOMGovernance? = nil,
        classification: WOMClassification? = nil,
        bindings: WOMBindings? = nil,
        attachments: [WOMReference] = [],
        relationships: [WOMRelation] = []
    ) {
        self.wom = "0.7"
        self.id = id
        self.type = type
        self.createdAt = createdAt
        self.schema = schema
        self.context = context ?? WOMStandardContext.defaults
        self.name = name
        self.summary = summary
        self.updatedAt = updatedAt
        self.attributedTo = attributedTo
        self.content = content
        self.data = data
        self.provenance = provenance
        self.governance = governance
        self.classification = classification
        self.bindings = bindings
        self.attachments = attachments
        self.relationships = relationships

        // Optional layers — nil by default
        self.identity = nil
        self.labels = nil
        self.entities = nil
        self.events = nil
        self.signals = nil
        self.statements = nil
        self.claims = nil
        self.annotations = nil
        self.descriptors = nil
        self.mappings = nil
        self.availability = nil
        self.sources = nil
        self.evidence = nil
        self.references = nil
        self.measurement = nil
        self.commercial = nil
        self.quality = nil
        self.editorial = nil
        self.journalism = nil
        self.publication = nil
        self.rights = nil
        self.archive = nil
        self.sourceProtection = nil
        self.revision = nil
        self.proof = nil
    }
}

// MARK: - Supporting domain types

/// Availability per WOM 0.6 §9.
struct WOMAvailability: Codable, Equatable {
    var object: String?             // object ID
    var status: String              // "available", "unavailable", "restricted", "offline", "deprecated"
    var format: String?             // MIME type or representation format
    var url: String?
    var validFrom: Date?
    var validUntil: Date?
}

/// Location per WIRC_SPEC §10.
struct WOMLocation: Codable, Equatable {
    var type: String?            // "point", "polyline", "polygon"
    var coordinates: [Double]?   // [lon, lat] for point
    var radius: Double?          // relevance radius in meters
    var relevanceScale: String?  // "here", "block", "neighborhood", "city", "region", "global"
    var name: String?            // human-readable place name
}

/// Temporal context per WIRC_SPEC §10.
struct WOMTemporal: Codable, Equatable {
    var type: String?            // "ephemeral", "instantaneous", "eventual", "durable", "permanent", "historical", "recurring"
    var startsAt: Date?
    var endsAt: Date?
    var expiresAt: Date?
    var recurrence: String?      // e.g. "RRULE:FREQ=WEEKLY;BYDAY=TU"
}

/// Measurement per WOM 0.6 §14.
struct WOMMeasurement: Codable, Equatable {
    var eventName: String?
    var observationType: String?    // "observed", "observed_and_inferred", "modelled", "imported"
    var modelled: Bool?
    var confidence: Double?
}

/// Commercial context per WOM 0.6 §14.
struct WOMCommercial: Codable, Equatable {
    var intentStage: String?        // "awareness", "consideration", "decision", "retention"
    var category: String?
    var value: Double?
    var currency: String?
    var attribution: WOMAttribution?
}

struct WOMAttribution: Codable, Equatable {
    var source: String?             // "recommendation", "ad", "search", "direct", "social"
    var recommendedBy: String?      // identity reference
    var campaignId: String?
    var placement: String?
}

/// Quality assessment per WOM 0.6 §7.
struct WOMQuality: Codable, Equatable {
    var score: Double?
    var dimensions: [String: Double]?  // e.g., ["accuracy": 0.9, "completeness": 0.8]
    var assessedBy: String?
    var assessedAt: Date?
}

/// Editorial metadata per WOM 0.6 §17.
struct WOMEditorial: Codable, Equatable {
    var section: String?
    var desk: String?
    var beat: String?
    var materialType: String?
    var storyFormat: String?
    var slug: String?
    var byline: [WOMByline]?
    var dateline: WOMDateline?
    var subjects: [WOMDescriptor]?
}

struct WOMByline: Codable, Equatable {
    var name: String
    var role: String?               // "reporter", "photographer", "editor", "contributor"
}

struct WOMDateline: Codable, Equatable {
    var place: String?
    var date: Date?
}

/// Journalism metadata per WOM 0.6 §17.
struct WOMJournalism: Codable, Equatable {
    var headline: String?
    var kicker: String?
    var deck: String?
    var abstract: String?
    var lead: String?
    var slug: WOMSlug?
}

struct WOMSlug: Codable, Equatable {
    var packaging: String?          // operational slug e.g., "CANADA-HOUSING"
    var wild: String?               // wild slug e.g., "VICTORIA"
}

/// Publication status per WOM 0.6 §17.
struct WOMPublication: Codable, Equatable {
    var status: String?             // draft, editing, ready, embargoed, published, corrected, retracted, archived
    var version: Int?
    var publishedAt: Date?
    var embargoUntil: Date?
}

/// Rights and licensing per WOM 0.6 §17.
struct WOMRights: Codable, Equatable {
    var license: String?
    var aiTrainingUse: String?      // "allowed", "not_allowed", "requires_license"
    var textMiningUse: String?
    var commercialReuse: String?
    var distributionRestriction: String?
}

/// Archive metadata per WOM 0.6 §19.
struct WOMArchive: Codable, Equatable {
    var collectionId: String?
    var seriesId: String?
    var fileId: String?
    var itemId: String?
    var findingAidId: String?
    var custodialHistory: String?
    var accessCondition: String?    // open, restricted, closed, embargoed, owner_only
    var preservationSnapshots: [WOMReference]?
}

/// Version chain revision per WOM 0.7 §10.
struct WOMRevision: Codable, Equatable {
    var version: Int
    var hash: String?            // "sha256:..."
    var previousHash: String?
    var previousSignature: String?
    var updatedAt: Date?
    var updatedBy: String?
}

/// Source protection per WOM 0.6 §18.
struct WOMSourceProtection: Codable, Equatable {
    var sourceKind: String?         // human_source, official_document, public_record, etc.
    var attributionStatus: String?  // on_the_record, anonymous, on_background, deep_background, off_the_record
    var sourceRole: String?         // witness, spokesperson, expert_interview, etc.
    var protectionLevel: String?    // none, low, medium, high
    var canBeQuoted: Bool?
    var canBeParaphrased: Bool?
    var requiresEditorApproval: Bool?
    var quoteStatus: String?        // raw, verified, approved_for_publication, paraphrase_only, etc.
    var legalReviewStatus: String?  // not_required, required, pending, approved, approved_with_changes, blocked
}
