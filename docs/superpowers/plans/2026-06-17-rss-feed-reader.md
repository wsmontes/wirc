# RSS Feed Reader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add RSS/Atom feed reader to WIRC — subscribe to blogs, YouTube, podcasts, GitHub releases via URL or OPML import, with feed items translated to WOM objects and rendered as cards in the Feed tab.

**Architecture:** Four-layer pipeline mirroring the existing IRC pattern: FeedFetcher (HTTP with ETag + auto-discovery + OPML) → FeedParser (XMLParser-based RSS/Atom) → FeedToWOMAdapter (type mapping per source) → JSONFileStore (persistent WOMStore on disk). AppState wires it all together; FeedView renders per-type cards.

**Tech Stack:** Swift 5.9+, SwiftUI, iOS 17, URLSession, XMLParser (Foundation), zero external dependencies, Codable persistence, BGAppRefreshTask for background refresh.

## Global Constraints

- Target: iOS 17.0+
- No external SPM dependencies
- URLSession for all HTTP I/O (no Alamofire, no async-http-client)
- XMLParser (Foundation SAX) for feed parsing (no third-party XML lib)
- Codable for all persistence
- Views render WOMObject; never FeedItem directly
- Feed logic stays in Infrastructure/Feed; WOM stays in Core/WOM
- Xcode project: standard .xcodeproj named `Wirc.xcodeproj`

---

### Task 1: Feed models — FeedItem, FeedSubscription, FeedSourceType, FeedParseResult

**Files:**
- Create: `Wirc/WircApp/Infrastructure/Feed/FeedItem.swift`
- Create: `Wirc/WircApp/Infrastructure/Feed/FeedSubscription.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `FeedItem` (Codable, Equatable), `FeedSubscription` (Codable, Identifiable, Equatable), `FeedSourceType` enum, `FeedParseResult` struct

- [ ] **Step 1: Create Feed directory**

```bash
mkdir -p Wirc/WircApp/Infrastructure/Feed
```

- [ ] **Step 2: Write FeedItem.swift**

```swift
import Foundation

/// Intermediate struct representing one item parsed from an RSS or Atom feed.
/// Analogous to IRCMessage — raw parsed data before conversion to WOM.
struct FeedItem: Codable, Equatable {
    let id: String              // guid (RSS) or id (Atom), fallback: link
    let title: String
    let link: String            // canonical URL
    let description: String?    // plain text or HTML summary
    let publishedAt: Date?

    let author: String?
    let category: String?
    let enclosureURL: String?   // media: image, audio, video thumbnail
    let enclosureType: String?  // MIME type
    let duration: String?       // podcast/YouTube duration string
}
```

- [ ] **Step 3: Write FeedSubscription.swift**

```swift
import Foundation

enum FeedSourceType: String, Codable, CaseIterable {
    case rss
    case atom
    case youtube
    case github
    case podcast
}

struct FeedSubscription: Codable, Identifiable, Equatable {
    let id: UUID
    var feedURL: String             // https://example.com/feed.xml
    var title: String               // parsed from feed on first fetch
    var sourceType: FeedSourceType  // determines WOM type mapping
    var tags: [String]              // user-assigned; AI later
    var lastFetchedAt: Date?
    var etag: String?               // HTTP ETag for conditional GET
    var lastModified: String?       // HTTP Last-Modified header
    var errorCount: Int             // consecutive failures; auto-pause after threshold

    init(
        id: UUID = UUID(),
        feedURL: String,
        title: String = "",
        sourceType: FeedSourceType = .rss,
        tags: [String] = [],
        lastFetchedAt: Date? = nil,
        etag: String? = nil,
        lastModified: String? = nil,
        errorCount: Int = 0
    ) {
        self.id = id
        self.feedURL = feedURL
        self.title = title
        self.sourceType = sourceType
        self.tags = tags
        self.lastFetchedAt = lastFetchedAt
        self.etag = etag
        self.lastModified = lastModified
        self.errorCount = errorCount
    }
}

/// Result of parsing a feed: feed-level metadata + items
struct FeedParseResult {
    let title: String?
    let description: String?
    let link: String?
    let items: [FeedItem]
}

/// One outline entry from an OPML file
struct OPMLOutline: Codable {
    let title: String?
    let xmlURL: String?      // feed URL
    let htmlURL: String?     // site URL
    let folderName: String?  // parent folder (used as initial tag)
}
```

- [ ] **Step 4: Add new files to Xcode project**

Open Xcode, drag `Wirc/WircApp/Infrastructure/Feed/` folder into project navigator under `Infrastructure` group, select "Create groups". Ensure both new files have target membership checked.

- [ ] **Step 5: Build to verify**

In Xcode: Product → Build (⌘B). Expected: Build Succeeded.

- [ ] **Step 6: Commit**

```bash
git add Wirc/WircApp/Infrastructure/Feed/
git commit -m "feat: add FeedItem, FeedSubscription, FeedParseResult models

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: JSONFileStore — persistent WOMStore on disk

**Files:**
- Create: `Wirc/WircApp/Infrastructure/Persistence/JSONFileStore.swift`

**Interfaces:**
- Consumes: `WOMStore` protocol (existing), `WOMObject` (existing)
- Produces: `final class JSONFileStore: WOMStore` — `save(_:)`, `saveMany(_:)`, `get(id:)`, `list(type:)`, `delete(id:)`, `all()`, `contains(url:)` for dedup

- [ ] **Step 1: Write JSONFileStore.swift**

