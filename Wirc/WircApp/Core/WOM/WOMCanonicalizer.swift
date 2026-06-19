import Foundation
import CryptoKit

/// Deterministic JSON canonicalization for WOM objects.
/// Same input always produces the same hash, regardless of who computes it.
enum WOMCanonicalizer {

    /// Fields excluded from canonicalization (not part of content integrity).
    private static let excludedFields: Set<String> = ["_lite", "_encrypted", "proof"]

    /// Produce canonical JSON bytes sorted alphabetically, no whitespace, NFC normalized.
    static func canonicalize(_ object: WOMObject) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(object)

        // Decode to dictionary, remove excluded fields, re-encode with sorted keys
        guard var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CanonicalizeError.notADictionary
        }

        for key in excludedFields {
            dict.removeValue(forKey: key)
        }

        // Recursively sort all nested dictionaries
        let sorted = sortKeysRecursively(dict)

        let canonicalData = try JSONSerialization.data(withJSONObject: sorted, options: [])

        // Unicode NFC normalization
        guard let nfc = String(data: canonicalData, encoding: .utf8)?.precomposedStringWithCanonicalMapping,
              let result = nfc.data(using: .utf8) else {
            throw CanonicalizeError.nfcFailed
        }

        return result
    }

    /// sha256 hash of the canonical JSON.
    static func hash(_ object: WOMObject) throws -> String {
        let data = try canonicalize(object)
        let digest = SHA256.hash(data: data)
        return "sha256:\(digest.compactMap { String(format: "%02x", $0) }.joined())"
    }

    // MARK: - Helpers

    private static func sortKeysRecursively(_ value: Any) -> Any {
        switch value {
        case let dict as [String: Any]:
            var sorted: [String: Any] = [:]
            for key in dict.keys.sorted() {
                sorted[key] = sortKeysRecursively(dict[key]!)
            }
            return sorted
        case let array as [Any]:
            return array.map { sortKeysRecursively($0) }
        default:
            return value
        }
    }

    enum CanonicalizeError: LocalizedError {
        case notADictionary, nfcFailed
        var errorDescription: String? {
            switch self {
            case .notADictionary: return "WOMObject did not encode to a JSON dictionary"
            case .nfcFailed: return "NFC normalization failed"
            }
        }
    }
}
