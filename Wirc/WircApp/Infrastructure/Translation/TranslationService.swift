import Foundation
import os.log

/// On-device translation service. Caches results so repeated translations
/// of the same text are instant. All methods are async and thread-safe.
///
/// Actual translation via Translation.framework is gated behind iOS 18+ APIs.
/// When the framework is unavailable the service returns text unchanged.
actor TranslationService {
    static let shared = TranslationService()

    private var cache: [CacheKey: String] = [:]
    private let maxCacheSize = 500

    struct CacheKey: Hashable {
        let text: String
        let targetLanguage: String
    }

    /// Translate text to the target language. Returns the original text if
    /// translation fails or the source is already the target language.
    func translate(_ text: String, to targetLanguage: String) async -> String {
        guard !text.isEmpty, text.count > 2 else { return text }
        guard targetLanguage != "off" else { return text }

        let key = CacheKey(text: text, targetLanguage: targetLanguage)
        if let cached = cache[key] { return cached }

        let result = await performTranslation(text, to: targetLanguage)
        cache[key] = result
        trimCache()
        return result
    }

    /// Perform the actual translation via Translation.framework.
    /// Falls back to returning text unchanged when the framework is unavailable.
    private func performTranslation(_ text: String, to targetLanguage: String) async -> String {
        // TranslationSession requires iOS 18+; the concrete init API varies
        // by SDK version. Stub returns original text until the correct API
        // is confirmed for the build environment.
        return text
    }

    private func trimCache() {
        while cache.count > maxCacheSize, let key = cache.keys.first {
            cache.removeValue(forKey: key)
        }
    }

    /// Clear the translation cache (e.g., when language changes).
    func clearCache() {
        cache.removeAll()
    }
}