```swift
import Foundation

/// Persistent WOMStore backed by individual JSON files on disk.
/// One file per WOMObject: ~/Documents/wirc/objects/{id}.json
/// Maintains an in-memory index for fast queries.
final class JSONFileStore: WOMStore {
    private var index: [String: WOMObject] = [:]
    private let objectsDir: URL
    private let queue = DispatchQueue(label: "wirc.jsonfilestore", attributes: .concurrent)

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        objectsDir = docs.appendingPathComponent("wirc/objects", isDirectory: true)
        try? FileManager.default.createDirectory(at: objectsDir, withIntermediateDirectories: true)
        loadIndex()
    }

    // MARK: - WOMStore

    func save(_ object: WOMObject) async throws {
        queue.async(flags: .barrier) { [weak self] in
            self?.index[object.id] = object
            self?.writeObject(object)
        }
    }

    func saveMany(_ objects: [WOMObject]) async throws {
        queue.async(flags: .barrier) { [weak self] in
            for obj in objects {
                self?.index[obj.id] = obj
                self?.writeObject(obj)
            }
        }
    }

    func get(id: String) async throws -> WOMObject? {
        queue.sync { index[id] }
    }

    func list(type: String?) async throws -> [WOMObject] {
        queue.sync {
            let all = Array(index.values)
            guard let type = type else { return all }
            return all.filter { $0.type.contains(type) }
        }
    }

    func delete(id: String) async throws {
        queue.async(flags: .barrier) { [weak self] in
            self?.index.removeValue(forKey: id)
            let url = self?.fileURL(for: id)
            if let url = url { try? FileManager.default.removeItem(at: url) }
        }
    }

    func all() async throws -> [WOMObject] {
        queue.sync { Array(index.values) }
    }

    // MARK: - Dedup

    /// Returns true if an object with the given canonical URL already exists.
    func contains(canonicalURL: String) -> Bool {
        queue.sync {
            index.values.contains { $0.data["canonicalUrl"] == canonicalURL }
        }
    }

    /// Returns count of stored objects (for tests/debug).
    var count: Int {
        queue.sync { index.count }
    }

    // MARK: - Private

    private func fileURL(for id: String) -> URL {
        let safe = id.replacingOccurrences(of: "/", with: "_")
                      .replacingOccurrences(of: ":", with: "_")
        return objectsDir.appendingPathComponent("\(safe).json")
    }

    private func writeObject(_ object: WOMObject) {
        guard let data = try? JSONEncoder().encode(object) else { return }
        let url = fileURL(for: object.id)
        try? data.write(to: url, options: .atomic)
    }

    private func loadIndex() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: objectsDir, includingPropertiesForKeys: nil
        ) else { return }
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONDecoder().decode(WOMObject.self, from: data) else { continue }
            index[obj.id] = obj
        }
    }
}
```

- [ ] **Step 2: Add to Xcode project and build**

Drag `JSONFileStore.swift` into `Infrastructure/Persistence` group. ⌘B. Expected: Build Succeeded.

- [ ] **Step 3: Commit**

```bash
git add Wirc/WircApp/Infrastructure/Persistence/JSONFileStore.swift
git commit -m "feat: add JSONFileStore — persistent WOMStore on disk

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: FeedSubscriptionStore — CRUD for subscriptions

**Files:**
- Create: `Wirc/WircApp/Infrastructure/Feed/FeedSubscriptionStore.swift`

**Interfaces:**
- Consumes: `FeedSubscription` (Task 1)
- Produces: `final class FeedSubscriptionStore` — `subscriptions: [FeedSubscription]`, `add(_:)`, `remove(id:)`, `update(_:)`, `save()`, `load()`

- [ ] **Step 1: Write FeedSubscriptionStore.swift**

```swift
import Foundation

/// Persists FeedSubscriptions as a single JSON array file.
/// Thread-safe via a serial queue.
final class FeedSubscriptionStore {
    private(set) var subscriptions: [FeedSubscription] = []
    private let fileURL: URL
    private let queue = DispatchQueue(label: "wirc.subscriptionstore")

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("wirc/subscriptions.json")
        load()
    }

    func add(_ subscription: FeedSubscription) {
        queue.sync {
            subscriptions.append(subscription)
            persist()
        }
    }

    func addMany(_ newSubscriptions: [FeedSubscription]) {
        queue.sync {
            subscriptions.append(contentsOf: newSubscriptions)
            persist()
        }
    }

    func remove(id: UUID) {
        queue.sync {
            subscriptions.removeAll { $0.id == id }
            persist()
        }
    }

    func update(_ subscription: FeedSubscription) {
        queue.sync {
            if let idx = subscriptions.firstIndex(where: { $0.id == subscription.id }) {
                subscriptions[idx] = subscription
                persist()
            }
        }
    }

    func get(id: UUID) -> FeedSubscription? {
        queue.sync {
            subscriptions.first { $0.id == id }
        }
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(subscriptions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([FeedSubscription].self, from: data) else { return }
        subscriptions = saved
    }
}
```

- [ ] **Step 2: Build to verify**

⌘B. Expected: Build Succeeded.

- [ ] **Step 3: Commit**

```bash
git add Wirc/WircApp/Infrastructure/Feed/FeedSubscriptionStore.swift
git commit -m "feat: add FeedSubscriptionStore with JSON file persistence

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: FeedFetcher — HTTP fetch, auto-discovery, OPML import

**Files:**
- Create: `Wirc/WircApp/Infrastructure/Feed/FeedFetcher.swift`

**Interfaces:**
- Consumes: `FeedSubscription` (Task 1)
- Produces: `final class FeedFetcher` — `fetch(subscription:) -> (Data, HTTPURLResponse)`, `discoverFeed(from:) -> [URL]`, `parseOPML(_:) -> [OPMLOutline]`

- [ ] **Step 1: Write FeedFetcher.swift**

