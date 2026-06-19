import Foundation
import CryptoKit

/// Cryptographic operations for WOM 0.7: Ed25519 signatures, pseudonymous addresses,
/// and XChaCha20-Poly1305 encryption for restricted-sharing content.
enum WOMCrypto {

    // MARK: - Signing (Ed25519)

    /// Sign a WOMObject's canonical hash with an Ed25519 private key.
    /// Returns the base64-encoded signature string.
    static func sign(_ object: WOMObject, privateKey: Curve25519.Signing.PrivateKey) throws -> String {
        let hash = try WOMCanonicalizer.hash(object)
        let hashData = Data(hash.utf8)
        let signature = try privateKey.signature(for: hashData)
        return signature.base64EncodedString()
    }

    /// Verify an Ed25519 signature against a WOMObject's canonical hash.
    static func verify(_ object: WOMObject, signature base64Sig: String, publicKey: Curve25519.Signing.PublicKey) throws -> Bool {
        let hash = try WOMCanonicalizer.hash(object)
        let hashData = Data(hash.utf8)
        guard let sigData = Data(base64Encoded: base64Sig) else { return false }
        return publicKey.isValidSignature(sigData, for: hashData)
    }

    /// Sign arbitrary data for chain linking (hash of hash+sig of previous version).
    static func signData(_ data: Data, privateKey: Curve25519.Signing.PrivateKey) throws -> String {
        let signature = try privateKey.signature(for: data)
        return signature.base64EncodedString()
    }

    static func verifyData(_ data: Data, signature base64Sig: String, publicKey: Curve25519.Signing.PublicKey) -> Bool {
        guard let sigData = Data(base64Encoded: base64Sig) else { return false }
        return publicKey.isValidSignature(sigData, for: data)
    }

    // MARK: - Keys

    /// Generate a new Ed25519 signing key pair.
    static func generateSigningKey() -> Curve25519.Signing.PrivateKey {
        Curve25519.Signing.PrivateKey()
    }

    /// Generate a new X25519 key agreement key pair.
    static func generateKeyAgreementKey() -> Curve25519.KeyAgreement.PrivateKey {
        Curve25519.KeyAgreement.PrivateKey()
    }

    /// Raw public key bytes (32 bytes).
    static func publicKeyBytes(_ key: Curve25519.Signing.PublicKey) -> Data {
        key.rawRepresentation
    }

    // MARK: - Pseudonymous Address

    /// Generate a pseudonymous address: sha256(pubkey) truncated to 20 bytes, hex-encoded.
    ///
    /// Full RIPEMD160(SHA256(pubkey)) would match Bitcoin's address model exactly.
    /// iOS CryptoKit does not include RIPEMD160, so we use SHA256-truncated as an
    /// initial implementation. The 20-byte output size is maintained for compatibility
    /// when RIPEMD160 is added later.
    static func address(_ publicKey: Curve25519.Signing.PublicKey) -> String {
        let raw = publicKey.rawRepresentation  // 32 bytes
        let hash = SHA256.hash(data: raw)
        let truncated = hash.prefix(20)        // 20 bytes
        return "addr:\(truncated.compactMap { String(format: "%02x", $0) }.joined())"
    }

    /// Verify that a public key matches a pseudonymous address.
    static func verifyAddress(_ address: String, publicKey: Curve25519.Signing.PublicKey) -> Bool {
        let computed = WOMCrypto.address(publicKey)
        return computed == address
    }

    // MARK: - Encryption (XChaCha20-Poly1305 stub)

    /// Encrypt content + data fields for restricted sharing.
    /// Stub: returns a placeholder encrypted payload.
    /// Full implementation requires symmetric key derivation from key agreement.
    static func encrypt(
        _ object: WOMObject,
        recipients: [Curve25519.KeyAgreement.PublicKey]
    ) throws -> WOMEncryptedPayload {
        // Stub — full XChaCha20-Poly1305 with X25519 key agreement coming in next phase
        let placeholder = Data("encrypted-\(object.id)".utf8).base64EncodedString()
        return WOMEncryptedPayload(
            algorithm: "XChaCha20-Poly1305",
            keyAgreement: "X25519",
            recipients: recipients.map { "did:key:\($0.rawRepresentation.base64EncodedString().prefix(16))" },
            nonce: Data(count: 24).base64EncodedString(),
            ciphertext: placeholder
        )
    }

    /// Decrypt content + data from an encrypted payload. Stub.
    static func decrypt(
        _ payload: WOMEncryptedPayload,
        privateKey: Curve25519.KeyAgreement.PrivateKey
    ) throws -> (content: WOMContent?, data: [String: String]?) {
        // Stub
        return (nil, nil)
    }
}

// MARK: - PublicKey conformance for dictionary storage

extension Curve25519.Signing.PublicKey: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawRepresentation)
    }
    public static func == (lhs: Curve25519.Signing.PublicKey, rhs: Curve25519.Signing.PublicKey) -> Bool {
        lhs.rawRepresentation == rhs.rawRepresentation
    }
}

extension Curve25519.KeyAgreement.PublicKey: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawRepresentation)
    }
    public static func == (lhs: Curve25519.KeyAgreement.PublicKey, rhs: Curve25519.KeyAgreement.PublicKey) -> Bool {
        lhs.rawRepresentation == rhs.rawRepresentation
    }
}
