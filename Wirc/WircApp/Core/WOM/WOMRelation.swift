import Foundation

struct WOMRelation: Codable, Identifiable, Equatable {
    var id: String?
    var type: String            // "wom:references", "wom:trusts"
    var subject: String?
    var object: String
    var createdAt: Date?
    var confidence: Double?
    var provenance: WOMProvenance?
}