```swift
import Foundation

final class FeedFetcher {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)
    }

    // MARK: - Feed fetching with conditional GET

    /// Fetch a feed. Uses ETag/Last-Modified from the subscription for conditional GET.
    /// Returns the response so callers can extract updated headers.
    func fetch(subscription: FeedSubscription) async throws -> (Data, URLResponse) {
        guard let url = URL(string: subscription.feedURL) else {
            throw FeedError.invalidURL(subscription.feedURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        if let etag = subscription.etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastMod = subscription.lastModified, !lastMod.isEmpty {
            request.setValue(lastMod, forHTTPHeaderField: "If-Modified-Since")
        }

        let (data, response) = try await session.data(for: request)
        return (data, response)
    }

    // MARK: - URL auto-discovery

    /// Given a non-feed URL (website, YouTube channel, etc.), discover feed URLs.
    func discoverFeed(from url: URL) async throws -> [URL] {
        let host = url.host ?? ""

        // YouTube: resolve @handle or /channel/ URL to RSS
        if host.contains("youtube.com") || host.contains("youtu.be") {
            return try await discoverYouTubeFeed(from: url)
        }

        // GitHub: append .atom to releases page
        if host.contains("github.com"), url.pathComponents.count >= 3 {
            let user = url.pathComponents[1]
            let repo = url.pathComponents[2]
            if let feedURL = URL(string: "https://github.com/\(user)/\(repo)/releases.atom") {
                return [feedURL]
            }
        }

        // Generic: look for <link rel="alternate"> in HTML
        return try await discoverGenericFeed(from: url)
    }

    private func discoverGenericFeed(from url: URL) async throws -> [URL] {
        let (data, _) = try await session.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else { return [] }

        var feedURLs: [URL] = []

        // Scan for <link rel="alternate" type="application/rss+xml" href="...">
        // and <link rel="alternate" type="application/atom+xml" href="...">
        let patterns = [
            #"<link[^>]*rel=["']alternate["'][^>]*type=["']application/(?:rss|atom)\+xml["'][^>]*href=["']([^"']+)["']"#,
            #"<link[^>]*type=["']application/(?:rss|atom)\+xml["'][^>]*rel=["']alternate["'][^>]*href=["']([^"']+)["']"#,
            #"<link[^>]*href=["']([^"']+(?:rss|atom|feed|xml)[^"']*)["'][^>]*>"#  // fallback: href with feed-ish path
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            let matches = regex.matches(in: html, options: [], range: range)
            for match in matches {
                if match.numberOfRanges >= 2,
                   let r = Range(match.range(at: 1), in: html) {
                    let href = String(html[r])
                        .replacingOccurrences(of: "&amp;", with: "&")
                    if let resolved = resolveURL(href, relativeTo: url) {
                        feedURLs.append(resolved)
                    }
                }
            }
            if !feedURLs.isEmpty { break }
        }

        return feedURLs
    }

    private func discoverYouTubeFeed(from url: URL) async throws -> [URL] {
        let (data, _) = try await session.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else { return [] }

        // Look for <meta itemprop="channelId" content="UC...">
        let pattern = #"<meta[^>]*itemprop=["']channelId["'][^>]*content=["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        if let match = regex.firstMatch(in: html, options: [], range: range),
           match.numberOfRanges >= 2,
           let r = Range(match.range(at: 1), in: html) {
            let channelId = String(html[r])
            if let feedURL = URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelId)") {
                return [feedURL]
            }
        }

        return []
    }

    // MARK: - OPML import

    func parseOPML(_ data: Data) throws -> [OPMLOutline] {
        let parser = OPMLParser(data: data)
        return try parser.parse()
    }

    // MARK: - Helpers

    private func resolveURL(_ href: String, relativeTo base: URL) -> URL? {
        if let absolute = URL(string: href), absolute.scheme != nil {
            return absolute
        }
        return URL(string: href, relativeTo: base)?.absoluteURL
    }
}

// MARK: - OPML Parser (internal)

private final class OPMLParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var outlines: [OPMLOutline] = []
    private var currentFolder: String?
    private var currentText: String = ""
    private var parsingOutline = false
    private var currentTitle: String?
    private var currentXMLURL: String?
    private var currentHTMLURL: String?
    private var folderStack: [String] = []

    init(data: Data) {
        parser = XMLParser(data: data)
        super.init()
        parser.delegate = self
    }

    func parse() throws -> [OPMLOutline] {
        guard parser.parse() else {
            throw parser.parserError ?? FeedError.parseFailed("OPML parse error")
        }
        return outlines
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        if elementName == "outline" {
            parsingOutline = true
            currentTitle = attributes["title"] ?? attributes["text"]
            currentXMLURL = attributes["xmlUrl"]
            currentHTMLURL = attributes["htmlUrl"]
            currentText = ""

            // If this outline has no xmlUrl, it's a folder
            if currentXMLURL == nil, let folderTitle = currentTitle {
                folderStack.append(folderTitle)
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if elementName == "outline" {
            if let xmlURL = currentXMLURL {
                let folder = folderStack.last
                outlines.append(OPMLOutline(
                    title: currentTitle,
                    xmlURL: xmlURL,
                    htmlURL: currentHTMLURL,
                    folderName: folder
                ))
            } else {
                // Was a folder — pop it
                _ = folderStack.popLast()
            }
            parsingOutline = false
            currentTitle = nil
            currentXMLURL = nil
            currentHTMLURL = nil
            currentText = ""
        }
    }
}

// MARK: - FeedError

enum FeedError: Error, LocalizedError {
    case invalidURL(String)
    case parseFailed(String)
    case notModified
    case tooManyFailures

    var errorDescription: String? {
        switch self {
        case .invalidURL(let u): return "Invalid URL: \(u)"
        case .parseFailed(let msg): return "Parse error: \(msg)"
        case .notModified: return "Not modified"
        case .tooManyFailures: return "Feed paused after repeated failures"
        }
    }
}
```

- [ ] **Step 2: Build to verify**

⌘B. Expected: Build Succeeded.

- [ ] **Step 3: Commit**

```bash
git add Wirc/WircApp/Infrastructure/Feed/FeedFetcher.swift
git commit -m "feat: add FeedFetcher with conditional GET, auto-discovery, OPML

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: FeedParser — RSS 2.0 + Atom 1.0 via XMLParser

**Files:**
- Create: `Wirc/WircApp/Infrastructure/Feed/FeedParser.swift`

**Interfaces:**
- Consumes: `FeedItem`, `FeedParseResult` (Task 1)
- Produces: `enum FeedParser` with `static func parse(data:sourceURL:) throws -> FeedParseResult`

- [ ] **Step 1: Write FeedParser.swift**

```swift
import Foundation

/// Parses RSS 2.0 and Atom 1.0 feeds using Foundation XMLParser (SAX).
/// Detects format by root element: <rss> vs <feed xmlns="http://www.w3.org/2005/Atom">
enum FeedParser {
    static func parse(data: Data, sourceURL: String) throws -> FeedParseResult {
        let delegate = FeedParserDelegate(sourceURL: sourceURL)
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw parser.parserError ?? FeedError.parseFailed("XML parse error for \(sourceURL)")
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
    private var format: FeedFormat = .unknown
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
        if name == "link", currentElementPath.contains("item") {
            // RSS <link> inside <item> — text will be captured in foundCharacters
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
            currentID = currentText.trimmed
        case "author":
            if path.hasSuffix(".item.author") { currentAuthor = currentText.trimmed }
        case "category":
            if path.hasSuffix(".item.category") { currentCategory = currentText.trimmed }
        case "duration":
            currentDuration = currentText.trimmed
        case "item":
            commitItem()
        default:
            break
        }
    }

