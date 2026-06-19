import Foundation

/// Ed25519 signature proof per WOM 0.7.
struct WOMProof: Codable, Equatable {
    var type: String              // "Ed25519"
    var target: String            // "sha256:..." — the hash being signed
    var signature: String         // base64-encoded Ed25519 signature
    var verificationMethod: String // "did:key:..." or pubkey reference
}
