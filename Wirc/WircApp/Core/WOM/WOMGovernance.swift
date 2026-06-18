import Foundation

// MARK: - WOM 0.6 Governance & Permissions (§13)

/// Governance and permission model per WOM 0.6 §13.
struct WOMGovernance: Codable, Equatable {
    var purpose: [String]?       // personal_use, messaging, curation, analytics, etc.
    var adsUse: String?          // not_allowed, allowed, requires_explicit_consent, etc.
    var agentUse: String?        // allowed, not_allowed, requires_human_approval
    var sharing: String?         // local_only, direct_recipient, friends_only, public, etc.
    var retention: String?       // e.g. "30d", "1y", "forever", "session"
    var consent: WOMConsent?
    var requiresHumanApproval: Bool?
    var permissionCheckResult: String?  // allowed, denied, requires_human_approval, etc.
}

/// Consent record per WOM 0.6 §13.
struct WOMConsent: Codable, Equatable {
    var status: String           // "granted", "denied", "revoked", "expired", "pending"
    var grantedAt: Date?
    var expiresAt: Date?
    var scope: [String]?         // analytics, personalization, advertising, etc.
    var grantedBy: String?       // identity reference
}

/// Agent delegation per WOM 0.6 §13.
struct WOMAgentDelegation: Codable, Equatable {
    var agentId: String
    var allowedActions: [String]?
    var restrictedActions: [String]?
    var expiresAt: Date?
    var requiresHumanApproval: Bool?
}
