import Foundation

// MARK: - WOM 0.6 Annotations Layer (§7)

/// Annotation per W3C Web Annotation / WOM 0.6.
struct WOMAnnotation: Codable, Equatable {
    var id: String?
    var type: String?               // "Annotation", "Highlight", "Comment"
    var motivation: String?         // "commenting", "tagging", "identifying", "classifying"
    var target: WOMTarget?
    var body: WOMAnnotationBody?
    var creator: WOMReference?
    var createdAt: Date?
}

struct WOMTarget: Codable, Equatable {
    var id: String                  // target object ID
    var selector: WOMSelector?      // fragment selector
}

struct WOMSelector: Codable, Equatable {
    var type: String?               // "TextQuoteSelector", "FragmentSelector", "XPathSelector"
    var exact: String?              // the quoted text
    var prefix: String?
    var suffix: String?
    var start: Int?
    var end: Int?
}

struct WOMAnnotationBody: Codable, Equatable {
    var format: String?             // "text/plain", "text/html"
    var text: String?
    var reference: WOMReference?    // reference to another object
}
