import Foundation

/// Compact transmission metadata per WOM 0.7 §9.
struct WOMLite: Codable, Equatable {
    var fullHash: String          // "sha256:..." — hash of the complete WOM
    var fullSize: Int             // bytes of the complete WOM JSON
    var version: Int              // revision version
    var previousHash: String?     // previous version hash (chain)
    var previousSignature: String? // previous version signature (chain)
    var fields: [String]?         // top-level field names omitted from Lite
}
