import Foundation

/// Content per WOM 0.6 §6.
struct WOMContent: Codable, Equatable {
    var format: String      // "text/plain", "text/html", "text/markdown", "application/json"
    var text: String?
    var language: String?   // BCP 47 language tag, e.g., "pt-BR", "en", "fr-CA"
    var mediaType: String?  // broader MIME type category for display hints
}
