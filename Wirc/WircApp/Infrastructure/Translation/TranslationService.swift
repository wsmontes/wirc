import Foundation
import Translation

/// On-device translation service. Caches results so repeated translations
/// of the same text are instant. All methods are async and thread-safe.
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

    private func performTranslation(_ text: String, to targetLanguage: String) async -> String {
        guard #available(iOS 17.4, *) else { return text }

        do {
            let configuration = TranslationSession.Configuration(
                source: nil, // auto-detect
                target: Locale.Language(identifier: targetLanguage)
            )
            let session = TranslationSession(configuration: configuration)
            let response = try await session.translate(text)
            // If the response is same as input, source likely matches target
            return response.targetText
        } catch {
            os_log(.debug, "TranslationService: translation failed for '%{public}@': %{public}@",
                   text.prefix(50), error.localizedDescription)
            return text
        }
    }

    private func trimCache() {
        if cache.count > maxCacheSize {
            // Remove oldest entries (Dictionary keeps insertion order in Swift)
            let toRemove = cache.count - maxCacheSize
            cache.removeFirst(min(toRemove, cache.count))
        }
    }

    /// Clear the translation cache (e.g., when language changes).
    func clearCache() {
        cache.removeAll()
    }
}
