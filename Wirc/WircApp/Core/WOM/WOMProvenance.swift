import Foundation

struct WOMProvenance: Codable, Equatable {
    var origin: String          // "remotePeer", "localUser"
    var actor: WOMReference?
    var source: WOMReference?
    var createdAt: Date?
    var confidence: Double?
    var reviewStatus: String?   // "none", "verified", "rejected"
}
