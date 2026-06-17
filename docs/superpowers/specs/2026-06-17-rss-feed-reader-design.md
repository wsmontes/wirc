# RSS Feed Reader — Design Spec

**Date:** 2026-06-17
**Status:** Approved
**Target:** iOS 17+, SwiftUI, Xcode project
**Depends on:** Virk/WIRC MVP (2026-06-16)

## Overview

Adds an RSS/Atom feed reader to WIRC, transforming the empty Feed tab into a functional multi-source timeline. RSS becomes the "universal slow connector" — blogs, YouTube channels, podcasts, GitHub releases, and newsletters all enter WIRC as WOM objects through the same pipeline.

### Core Thesis

Every content source with an RSS feed becomes a WOM data source. The pipeline is protocol-agnostic: RSS 2.0 and Atom 1.0 are parsed uniformly; the subscription's `sourceType` determines the WOM type mapping and card rendering. This proves RSS as the universal ingestion layer without coupling to any specific platform.

### Goal

1. User can subscribe to feeds by pasting a URL (auto-discovery) or importing OPML
2. Feeds are fetched periodically (BGAppRefreshTask) and on-demand (launch, pull-to-refresh)
3. Feed items are parsed, converted to WOM objects, and persisted to disk
4. The Feed tab renders cards appropriate to each content type (blog post, YouTube video, podcast episode, GitHub release)
5. Feed subscriptions support user-assigned tags for organization (AI-assigned tags deferred to future AI layer)

## Architecture

### Pipeline (mirrors IRC pattern)

```
HTTP GET feed.xml ──▶ FeedFetcher ──▶ FeedParser ──▶ FeedToWOMAdapter ──▶ WOMStore (JSONFileStore) ──▶ FeedView
                         ▲                                          │
                         │                                          │
                   FeedSubscription                           WOMObject
                   (URL, ETag, tags)                     (type-mapped, persisted)
```

### Layer Isolation

| Layer | File | Responsibility | Does NOT know |
|-------|------|---------------|---------------|
| Feed Fetching | `FeedFetcher.swift` | HTTP GET with ETag/Last-Modified, URL auto-discovery, OPML parsing | WOM, FeedItem structure |
| Feed Parsing | `FeedParser.swift` | XMLParser-based RSS 2.0 + Atom 1.0 → [FeedItem] | WOM, network |
| Intermediate Model | `FeedItem.swift` | Codable struct: title, link, description, pubDate, author, enclosure | WOM, network, parsing |
| Adapter | `FeedToWOMAdapter.swift` | FeedItem + FeedSubscription → WOMObject with type mapping | Network, XML parsing |
| Subscription Model | `FeedSubscription.swift` | Codable model: feedURL, title, sourceType, tags, ETag, lastFetchedAt, errorCount | WOM, parsing |
| Subscription Store | `FeedSubscriptionStore.swift` | CRUD for subscriptions, JSON file persistence | Network, WOM, parsing |
| Persistence | `JSONFileStore.swift` | WOMStore protocol implementation on disk (one JSON file per object + in-memory index) | Feed specifics, network |

### Data Flow (Receive)

1. Trigger: app launch, pull-to-refresh, or BGAppRefreshTask
2. `AppState.refreshAllFeeds()` iterates over all subscriptions
3. For each: `FeedFetcher.fetch(subscription)` → HTTP response with conditional GET headers
4. If 304 Not Modified → skip (ETag match)
5. If 200 OK → `FeedParser.parse(data, sourceURL)` → `FeedParseResult` (title + [FeedItem])
6. `FeedToWOMAdapter.convert(items, subscription)` → [WOMObject]
7. WOM objects saved to `JSONFileStore`; dedup by `data.canonicalUrl`
8. UI reactively updates via `@Observable AppState`

### Data Flow (Subscribe)

1. User pastes URL in AddFeedView
2. If URL looks like a website (not .xml): `FeedFetcher.discoverFeed(from:)` fetches HTML, extracts `<link rel="alternate">` tags or resolves YouTube @handle → channel ID → RSS URL
3. If URL is a direct feed URL (.xml, /feed, /rss): use directly
4. `FeedFetcher.fetch(subscription)` once to get feed title
5. Create `FeedSubscription` with parsed title and detected sourceType
6. Save to `FeedSubscriptionStore`

