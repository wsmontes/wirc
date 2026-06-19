import Foundation

/// Encrypted content payload per WOM 0.7.
struct WOMEncryptedPayload: Codable, Equatable {
    var algorithm: String         // "XChaCha20-Poly1305"
    var keyAgreement: String      // "X25519"
    var recipients: [String]      // ["did:key:...", ...] — who can decrypt
    var nonce: String             // base64-encoded nonce
    var ciphertext: String        // base64-encoded encrypted data
}