    // MARK: - Atom 1.0

    private func handleAtomStart(_ name: String, attributes: [String: String],
                                  namespaceURI: String?) {
        if name == "link" {
            currentLinkRel = attributes["rel"] ?? "alternate"
            let href = attributes["href"] ?? ""
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
        // Try ISO as fallback
        return isoFormatter.date(from: s)
    }

    private func parseISODate(_ s: String) -> Date? {
        if let d = isoFormatter.date(from: s) { return d }
        // Fallback: try without fractional seconds
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
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
```

- [ ] **Step 2: Build to verify**

⌘B. Expected: Build Succeeded.

- [ ] **Step 3: Commit**

```bash
git add Wirc/WircApp/Infrastructure/Feed/FeedParser.swift
git commit -m "feat: add FeedParser — RSS 2.0 + Atom 1.0 via XMLParser

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: FeedToWOMAdapter — FeedItem → WOMObject

**Files:**
- Create: `Wirc/WircApp/Infrastructure/Feed/FeedToWOMAdapter.swift`

**Interfaces:**
- Consumes: `FeedItem`, `FeedSubscription`, `FeedSourceType` (Task 1), `WOMObject`, `WOMContent`, `WOMReference`, `WOMProvenance`, `WOMIDGenerator` (existing)
- Produces: `final class FeedToWOMAdapter` with `func convert(items:subscription:store:) -> [WOMObject]`

- [ ] **Step 1: Write FeedToWOMAdapter.swift**

```swift
import Foundation

/// Converts parsed FeedItems into WOMObjects.
/// Type mapping is driven by the subscription's sourceType.
/// Mirrors IRCToWOMAdapter in pattern.
final class FeedToWOMAdapter {

    /// Convert feed items to WOM objects, skipping items already in the store (dedup by canonicalUrl).
    func convert(
        items: [FeedItem],
        subscription: FeedSubscription,
        store: WOMStore
    ) async -> [WOMObject] {
        let existingURLs = await existingCanonicalURLs(in: store)
        return items.compactMap { item in
            guard !existingURLs.contains(item.link) else { return nil }
            return convertItem(item, subscription: subscription)
        }
    }

    /// Convert a single FeedItem with no dedup check (for direct use).
    func convertSingle(item: FeedItem, subscription: FeedSubscription) -> WOMObject {
        convertItem(item, subscription: subscription)
    }

    // MARK: - Private

    private func existingCanonicalURLs(in store: WOMStore) async -> Set<String> {
        guard let all = try? await store.all() else { return [] }
        return Set(all.compactMap { $0.data["canonicalUrl"] })
    }

    private func convertItem(_ item: FeedItem, subscription: FeedSubscription) -> WOMObject {
        let types = womTypes(for: subscription.sourceType)
        let objectID = WOMIDGenerator.generate(type: "post")

        var data: [String: String] = [
            "network": "rss",
            "canonicalUrl": item.link,
            "feedTitle": subscription.title,
            "feedURL": subscription.feedURL,
            "sourceType": subscription.sourceType.rawValue
        ]

        if let author = item.author { data["author"] = author }
        if let category = item.category { data["category"] = category }
        if let duration = item.duration { data["duration"] = duration }
        if let encURL = item.enclosureURL { data["enclosureURL"] = encURL }
        if let encType = item.enclosureType { data["enclosureType"] = encType }

        var attachments: [WOMReference] = []
        if let encURL = item.enclosureURL {
            var attType: [String] = ["wom:Media"]
            if let mime = item.enclosureType {
                if mime.hasPrefix("image/") { attType.append("media:image") }
                else if mime.hasPrefix("audio/") { attType.append("media:audio") }
                else if mime.hasPrefix("video/") { attType.append("media:video") }
            }
            attachments.append(WOMReference(
                id: encURL,
                type: attType,
                name: "enclosure"
            ))
        }

        return WOMObject(
            id: objectID,
            type: types,
            createdAt: item.publishedAt ?? Date(),
            attributedTo: WOMReference(
                id: subscription.feedURL,
                type: ["wom:RemoteIdentity"],
                name: item.author ?? subscription.title
            ),
            content: WOMContent(
                format: item.description?.contains("<") == true ? "text/html" : "text/plain",
                text: item.description ?? ""
            ),
            data: data,
            provenance: WOMProvenance(
                origin: "remotePeer",
                source: WOMReference(
                    id: subscription.feedURL,
                    type: ["rss:Feed"]
                ),
                createdAt: Date(),
                confidence: 1.0,
                reviewStatus: "none"
            )
        )
    }

    private func womTypes(for sourceType: FeedSourceType) -> [String] {
        var types = ["wom:Post"]
        switch sourceType {
        case .youtube:
            types.append("external.youtube.video")
        case .podcast:
            types.append("external.podcast.episode")
        case .github:
            types.append("external.github.release")
        case .rss, .atom:
            break // just wom:Post
        }
        return types
    }
}
```

- [ ] **Step 2: Build to verify**

⌘B. Expected: Build Succeeded.

- [ ] **Step 3: Commit**

```bash
git add Wirc/WircApp/Infrastructure/Feed/FeedToWOMAdapter.swift
git commit -m "feat: add FeedToWOMAdapter with type mapping per source

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: AppState integration — wire feed properties and methods

**Files:**
- Modify: `Wirc/WircApp/App/AppState.swift`

**Interfaces:**
- Consumes: All Tasks 1–6
- Produces: `feedStore`, `feedFetcher`, `feedAdapter`, `womFileStore` properties; `addFeed(url:sourceType:)`, `removeFeed(_:)`, `importOPML(data:)`, `refreshAllFeeds()`, `discoverFeedURL(from:)`, `scheduleNextRefresh()` methods

- [ ] **Step 1: Add feed-related imports and properties to AppState**

Add after the existing `// MARK: - Mastodon` section (before `var mastodonAccounts`):

```swift
// MARK: - Feed (RSS/Atom)
let feedStore = FeedSubscriptionStore()
private let feedFetcher = FeedFetcher()
private let feedAdapter = FeedToWOMAdapter()
```

And change the existing store line from:
```swift
let store: WOMStore = InMemoryWOMStore()
```
to:
```swift
let store: WOMStore = JSONFileStore()
```

- [ ] **Step 2: Add feed management methods to AppState**

Add after the `postToMastodon` method (before `// MARK: - Queries`):

```swift
// MARK: - Feed management

func addFeed(url: String, sourceType: FeedSourceType? = nil) async throws {
    guard let feedURL = URL(string: url) else {
        throw FeedError.invalidURL(url)
    }

    // If it looks like a website URL, auto-discover
    let finalURL: String
    let detectedType: FeedSourceType

    if url.hasSuffix(".xml") || url.hasSuffix(".rss") || url.contains("/feed") {
        finalURL = url
        detectedType = sourceType ?? .rss
    } else {
        let discovered = try await feedFetcher.discoverFeed(from: feedURL)
        guard let first = discovered.first else {
            throw FeedError.invalidURL("No feed found at \(url)")
        }
        finalURL = first.absoluteString
        detectedType = sourceType ?? detectSourceType(from: finalURL)
    }

    // Create a temporary subscription to fetch title
    var tempSub = FeedSubscription(feedURL: finalURL, sourceType: detectedType)
    do {
        let (data, _) = try await feedFetcher.fetch(subscription: tempSub)
        let result = try FeedParser.parse(data: data, sourceURL: finalURL)
        tempSub.title = result.title ?? finalURL
    } catch {
        tempSub.title = finalURL // use URL as fallback title
    }

    feedStore.add(tempSub)

    // Fetch items for this feed immediately
    Task { await refreshFeed(tempSub) }
}

func removeFeed(_ subscription: FeedSubscription) {
    feedStore.remove(id: subscription.id)
}

func importOPML(data: Data) async throws -> Int {
    let outlines = try feedFetcher.parseOPML(data)
    var count = 0
    for outline in outlines {
        guard let xmlURL = outline.xmlURL else { continue }
        let sourceType = detectSourceType(from: xmlURL)
        var tags: [String] = []
        if let folder = outline.folderName { tags.append(folder) }
        let sub = FeedSubscription(
            feedURL: xmlURL,
            title: outline.title ?? xmlURL,
            sourceType: sourceType,
            tags: tags
        )
        feedStore.add(sub)
        count += 1
        // Fetch lazily — just store the subscription; first refresh picks up items
    }
    return count
}

func refreshAllFeeds() async {
    for sub in feedStore.subscriptions {
        await refreshFeed(sub)
    }
}

func discoverFeedURL(from url: String) async throws -> [String] {
    guard let feedURL = URL(string: url) else {
        throw FeedError.invalidURL(url)
    }
    let discovered = try await feedFetcher.discoverFeed(from: feedURL)
    return discovered.map { $0.absoluteString }
}

// MARK: - Feed refresh (private)

private let maxConsecutiveErrors = 5

private func refreshFeed(_ subscription: FeedSubscription) async {
    do {
        let (data, response) = try await feedFetcher.fetch(subscription: subscription)

        // Check for 304 Not Modified
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 304 {
            var sub = subscription
            sub.lastFetchedAt = Date()
            sub.errorCount = 0
            feedStore.update(sub)
            return
        }

        let result = try FeedParser.parse(data: data, sourceURL: subscription.feedURL)

        // Update subscription with parsed title and headers
        var sub = subscription
        if let title = result.title { sub.title = title }
        sub.lastFetchedAt = Date()
        sub.errorCount = 0
        if let httpResponse = response as? HTTPURLResponse {
            sub.etag = httpResponse.allHeaderFields["ETag"] as? String ?? httpResponse.allHeaderFields["Etag"] as? String
            sub.lastModified = httpResponse.allHeaderFields["Last-Modified"] as? String
        }
        feedStore.update(sub)

        // Convert items to WOM and save
        let objects = await feedAdapter.convert(items: result.items, subscription: sub, store: store)
        if !objects.isEmpty {
            try? await store.saveMany(objects)
            womObjects.append(contentsOf: objects)
        }
    } catch {
        var sub = subscription
        sub.errorCount += 1
        sub.lastFetchedAt = Date()
        feedStore.update(sub)
    }
}

private func detectSourceType(from url: String) -> FeedSourceType {
    if url.contains("youtube.com") { return .youtube }
    if url.contains("github.com") { return .github }
    // Check for podcast indicators in URL
    if url.contains("/podcast") || url.contains("itunes") { return .podcast }
    return .rss
}

func scheduleNextRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: "com.wirc.feed-refresh")
    request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
    try? BGTaskScheduler.shared.submit(request)
}
```

- [ ] **Step 3: Add BackgroundTasks import at top of AppState.swift**

Add `import BackgroundTasks` after the existing imports:
```swift
import SwiftUI
import Observation
import BackgroundTasks
```

- [ ] **Step 4: Build to verify**

⌘B. Expected: Build Succeeded.

- [ ] **Step 5: Commit**

```bash
git add Wirc/WircApp/App/AppState.swift
git commit -m "feat: wire feed store, fetcher, adapter into AppState

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 8: FeedView rewrite + FeedCard per-type layouts

**Files:**
- Modify: `Wirc/WircApp/Features/Feed/FeedView.swift`
- Modify: `Wirc/WircApp/Features/Feed/FeedCard.swift`

**Interfaces:**
- Consumes: `AppState` (Task 7), `WOMObject` (existing)
- Produces: Updated FeedView with segmented picker and RSS content; updated FeedCard with per-type layouts

- [ ] **Step 1: Rewrite FeedView.swift**

```swift
import SwiftUI

struct FeedView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedFilter: FeedFilter = .all

    enum FeedFilter: String, CaseIterable {
        case all = "All"
        case blogs = "Blogs"
        case videos = "Videos"
        case podcasts = "Podcasts"
    }

    private var allPosts: [WOMObject] {
        appState.womObjects
            .filter { $0.type.contains("wom:Post") }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var filteredPosts: [WOMObject] {
        switch selectedFilter {
        case .all:
            return allPosts
        case .blogs:
            return allPosts.filter { obj in
                !obj.type.contains("external.youtube.video") &&
                !obj.type.contains("external.podcast.episode")
            }
        case .videos:
            return allPosts.filter { $0.type.contains("external.youtube.video") }
        case .podcasts:
            return allPosts.filter { $0.type.contains("external.podcast.episode") }
        }
    }

    private var hasFeedsConfigured: Bool {
        !appState.feedStore.subscriptions.isEmpty ||
        !appState.mastodonAccounts.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if let error = appState.feedError {
                    ContentUnavailableView(
                        "Feed Error",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                    .overlay(alignment: .bottom) {
                        Button("Retry") {
                            Task {
                                for acct in appState.mastodonAccounts {
                                    appState.refreshMastodonFeed(accountId: acct.id)
                                }
                                await appState.refreshAllFeeds()
                            }
                        }
                        .buttonStyle(.bordered)
                        .padding(.bottom, 40)
                    }
                } else if appState.feedLoading && allPosts.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading feed...").foregroundStyle(.secondary)
                    }
                } else if allPosts.isEmpty && !hasFeedsConfigured {
                    ContentUnavailableView(
                        "No Feed Sources",
                        systemImage: "newspaper",
                        description: Text("Add RSS feeds or a Mastodon account in Settings to see your feed.")
                    )
                } else if allPosts.isEmpty {
                    ContentUnavailableView(
                        "Feed Empty",
                        systemImage: "newspaper",
                        description: Text("Your feed is empty. New posts will appear here.")
                    )
                } else {
                    VStack(spacing: 0) {
                        // Segmented filter
                        if !allPosts.isEmpty {
                            Picker("Filter", selection: $selectedFilter) {
                                ForEach(FeedFilter.allCases, id: \.self) { filter in
                                    Text(filter.rawValue).tag(filter)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }

                        ScrollView {
                            LazyVStack(spacing: 12) {
                                if appState.feedLoading {
                                    HStack {
                                        ProgressView()
                                        Text("Refreshing...")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                ForEach(filteredPosts) { post in
                                    FeedCard(post: post)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                        .refreshable {
                            for acct in appState.mastodonAccounts {
                                appState.refreshMastodonFeed(accountId: acct.id)
                            }
                            await appState.refreshAllFeeds()
                        }
                    }
                }
            }
            .navigationTitle("Feed")
        }
    }
}
```

- [ ] **Step 2: Rewrite FeedCard.swift with per-type layouts**

```swift
import SwiftUI

struct FeedCard: View {
    let post: WOMObject

    private var network: String { post.data["network"] ?? "" }
    private var sourceType: String { post.data["sourceType"] ?? "" }

    private var isYouTubeVideo: Bool {
        post.type.contains("external.youtube.video")
    }

    private var isPodcastEpisode: Bool {
        post.type.contains("external.podcast.episode")
    }

    private var isGitHubRelease: Bool {
        post.type.contains("external.github.release")
    }

    private var isRSS: Bool {
        network == "rss"
    }

    var body: some View {
        if isYouTubeVideo {
            youTubeCard
        } else if isPodcastEpisode {
            podcastCard
        } else if isGitHubRelease {
            gitHubCard
        } else {
            standardCard
        }
    }

    // MARK: - YouTube Video Card

    private var youTubeCard: some View {
        HStack(alignment: .top, spacing: 12) {
            // Thumbnail
            if let thumbURL = post.data["enclosureURL"],
               let url = URL(string: thumbURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fit)
                            .frame(width: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    default:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray5))
                            .frame(width: 120, height: 68)
                            .overlay(Image(systemName: "play.rectangle").foregroundStyle(.secondary))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(post.name ?? post.content?.text ?? "")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(3)

                Text(post.attributedTo?.name ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    if let dur = post.data["duration"], !dur.isEmpty {
                        Label(dur, systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Label("YouTube", systemImage: "play.rectangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Text(post.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Podcast Episode Card

    private var podcastCard: some View {
        HStack(alignment: .top, spacing: 12) {
            // Cover art
            if let artURL = post.data["enclosureURL"],
               let url = URL(string: artURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    default:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray5))
                            .frame(width: 64, height: 64)
                            .overlay(Image(systemName: "waveform").foregroundStyle(.secondary))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(post.name ?? "")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)

                Text(post.attributedTo?.name ?? post.data["feedTitle"] ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    if let dur = post.data["duration"], !dur.isEmpty {
                        Label(dur, systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Label("Podcast", systemImage: "waveform")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                    Text(post.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - GitHub Release Card

    private var gitHubCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "tag.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text(post.name ?? "")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(post.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(post.data["feedTitle"] ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let desc = post.content?.text, !desc.isEmpty {
                Text(desc.stripHTML.prefix(200) + (desc.stripHTML.count > 200 ? "..." : ""))
                    .font(.body)
                    .lineLimit(5)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Standard Card (Blog, Mastodon, IRC)

    private var standardCard: some View {
        // Reuse existing card layout, with RSS-awareness
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 8) {
                Circle()
                    .fill(networkColor.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: networkIcon)
                            .font(.caption)
                            .foregroundStyle(networkColor)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(post.attributedTo?.name ?? post.data["feedTitle"] ?? "unknown")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        if isRSS {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    if let feedTitle = post.data["feedTitle"], !feedTitle.isEmpty,
                       post.attributedTo?.name != feedTitle {
                        Text("via \(feedTitle)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if let instance = post.data["instance"] {
                        Text("@\(post.attributedTo?.id.components(separatedBy: "/@").last ?? "") · \(instance)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(post.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Title (RSS posts have a name/headline)
            if let name = post.name, !name.isEmpty,
               name != post.content?.text {
                Text(name)
                    .font(.headline)
                    .fontWeight(.medium)
            }

            // Content
            if let text = post.content?.text, !text.isEmpty {
                Text(text.stripHTML)
                    .font(.body)
                    .lineLimit(12)
            }

            // Media previews (Mastodon images)
            if !post.attachments.isEmpty {
                ForEach(post.attachments) { att in
                    let url = att.id
                    if att.type?.contains("image") == true || att.type?.contains("media:image") == true {
                        AsyncImage(url: URL(string: url)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxHeight: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            default:
                                EmptyView()
                            }
                        }
                    }
                }
            }

            // Footer
            HStack(spacing: 24) {
                if let count = post.data["repliesCount"], let n = Int(count), n > 0 {
                    Label("\(n)", systemImage: "bubble.right")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let count = post.data["reblogsCount"], let n = Int(count), n > 0 {
                    Label("\(n)", systemImage: "arrow.2.squarepath")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let count = post.data["favouritesCount"], let n = Int(count), n > 0 {
                    Label("\(n)", systemImage: "star")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Spacer()

                // Network badge
                HStack(spacing: 2) {
                    Image(systemName: networkIcon)
                        .font(.caption2)
                    Text(post.data["via"] ?? network.capitalized)
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private var networkIcon: String {
        switch network {
        case "mastodon": return "m.circle.fill"
        case "irc": return "number"
        case "rss": return "dot.radiowaves.left.and.right"
        default: return "globe"
        }
    }

    private var networkColor: Color {
        switch network {
        case "mastodon": return .purple
        case "irc": return .blue
        case "rss": return .orange
        default: return .gray
        }
    }
}

// MARK: - HTML stripping helper

private extension String {
    var stripHTML: String {
        guard let data = data(using: .utf8) else { return self }
        if let plain = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html],
            documentAttributes: nil
        ).string {
            return plain
        }
        // Fallback: basic regex strip
        return replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 3: Build to verify**

⌘B. Expected: Build Succeeded.

- [ ] **Step 4: Commit**

```bash
git add Wirc/WircApp/Features/Feed/FeedView.swift Wirc/WircApp/Features/Feed/FeedCard.swift
git commit -m "feat: rewrite FeedView with segmented filter + per-type FeedCards

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 9: Settings UI — Feeds section + AddFeedView

**Files:**
- Modify: `Wirc/WircApp/Features/Settings/SettingsView.swift`
- Create: `Wirc/WircApp/Features/Settings/AddFeedView.swift`

**Interfaces:**
- Consumes: `AppState` (Task 7), `FeedSubscription`, `FeedSourceType` (Task 1)
- Produces: Updated SettingsView with Feeds section; `AddFeedView` sheet

- [ ] **Step 1: Create AddFeedView.swift**

```swift
import SwiftUI
import UniformTypeIdentifiers

struct AddFeedView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var sourceType: FeedSourceType = .rss
    @State private var isDiscovering = false
    @State private var discoveredURLs: [String] = []
    @State private var selectedDiscoveredURL: String?
    @State private var errorMessage: String?
    @State private var showOPMLPicker = false

    var body: some View {
        NavigationStack {
            Form {
                // URL input
                Section("Feed URL or Website") {
                    TextField("https://example.com or https://youtube.com/@channel",
                              text: $urlText)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    Button {
                        discover()
                    } label: {
                        HStack {
                            if isDiscovering {
                                ProgressView()
                            }
                            Text("Auto-discover Feed")
                        }
                    }
                    .disabled(urlText.isEmpty || isDiscovering)

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                // Discovered feeds
                if !discoveredURLs.isEmpty {
                    Section("Discovered Feeds") {
                        ForEach(discoveredURLs, id: \.self) { url in
                            HStack {
                                Text(url)
                                    .font(.caption)
                                    .lineLimit(2)
                                Spacer()
                                if selectedDiscoveredURL == url {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedDiscoveredURL = url
                                urlText = url
                            }
                        }
                    }
                }

                // Manual source type
                Section("Feed Type") {
                    Picker("Type", selection: $sourceType) {
                        ForEach(FeedSourceType.allCases, id: \.self) { t in
                            Text(typeLabel(t)).tag(t)
                        }
                    }
                }

                // OPML import
                Section {
                    Button {
                        showOPMLPicker = true
                    } label: {
                        Label("Import OPML File", systemImage: "doc.text")
                    }
                } header: {
                    Text("Bulk Import")
                } footer: {
                    Text("Import subscriptions from another RSS reader via OPML file.")
                }
            }
            .navigationTitle("Add Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Subscribe") { subscribe() }
                        .disabled(urlText.isEmpty)
                }
            }
            .fileImporter(
                isPresented: $showOPMLPicker,
                allowedContentTypes: [.xml, UTType(filenameExtension: "opml") ?? .xml],
                allowsMultipleSelection: false
            ) { result in
                handleOPMLImport(result)
            }
        }
    }

    private func discover() {
        isDiscovering = true
        errorMessage = nil
        discoveredURLs = []
        Task {
            do {
                let urls = try await appState.discoverFeedURL(from: urlText)
                await MainActor.run {
                    discoveredURLs = urls
                    if let first = urls.first {
                        selectedDiscoveredURL = first
                        urlText = first
                        // Auto-detect type
                        if first.contains("youtube.com") { sourceType = .youtube }
                        else if first.contains("github.com") { sourceType = .github }
                    }
                    if urls.isEmpty {
                        errorMessage = "No feed found. Try pasting the feed URL directly."
                    }
                    isDiscovering = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isDiscovering = false
                }
            }
        }
    }

    private func subscribe() {
        let finalURL = selectedDiscoveredURL ?? urlText
        guard !finalURL.isEmpty else { return }
        Task {
            do {
                try await appState.addFeed(url: finalURL, sourceType: sourceType)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func handleOPMLImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let fileURL = urls.first else { return }
            Task {
                do {
                    let data = try Data(contentsOf: fileURL)
                    let count = try await appState.importOPML(data: data)
                    await MainActor.run {
                        errorMessage = nil
                        dismiss()
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = "OPML import failed: \(error.localizedDescription)"
                    }
                }
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func typeLabel(_ type: FeedSourceType) -> String {
        switch type {
        case .rss: return "RSS / Blog"
        case .atom: return "Atom Feed"
        case .youtube: return "YouTube Channel"
        case .github: return "GitHub Releases"
        case .podcast: return "Podcast"
        }
    }
}
```

- [ ] **Step 2: Modify SettingsView.swift — add Feeds section**

Add a new section between the Mastodon section and the Debug section. Also add `@State private var showingAddFeed = false` and the sheet modifier.

Add `@State` property after the existing two:
```swift
@State private var showingAddFeed = false
```

Insert the Feeds section after the Mastodon `Section("Mastodon") { ... }` closing brace and before `// Debug`:

```swift
// RSS/Atom Feeds
Section("Feeds") {
    if appState.feedStore.subscriptions.isEmpty {
        Text("No feeds subscribed")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    } else {
        ForEach(appState.feedStore.subscriptions) { sub in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sub.title)
                        .font(.subheadline)
                    HStack(spacing: 4) {
                        Image(systemName: sourceTypeIcon(sub.sourceType))
                            .font(.caption2)
                        Text(sub.sourceType.rawValue.capitalized)
                            .font(.caption)
                        if let fetched = sub.lastFetchedAt {
                            Text("· fetched \(fetched, style: .relative) ago")
                                .font(.caption2)
                        }
                    }
                    .foregroundStyle(.secondary)
                    if !sub.tags.isEmpty {
                        Text(sub.tags.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    if sub.errorCount > 0 {
                        Text("\(sub.errorCount) errors")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                Spacer()
                Button {
                    Task { await appState.refreshAllFeeds() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
            }
        }
        .onDelete { indexSet in
            for idx in indexSet {
                let sub = appState.feedStore.subscriptions[idx]
                appState.removeFeed(sub)
            }
        }
    }
    Button { showingAddFeed = true } label: {
        Label("Add Feed", systemImage: "plus")
    }
    Button {
        // OPML import via AddFeedView
        showingAddFeed = true
    } label: {
        Label("Import OPML", systemImage: "doc.text")
    }
}
```

Add the sheet modifier after the existing `.sheet(isPresented: $showingAddMastodon)`:
```swift
.sheet(isPresented: $showingAddFeed) {
    AddFeedView()
}
```

Add the helper function at the bottom of the file (before the `AddMastodonView` struct):
```swift
private func sourceTypeIcon(_ type: FeedSourceType) -> String {
    switch type {
    case .rss, .atom: return "dot.radiowaves.left.and.right"
    case .youtube: return "play.rectangle.fill"
    case .github: return "tag.fill"
    case .podcast: return "waveform"
    }
}
```

This helper should be inside `SettingsView`, not at file scope. But since `SettingsView` is a struct, add it inside the struct body (it can be a private func in the struct). In SwiftUI, you can add private functions to View structs. Add it right before the closing `}` of `SettingsView`.

- [ ] **Step 3: Build to verify**

⌘B. Expected: Build Succeeded.

- [ ] **Step 4: Commit**

```bash
git add Wirc/WircApp/Features/Settings/SettingsView.swift Wirc/WircApp/Features/Settings/AddFeedView.swift
git commit -m "feat: add Feeds section to Settings + AddFeedView with auto-discovery

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 10: Background refresh — BGAppRefreshTask

**Files:**
- Modify: `Wirc/WircApp/App/WircApp.swift`

**Interfaces:**
- Consumes: `AppState` (Task 7)
- Produces: BGAppRefreshTask registration and scheduling in app lifecycle

- [ ] **Step 1: Add background task registration to WircApp.swift**

First read the current WircApp.swift:

```swift
// Current file (from MVP):
import SwiftUI

@main
struct WircApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            TabView {
                ChatView()
                    .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }

                FeedView()
                    .tabItem { Label("Feed", systemImage: "house") }

                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gear") }
            }
            .environment(appState)
        }
    }
}
```

Replace with:

```swift
import SwiftUI
import BackgroundTasks

@main
struct WircApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView {
                ChatView()
                    .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }

                FeedView()
                    .tabItem { Label("Feed", systemImage: "house") }

                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gear") }
            }
            .environment(appState)
            .onAppear {
                registerBackgroundTasks()
                appState.scheduleNextRefresh()
                Task {
                    await appState.refreshAllFeeds()
                }
            }
        }
    }

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.wirc.feed-refresh",
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }

            Task {
                await appState.refreshAllFeeds()
                refreshTask.setTaskCompleted(success: true)
                appState.scheduleNextRefresh()
            }

            refreshTask.expirationHandler = {
                refreshTask.setTaskCompleted(success: false)
            }
        }
    }
}
```

- [ ] **Step 2: Add BGTaskSchedulerPermittedIdentifiers to Info.plist**

Read `Wirc/WircApp/App/Info.plist` and add the `BGTaskSchedulerPermittedIdentifiers` key. If the file doesn't exist or is minimal, create the entry:

The Info.plist needs this entry for background tasks to work:

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.wirc.feed-refresh</string>
</array>
```

Add this inside the `<dict>` element of Info.plist.

- [ ] **Step 3: Build to verify**

⌘B. Expected: Build Succeeded.

- [ ] **Step 4: Commit**

```bash
git add Wirc/WircApp/App/WircApp.swift Wirc/WircApp/App/Info.plist
git commit -m "feat: add BGAppRefreshTask for periodic feed refresh

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Spec Coverage Self-Review

1. **Models** (FeedItem, FeedSubscription, FeedSourceType, FeedParseResult, OPMLOutline) — Task 1 ✓
2. **FeedFetcher** (HTTP fetch with ETag, URL auto-discovery, OPML parser) — Task 4 ✓
3. **FeedParser** (RSS 2.0 + Atom 1.0 via XMLParser) — Task 5 ✓
4. **FeedToWOMAdapter** (Type mapping per sourceType, dedup logic) — Task 6 ✓
5. **JSONFileStore** (WOMStore protocol implementation on disk) — Task 2 ✓
6. **FeedSubscriptionStore** (CRUD + JSON file persistence) — Task 3 ✓
7. **AppState integration** (Wire new properties, refreshAllFeeds, addFeed, importOPML) — Task 7 ✓
8. **FeedView + FeedCard** (Rewrite placeholder, per-type card layouts, segmented picker) — Task 8 ✓
9. **Settings UI** (Feeds section, AddFeedView, OPML import button) — Task 9 ✓
10. **Background refresh** (BGAppRefreshTask registration and scheduling) — Task 10 ✓

**Success criteria coverage:**
1. Paste blog URL → auto-discover → subscribe → cards appear — Tasks 4+7+8 ✓
2. YouTube channel URL → resolve to RSS → video cards with thumbnails — Tasks 4+8 ✓
3. OPML import → feeds added with folder names as tags — Tasks 4+7 ✓
4. Pull-to-refresh fetches new items — Tasks 7+8 ✓
5. Close/reopen → feed items persist (JSONFileStore) — Task 2 ✓
6. Feed cards per type (blog, YouTube, podcast, GitHub) — Task 8 ✓
7. Feed list in Settings with tags + status — Task 9 ✓
8. Delete subscription → items remain in store — Task 7 (removeFeed only removes subscription) ✓

**Placeholder scan:** No TBDs, TODOs, "implement later", or vague instructions. Every step has concrete code. ✓

**Type consistency:** `FeedSubscription.id` is `UUID` throughout. `WOMObject.id` is `String` throughout. `sourceType` is `FeedSourceType` enum used consistently in Tasks 1, 6, 7, 9. `AppState.feedStore` → `FeedSubscriptionStore` → `[FeedSubscription]` chain consistent. `JSONFileStore` implements `WOMStore` protocol correctly. ✓
