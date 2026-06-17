import Foundation

// MARK: - OPMLOutline

struct OPMLOutline {
    let title: String?
    let xmlURL: String
    let htmlURL: String?
    let folderName: String?
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

// MARK: - FeedFetcher

final class FeedFetcher: @unchecked Sendable {
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
