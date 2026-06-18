import Foundation

/// Provenance per WOM 0.6 §11.
/// Records origin, actor, process, derivation source, trust, and review status.
struct WOMProvenance: Codable, Equatable {
    /// Origin of the data per WOMOrigin enum values:
    /// user_provided, observed, inferred, modeled, imported,
    /// assistant_generated, remote_peer, system_generated, sensor,
    /// external_protocol, editorial, machine, local_user
    var origin: String

    /// The actor (person, agent, system) that produced this object.
    var actor: WOMReference?

    /// The source object or feed this was derived from.
    var source: WOMReference?

    /// When this specific provenance record was created.
    var createdAt: Date?

    /// Confidence in the transformation (0.0–1.0).
    var confidence: Double?

    /// Review status: none, pending, verified, rejected, needs_review.
    var reviewStatus: String?

    /// Process run that produced this object (optional).
    var processRun: WOMReference?

    // MARK: - Convenience initializers

    /// Creates a provenance record with the given origin.
    init(
        origin: String,
        actor: WOMReference? = nil,
        source: WOMReference? = nil,
        createdAt: Date? = nil,
        confidence: Double? = nil,
        reviewStatus: String? = nil,
        processRun: WOMReference? = nil
    ) {
        self.origin = origin
        self.actor = actor
        self.source = source
        self.createdAt = createdAt
        self.confidence = confidence
        self.reviewStatus = reviewStatus
        self.processRun = processRun
    }

    // MARK: - Standard factories

    /// Remote peer content (IRC message, Mastodon status, RSS feed).
    static func remotePeer(
        source: WOMReference? = nil,
        actor: WOMReference? = nil,
        createdAt: Date? = nil,
        confidence: Double? = 1.0
    ) -> WOMProvenance {
        WOMProvenance(
            origin: WOMOrigin.remotePeer.rawValue,
            actor: actor,
            source: source,
            createdAt: createdAt,
            confidence: confidence,
            reviewStatus: WOMReviewStatus.none.rawValue
        )
    }

    /// Local user generated content.
    static func localUser(createdAt: Date? = nil) -> WOMProvenance {
        WOMProvenance(
            origin: WOMOrigin.userProvided.rawValue,
            actor: WOMReference(id: "local:user", type: ["wom:Person"]),
            createdAt: createdAt ?? Date(),
            confidence: 1.0,
            reviewStatus: WOMReviewStatus.none.rawValue
        )
    }

    /// Assistant (AI agent) generated content.
    static func assistantGenerated(
        agentId: String,
        source: WOMReference? = nil,
        confidence: Double? = nil
    ) -> WOMProvenance {
        WOMProvenance(
            origin: WOMOrigin.assistantGenerated.rawValue,
            actor: WOMReference(id: agentId, type: ["wom:Agent"]),
            source: source,
            createdAt: Date(),
            confidence: confidence,
            reviewStatus: WOMReviewStatus.pending.rawValue
        )
    }

    /// Imported from external protocol or format.
    static func imported(
        source: WOMReference? = nil,
        confidence: Double? = nil
    ) -> WOMProvenance {
        WOMProvenance(
            origin: WOMOrigin.imported.rawValue,
            source: source,
            createdAt: Date(),
            confidence: confidence,
            reviewStatus: WOMReviewStatus.none.rawValue
        )
    }

    /// System-generated event (auto-join, topic change, etc.).
    static func systemGenerated(
        source: WOMReference? = nil
    ) -> WOMProvenance {
        WOMProvenance(
            origin: WOMOrigin.systemGenerated.rawValue,
            source: source,
            createdAt: Date(),
            confidence: 1.0,
            reviewStatus: WOMReviewStatus.none.rawValue
        )
    }

    // MARK: - Computed properties for origin checks

    /// True if this object was created by the local human user.
    var isLocalUser: Bool {
        origin == WOMOrigin.userProvided.rawValue
            || origin == WOMOrigin.localUser.rawValue
    }

    /// True if this object was created by an AI agent/assistant.
    var isAssistantGenerated: Bool {
        origin == WOMOrigin.assistantGenerated.rawValue
    }

    /// True if this object originated from a remote peer (IRC, Mastodon, RSS, etc.).
    var isRemotePeer: Bool {
        origin == WOMOrigin.remotePeer.rawValue
    }

    /// True if this is a system-generated event.
    var isSystemGenerated: Bool {
        origin == WOMOrigin.systemGenerated.rawValue
    }
}