### Data Flow (OPML Import)

1. User picks .opml file via file picker
2. `FeedFetcher.parseOPML(data)` → flat list of feed URLs with folder names
3. Folder names become initial tags on each subscription
4. For each URL: create `FeedSubscription` (title fetched lazily on first refresh)
5. All subscriptions saved; count returned to UI

## Models

### FeedItem (Intermediate Struct)

```swift
struct FeedItem: Codable, Equatable {
    let id: String           // guid (RSS) or id (Atom), fallback: link
    let title: String
    let link: String          // canonical URL
    let description: String?  // plain text or HTML summary
    let publishedAt: Date?

    let author: String?
    let category: String?
    let enclosureURL: String?   // media: image, audio, video
    let enclosureType: String?  // MIME type
    let duration: String?       // podcast/YouTube
}
```

### FeedSubscription

```swift
struct FeedSubscription: Codable, Identifiable, Equatable {
    let id: UUID
    var feedURL: String           // https://example.com/feed.xml
    var title: String              // "Wagner's Blog" (parsed from feed)
    var sourceType: FeedSourceType // .rss, .atom, .youtube, .github, .podcast
    var tags: [String]            // user-assigned: ["tech", "llm", "brasil"]
    var lastFetchedAt: Date?
    var etag: String?              // HTTP ETag for conditional GET
    var lastModified: String?      // HTTP Last-Modified
    var errorCount: Int           // consecutive failures (auto-pause after threshold)
}

enum FeedSourceType: String, Codable {
    case rss, atom, youtube, github, podcast
}
```

### FeedParseResult

```swift
struct FeedParseResult {
    let title: String?         // feed-level title
    let description: String?   // feed-level description
    let link: String?          // feed-level homepage
    let items: [FeedItem]      // parsed items
}
```

## WOM Type Mapping

The `sourceType` on the subscription determines the WOM types. The parser is format-agnostic; the adapter applies the mapping.

| Source Type | WOM types | Card Layout |
|-------------|-----------|-------------|
| `.rss` / `.atom` (blog/news) | `["wom:Post"]` | Title + summary + author + date + source |
| `.youtube` | `["wom:Post", "external.youtube.video"]` | Thumbnail left, title, channel name, duration |
| `.podcast` | `["wom:Post", "external.podcast.episode"]` | Cover art, title, podcast name, duration, play button |
| `.github` | `["wom:Post", "external.github.release"]` | Version tag, repo name, changelog summary |

### WOMObject Example (YouTube Video)

```json
{
  "wom": "0.1",
  "id": "urn:wom:post:abc123...",
  "type": ["wom:Post", "external.youtube.video"],
  "name": "The most beautiful equation in math",
  "summary": "Euler's formula explained visually...",
  "createdAt": "2026-06-15T14:00:00Z",
  "attributedTo": {
    "id": "https://youtube.com/channel/UCYO_...",
    "type": ["wom:RemoteIdentity"],
    "name": "3Blue1Brown"
  },
  "content": { "format": "text/html", "text": "<p>Euler's formula...</p>" },
  "attachments": [
    { "id": "https://i.ytimg.com/vi/.../hqdefault.jpg", "type": ["wom:Media"], "name": "thumbnail" }
  ],
  "data": {
    "network": "rss",
    "canonicalUrl": "https://youtube.com/watch?v=...",
    "feedTitle": "3Blue1Brown",
    "sourceType": "youtube",
    "duration": "24:18"
  },
  "provenance": {
    "origin": "remotePeer",
    "source": { "id": "https://youtube.com/feeds/videos.xml?channel_id=...", "type": ["rss:Feed"] },
    "confidence": 1.0
  }
}
```

## FeedFetcher

```swift
final class FeedFetcher {
    // Fetch a feed with conditional GET
    func fetch(subscription: FeedSubscription) async throws -> (Data, HTTPURLResponse)

    // URL auto-discovery: website URL → discovered feed URLs
    func discoverFeed(from url: URL) async throws -> [URL]

    // OPML import: XML data → flat list of feed outlines
    func parseOPML(_ data: Data) throws -> [OPMLOutline]
}
```

