import Foundation

/// Parses RSS 2.0 and Atom 1.0 feeds using Foundation XMLParser (SAX).
/// Detects format by root element: <rss> vs <feed xmlns="http://www.w3.org/2005/Atom">
enum FeedParser {
    static func parse(data: Data, sourceURL: String) throws -> FeedParseResult {
        let delegate = FeedParserDelegate(sourceURL: sourceURL)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            throw parser.parserError ?? FeedError.parseFailed("XML parse error for \(sourceURL)")
        }

        guard delegate.format != .unknown else {
            throw FeedError.parseFailed("Unknown feed format: \(sourceURL)")
        }

        return FeedParseResult(
            title: delegate.feedTitle,
            description: delegate.feedDescription,
            link: delegate.feedLink,
            items: delegate.items
        )
    }
}

// MARK: - XMLParser Delegate

private final class FeedParserDelegate: NSObject, XMLParserDelegate {
    let sourceURL: String

    // Feed-level metadata
    var feedTitle: String?
    var feedDescription: String?
    var feedLink: String?

    // Parsed items
    var items: [FeedItem] = []

    // State
    private(set) var format: FeedFormat = .unknown
    private var currentElementPath: [String] = []
    private var currentText: String = ""

    // Current item being built
    private var currentID: String?
    private var currentTitle: String?
    private var currentLink: String?
    private var currentDescription: String?
    private var currentPublishedAt: Date?
    private var currentAuthor: String?
    private var currentCategory: String?
    private var currentEnclosureURL: String?
    private var currentEnclosureType: String?
    private var currentDuration: String?

    // For RSS link vs Atom link[@rel]
    private var currentLinkRel: String?

    // Date formatters (created lazily to avoid overhead)
    private let rssDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private let isoWithoutFractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    init(sourceURL: String) {
        self.sourceURL = sourceURL
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElementPath.append(elementName)
        currentText = ""

        // Detect format
        if format == .unknown {
            if elementName == "rss" { format = .rss }
            if elementName == "feed" && namespaceURI?.contains("2005/Atom") == true { format = .atom }
        }

        switch format {
        case .rss:
            handleRSSStart(elementName, attributes: attributes)
        case .atom:
            handleAtomStart(elementName, attributes: attributes, namespaceURI: namespaceURI)
        case .unknown:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let path = currentElementPath.joined(separator: ".")

        switch format {
        case .rss:
            handleRSSEnd(elementName, path: path)
        case .atom:
            handleAtomEnd(elementName, path: path, namespaceURI: namespaceURI)
        case .unknown:
            break
        }

        _ = currentElementPath.popLast()
    }

    // MARK: - RSS 2.0

    private func handleRSSStart(_ name: String, attributes: [String: String]) {
        if name == "enclosure" {
            currentEnclosureURL = attributes["url"]
            currentEnclosureType = attributes["type"]
        }
    }

    private func handleRSSEnd(_ name: String, path: String) {
        switch name {
        case "title":
            if path == "rss.channel.title" { feedTitle = currentText.trimmed }
            if path.hasSuffix(".item.title") { currentTitle = currentText.trimmed }
        case "link":
            if path.hasSuffix(".channel.link") { feedLink = currentText.trimmed }
            if path.hasSuffix(".item.link"), currentLink == nil {
                currentLink = currentText.trimmed
            }
        case "description":
            if path.hasSuffix(".channel.description") { feedDescription = currentText.trimmed }
            if path.hasSuffix(".item.description") { currentDescription = currentText.trimmed }
        case "pubDate":
            if let d = parseRSSDate(currentText.trimmed) { currentPublishedAt = d }
        case "guid":
            if path.hasSuffix(".item.guid") { currentID = currentText.trimmed }
        case "author":
            if path.hasSuffix(".item.author") { currentAuthor = currentText.trimmed }
        case "category":
            if path.hasSuffix(".item.category") { currentCategory = currentText.trimmed }
        case "duration":
            if path.hasSuffix(".item.duration") { currentDuration = currentText.trimmed }
        case "item":
            commitItem()
        default:
            break
        }
    }

    // MARK: - Atom 1.0

    private func handleAtomStart(_ name: String, attributes: [String: String],
                                  namespaceURI: String?) {
        if name == "category", let term = attributes["term"], !term.isEmpty {
            currentCategory = term
            return
        }

        if name == "link" {
            currentLinkRel = attributes["rel"] ?? "alternate"
            guard let href = attributes["href"], !href.isEmpty else { return }
            if currentLinkRel == "alternate" {
                currentLink = href
            } else if currentLinkRel == "enclosure" {
                currentEnclosureURL = href
                currentEnclosureType = attributes["type"]
            }
        }
    }

    private func handleAtomEnd(_ name: String, path: String,
                                namespaceURI: String?) {
        let isEntry = path.contains(".entry.")

        switch name {
        case "title":
            if isEntry { currentTitle = currentText.trimmed }
            else { feedTitle = currentText.trimmed }
        case "subtitle":
            if !isEntry { feedDescription = currentText.trimmed }
        case "summary", "content":
            if isEntry, currentDescription == nil { currentDescription = currentText.trimmed }
        case "published":
            if let d = parseISODate(currentText.trimmed) { currentPublishedAt = d }
        case "updated":
            if isEntry, currentPublishedAt == nil, let d = parseISODate(currentText.trimmed) {
                currentPublishedAt = d
            }
        case "name":
            if path.contains(".author.") { currentAuthor = currentText.trimmed }
        case "term":
            if isEntry && path.contains(".category.") { currentCategory = currentText.trimmed }
        case "id":
            if isEntry { currentID = currentText.trimmed }
        case "link":
            // handled in didStartElement
            break
        case "entry":
            commitItem()
        default:
            break
        }
    }

    // MARK: - Commit item

    private func commitItem() {
        guard let title = currentTitle, let link = currentLink else {
            resetItemState()
            return
        }

        let itemID = currentID ?? link

        let item = FeedItem(
            id: itemID,
            title: title,
            link: link,
            description: currentDescription,
            publishedAt: currentPublishedAt,
            author: currentAuthor,
            category: currentCategory,
            enclosureURL: currentEnclosureURL,
            enclosureType: currentEnclosureType,
            duration: currentDuration
        )
        items.append(item)
        resetItemState()
    }

    private func resetItemState() {
        currentID = nil
        currentTitle = nil
        currentLink = nil
        currentDescription = nil
        currentPublishedAt = nil
        currentAuthor = nil
        currentCategory = nil
        currentEnclosureURL = nil
        currentEnclosureType = nil
        currentDuration = nil
        currentLinkRel = nil
    }

    // MARK: - Date parsing

    private func parseRSSDate(_ s: String) -> Date? {
        if let d = rssDateFormatter.date(from: s) { return d }
        // Try ISO with fractional seconds as fallback
        if let d = isoFormatter.date(from: s) { return d }
        // Try ISO without fractional seconds as third fallback
        return isoWithoutFractionalFormatter.date(from: s)
    }

    private func parseISODate(_ s: String) -> Date? {
        if let d = isoFormatter.date(from: s) { return d }
        // Fallback: try without fractional seconds
        return isoWithoutFractionalFormatter.date(from: s)
    }
}

// MARK: - Feed format enum

private enum FeedFormat {
    case unknown
    case rss
    case atom
}

// MARK: - String helper

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