### Auto-Discovery Mechanisms

1. **Generic websites**: Fetch HTML, parse `<link rel="alternate" type="application/rss+xml" href="...">` and `<link rel="alternate" type="application/atom+xml" href="...">`. Resolve relative URLs.
2. **YouTube**: Fetch channel/page HTML, extract `<meta itemprop="channelId" content="UC...">`, build `https://www.youtube.com/feeds/videos.xml?channel_id=UC...`
3. **GitHub**: Append `.atom` to releases page URL (`https://github.com/user/repo/releases.atom`)

### Conditional GET

- First fetch: store `ETag` and `Last-Modified` from response headers
- Subsequent fetches: send `If-None-Match` and `If-Modified-Since` headers
- 304 response: no new content, skip parsing

## FeedParser

```swift
enum FeedParser {
    static func parse(data: Data, sourceURL: String) throws -> FeedParseResult
}
```

Uses Foundation `XMLParser` (SAX). Detects format by root element (`<rss>` vs `<feed xmlns="http://www.w3.org/2005/Atom">`).

### Supported Elements

**RSS 2.0**: `title`, `link`, `description`, `pubDate`, `author`, `category`, `enclosure[@url, @type]`, `guid`

**Atom 1.0**: `title`, `link[@rel='alternate'][@href]`, `summary` / `content`, `published` / `updated`, `author/name`, `category[@term]`, `link[@rel='enclosure'][@href]`

Namespace extensions (mrss, itunes, media:) are explicitly out of scope for this iteration. They will be parsed as passthrough data if present.

## FeedToWOMAdapter

```swift
final class FeedToWOMAdapter {
    func convert(items: [FeedItem], subscription: FeedSubscription) -> [WOMObject]
}
```

Mirrors `IRCToWOMAdapter`. Pure function: `[FeedItem]` + context → `[WOMObject]`.

- Dedup: skip items whose `data.canonicalUrl` already exists in the store
- Type mapping: based on `subscription.sourceType`
- Provenance: `origin: "remotePeer"`, source pointing to the feed URL

## Persistence

### JSONFileStore (implements WOMStore)

Deferred from MVP. Stores each WOMObject as a separate JSON file in the app's Documents directory. Maintains an in-memory index for queries.

```
~/Documents/wirc/
├── objects/
│   ├── urn:wom:post:abc123.json
│   ├── urn:wom:post:def456.json
│   └── ...
├── subscriptions.json    // FeedSubscriptionStore
└── settings.json          // UserDefaults (existing)
```

### FeedSubscriptionStore

CRUD for subscriptions. Persisted as a single JSON array file (`subscriptions.json`). Loaded on init, written on every mutation.

## Background Refresh

Uses `BGAppRefreshTask` (iOS background task scheduler):

- Task identifier: `"com.wirc.feed-refresh"`
- Registered at app launch
- Re-scheduled after each successful run (30-minute interval requested)
- System decides actual execution timing based on battery, connectivity, usage patterns

Fetch also happens at:
- `FeedView.onAppear` (app launch / tab switch)
- Pull-to-refresh gesture in FeedView

BGTask is a bonus, not a dependency. The user never sees stale content unless they ignore the app for hours.

## UI Changes

### FeedView (rewrite placeholder)

```
FeedView
 ├── Pull-to-refresh (triggers refreshAllFeeds)
 ├── Segmented picker: "All" | "Blogs" | "Videos" | "Podcasts"
 ├── ScrollView > LazyVStack of FeedCards
 └── Empty state: "Add feeds in Settings to see posts here"
```

### FeedCard (per-type layouts)

| WOM type | Card layout |
|----------|-------------|
| `wom:Post` (blog) | Text card: title, summary, author, date, source badge |
| `external.youtube.video` | Thumbnail card: image left, title, channel name, duration badge |
| `external.podcast.episode` | Cover art card: image left, title, podcast name, duration, play button (opens URL) |
| `external.github.release` | Compact card: version tag badge, repo name, changelog excerpt |

### SettingsView (new "Feeds" section)

New section below "Servers":

```
SettingsView
 ├── Servers section (existing)
 ├── Feeds section (NEW)
 │   ├── Subscription list
 │   │   ├── Feed title + sourceType badge
 │   │   ├── Tags (editable chips)
 │   │   ├── Last fetched timestamp + error indicator
 │   │   └── Swipe to delete
 │   ├── "Add Feed" button → AddFeedView sheet
 │   │   ├── URL text field
 │   │   ├── "Auto-discover" button
 │   │   ├── Manual source type picker
 │   │   └── "Subscribe" button
 │   └── "Import OPML" button → file picker (.opml, .xml)
 └── Debug section (existing)
```

### AppState Changes

New properties:
- `feedStore: FeedSubscriptionStore`
- `feedFetcher: FeedFetcher`
- `feedAdapter: FeedToWOMAdapter`
- `womFileStore: JSONFileStore` (replaces InMemoryWOMStore for persistence)

New methods:
- `addFeed(url:sourceType:) async throws`
- `removeFeed(_:) async`
- `importOPML(data:) async throws -> Int`
- `refreshAllFeeds() async`
- `discoverFeedURL(from:) async throws -> [String]`
- `scheduleNextRefresh()`

Existing `feedObjects` computed property continues to filter `wom:Post` — no change needed. The content grows; the query stays the same.

## Implementation Phases

1. **Models** — FeedItem, FeedSubscription, FeedSourceType, FeedParseResult, OPMLOutline
2. **FeedFetcher** — HTTP fetch with ETag, URL auto-discovery, OPML parser
3. **FeedParser** — RSS 2.0 + Atom 1.0 via XMLParser
4. **FeedToWOMAdapter** — Type mapping per sourceType, dedup logic
5. **JSONFileStore** — WOMStore protocol implementation on disk
6. **FeedSubscriptionStore** — CRUD + JSON file persistence
7. **AppState integration** — Wire new properties, refreshAllFeeds, addFeed, importOPML
8. **FeedView + FeedCard** — Rewrite placeholder, per-type card layouts, segmented picker
9. **Settings UI** — Feeds section, AddFeedView, OPML import button
10. **Background refresh** — BGAppRefreshTask registration and scheduling

## Success Criteria

1. Paste a blog URL → auto-discovers feed → subscribes → fetches posts → cards appear in Feed
2. Paste a YouTube channel URL → resolves to RSS → subscribes → video cards appear with thumbnails
3. Import OPML file → all feeds added with folder names as tags
4. Pull-to-refresh fetches new items from all subscriptions
5. Close and reopen app → feed items persist (JSONFileStore)
6. Feed cards render correctly per type (blog, YouTube, podcast, GitHub)
7. Feed list in Settings shows all subscriptions with tags and last-fetched status
8. Delete a subscription → its items remain in the store (they're WOM objects now)

## Explicitly Excluded

- AI-based feed classification and relevance scoring (separate AI layer spec)
- AI-generated thematic feeds (separate AI layer spec)
- Semantic search across feed items (separate AI layer spec)
- Activity tracking / engagement logging for AI training (separate AI layer spec)
- Mastodon, Bluesky, Nostr, ActivityPub adapters
- Namespace extensions (mrss, itunes, media:) — parsed as passthrough only
- In-app feed content rendering (WebView for full articles) — items open in system browser
- Offline reading / read-later
- Feed export (OPML export)
- Feed refresh interval configuration UI (hardcoded 30 min)
- Push notifications for new feed items
- Mumble voice integration
- Meshnet transport
- Cryptographic identity / Virk keys / signatures

## Key Design Rules

- **Same pipeline pattern as IRC**: Fetcher → Parser → Adapter → Store → UI
- **WOM purity**: FeedView renders WOMObject, never FeedItem directly
- **No own server**: Feeds are fetched directly from source URLs
- **Conditional GET**: Respect ETag/Last-Modified to minimize bandwidth
- **Dedup by canonical URL**: Same item from multiple feeds = one WOM object
- **User-controlled tags**: Folders/categories are tags, assigned by user (AI later)
- **Design for later AI integration**: All classification data lives in WOM object fields that an AI layer can read and enrich
