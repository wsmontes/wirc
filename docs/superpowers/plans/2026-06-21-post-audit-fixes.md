# Post-Audit Fixes — 92 Remaining Issues

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all 92 remaining issues from the comprehensive Wirc audit — covering feed content display, IRC robustness, data integrity, Mastodon integration, navigation, accessibility, and code quality.

**Architecture:** Work is organized into 7 independent workstreams that can be executed in parallel. Each stream produces testable, shippable improvements without depending on other streams. Within each stream, tasks are ordered by dependency.

**Tech Stack:** Swift 6, SwiftUI, iOS 17+, `@Observable` macro, `NWConnection` (IRC), `URLSession` (HTTP/Mastodon), `JSONFileStore` (persistence), `XMLParser` (feed parsing)

## Global Constraints

- Minimum iOS 17.0 target
- Swift 6 concurrency safety (no new `@unchecked Sendable` without justification)
- All UI must use `DesignSystem.Colors` and `DesignSystem.Fonts` — no hardcoded colors or font sizes
- No feature removal, no scope reduction
- Build must succeed before each commit
- Use existing patterns: `@Observable` + `@MainActor` for state, async/await for I/O, LazyVStack for lists

---

## Workstream A: Feed Content Display (CRITICAL + HIGH)

**Goal:** Fix broken thumbnails, HTML rendering, card UX, and feed error visibility. All 200+ feeds should display correct images and readable text.

**Files involved:** `FeedParser.swift`, `FeedFetcher.swift`, `FeedCard.swift`, `FeedToWOMAdapter.swift`, `DefaultFeeds.json`

### Task A.1: Parse media:thumbnails and itunes:image in FeedParser

**Files:**
- Modify: `Wirc/WircApp/Infrastructure/Feed/FeedParser.swift:151-156` (enclosure handler)
- Modify: `Wirc/WircApp/Infrastructure/Feed/FeedItem.swift:5-17` (add thumbnail field)

**Interfaces:**
- Consumes: `FeedParserDelegate.currentEnclosureURL`, `currentEnclosureType`
- Produces: `FeedItem.thumbnailURL: String?` — new optional field on the parsed item

- [ ] **Step 1: Add `thumbnailURL` to FeedItem struct**

In `Wirc/WircApp/Infrastructure/Feed/FeedItem.swift`, add the field after `enclosureType`:
```swift
struct FeedItem: Identifiable {
    let id = UUID()
    let title: String?
    let link: String
    let description: String?
    let publishedAt: Date?
    let author: String?
    let category: String?
    let enclosureURL: String?
    let enclosureType: String?
    let duration: String?
    var thumbnailURL: String?  // NEW: media:thumbnail or itunes:image href
}
```

- [ ] **Step 2: Parse `<media:thumbnail>` in FeedParser RSS handler**

In `Wirc/WircApp/Infrastructure/Feed/FeedParser.swift`, add to `handleRSSStart`:
```swift
// After the existing enclosure handler at line 152-155
if name == "media:thumbnail" || (name == "thumbnail" && namespaceURI?.contains("media") == true) {
    currentThumbnailURL = attributes["url"]
}
```

Add `private var currentThumbnailURL: String?` near line 57 alongside the other current-item vars.

- [ ] **Step 3: Parse `<itunes:image>` in FeedParser RSS handler**

In the same `handleRSSStart`, add:
```swift
if name == "image" && namespaceURI?.contains("itunes") == true {
    currentThumbnailURL = attributes["href"]
}
```

- [ ] **Step 4: Commit thumbnail URL in `commitItem()`**

In `Wirc/WircApp/Infrastructure/Feed/FeedParser.swift`, inside `commitItem()` (around line 246), add after the item fields:
```swift
currentThumbnailURL = nil  // reset after commit
```

And set it on the item:
```swift
let item = FeedItem(
    title: currentTitle,
    link: currentLink ?? "",
    description: currentDescription,
    publishedAt: currentPublishedAt,
    author: currentAuthor,
    category: currentCategory,
    enclosureURL: currentEnclosureURL,
    enclosureType: currentEnclosureType,
    duration: currentDuration,
    thumbnailURL: currentThumbnailURL  // NEW
)
```

- [ ] **Step 5: Wire thumbnailURL into WOMObject data in FeedToWOMAdapter**

In `Wirc/WircApp/Infrastructure/Feed/FeedToWOMAdapter.swift`, in `convertItem`, add after existing enclosure data (around line 57):
```swift
if let thumb = item.thumbnailURL { data["thumbnailURL"] = thumb }
```

- [ ] **Step 6: Use thumbnailURL in FeedCard image displays**

In `Wirc/WircApp/Infrastructure/Feed/FeedCard.swift`:
- YouTube content (line ~316): Change `post.data["enclosureURL"]` to `post.data["thumbnailURL"] ?? post.data["enclosureURL"]`
- Podcast content (line ~360): Change `post.data["enclosureURL"]` to `post.data["thumbnailURL"] ?? post.data["enclosureURL"]`

- [ ] **Step 7: Build and verify**

Run: `xcodebuild -project Wirc.xcodeproj -scheme Wirc -destination 'platform=iOS Simulator,id=D3A8E60A-D820-4E29-A7E3-BC32DE7AD990' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```bash
git add Wirc/WircApp/Infrastructure/Feed/FeedItem.swift Wirc/WircApp/Infrastructure/Feed/FeedParser.swift Wirc/WircApp/Infrastructure/Feed/FeedToWOMAdapter.swift Wirc/WircApp/Infrastructure/Feed/FeedCard.swift
git commit -m "fix: parse media:thumbnail and itunes:image, display in FeedCard"
```

### Task A.2: Resolve relative Atom URLs against feed URL

**Files:**
- Modify: `Wirc/WircApp/Infrastructure/Feed/FeedParser.swift:201`

- [ ] **Step 1: Add sourceURL-based resolution in commitItem**

In `commitItem()`, before constructing the `FeedItem`, resolve the link:
```swift
private func resolvedLink(_ href: String?) -> String {
    guard let href = href else { return "" }
    if href.hasPrefix("http://") || href.hasPrefix("https://") { return href }
    guard let base = URL(string: sourceURL) else { return href }
    return URL(string: href, relativeTo: base)?.absoluteString ?? href
}
```

Then change the `link` field assignment:
```swift
// In commitItem(), replace currentLink assignment:
link: resolvedLink(currentLink),
```

- [ ] **Step 2: Apply same resolution to enclosureURL**

In `commitItem()`, also resolve enclosure URLs:
```swift
enclosureURL: resolvedLink(currentEnclosureURL),
```

- [ ] **Step 3: Build and verify**

- [ ] **Step 4: Commit**

```bash
git add Wirc/WircApp/Infrastructure/Feed/FeedParser.swift
git commit -m "fix: resolve relative Atom URLs against feed base URL"
```

### Task A.3: Fix FeedCard tap UX — open article on first tap

**Files:**
- Modify: `Wirc/WircApp/Infrastructure/Feed/FeedCard.swift:49-59`, `Wirc/WircApp/Infrastructure/Feed/FeedCard.swift:57-103`

**Goal:** First tap opens the article URL directly. Expanded actions (Share, Copy, Inspect) move to long-press context menu.

- [ ] **Step 1: Replace onTapGesture with direct open**

Change the card tap behavior:
```swift
// Remove: .onTapGesture { withAnimation { isExpanded.toggle() } }
// Add:
.onTapGesture {
    if let url = cardURL {
        UIApplication.shared.open(url)
    }
}
.contextMenu {
    if let url = cardURL {
        Button { UIApplication.shared.open(url) } label: {
            Label("Open in Safari", systemImage: "safari")
        }
        Button {
            let avc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = scene.windows.first?.rootViewController {
                root.present(avc, animated: true)
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        Button { UIPasteboard.general.string = url.absoluteString } label: {
            Label("Copy Link", systemImage: "doc.on.doc")
        }
    }
    Button { showInspector = true } label: {
        Label("Inspect", systemImage: "info.circle")
    }
}
```

- [ ] **Step 2: Remove the expanded actions VStack**

Remove lines 59-103 (the `expandedActions` var and its rendering in body). The long-press context menu replaces it.

- [ ] **Step 3: Remove `@State private var isExpanded`**

Delete line 5: `@State private var isExpanded = false`

- [ ] **Step 4: Update provenance badge tap — open source URL**

Change provenance badge tap (around line 112):
```swift
// Remove: showInspector = true
// Replace with: open the feed URL or Mastodon profile
Button {
    if let feedURL = URL(string: post.data["feedURL"] ?? "") {
        UIApplication.shared.open(feedURL)
    }
} label: {
```

- [ ] **Step 5: Build and verify**

- [ ] **Step 6: Commit**

```bash
git add Wirc/WircApp/Infrastructure/Feed/FeedCard.swift
git commit -m "fix: tap to open article, long-press for actions, provenance opens source"
```

### Task A.4: Improve HTML stripping — preserve paragraph structure

**Files:**
- Modify: `Wirc/WircApp/Infrastructure/Feed/FeedCard.swift:473-483`

- [ ] **Step 1: Enhance stripHTML to insert newlines for block elements**

Replace the current `stripHTML` extension:
```swift
extension String {
    var stripHTML: String {
        var result = self
        // Insert newlines for block-level elements before stripping tags
        result = result.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "<p[^>]*>", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "</p>", with: "\n")
        result = result.replacingOccurrences(of: "<li[^>]*>", with: "\n• ", options: .regularExpression)
        result = result.replacingOccurrences(of: "</li>", with: "")
        result = result.replacingOccurrences(of: "<h[1-6][^>]*>", with: "\n\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "</h[1-6]>", with: "\n")
        // Now strip remaining HTML tags
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Decode common entities
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        // Collapse multiple blank lines
        result = result.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 2: Build and verify**

- [ ] **Step 3: Commit**

```bash
git add Wirc/WircApp/Infrastructure/Feed/FeedCard.swift
git commit -m "fix: preserve paragraph structure in stripHTML with newlines for block elements"
```

### Task A.5: Fix ThePrimeagen fake channel ID, remove duplicate feeds

**Files:**
- Modify: `Wirc/WircApp/Infrastructure/Feed/DefaultFeeds.json:184`

- [ ] **Step 1: Fix ThePrimeagen channel ID**

Replace line 184:
```json
{"title":"ThePrimeagen","url":"https://www.youtube.com/feeds/videos.xml?channel_id=UC2e2Y2Y2Y2Y2Y2Y2Y2Y2Y2Y2Q","type":"youtube"}
```
With:
```json
{"title":"ThePrimeagen","url":"https://www.youtube.com/feeds/videos.xml?channel_id=UC8ENHE5xdFSwx71u3fDH5Xw","type":"youtube"}
```

- [ ] **Step 2: Commit**

```bash
git add Wirc/WircApp/Infrastructure/Feed/DefaultFeeds.json
git commit -m "fix: correct ThePrimeagen YouTube channel ID"
```

### Task A.6: Fix RSS enclosure images not rendered

**Files:**
- Modify: `Wirc/WircApp/Infrastructure/Feed/FeedCard.swift:276-308` (rssContent)

- [ ] **Step 1: Add media rendering to rssContent**

Add after line 292 (after the body text line) in `rssContent`:
```swift
// Show enclosures that are images
if let encURL = post.data["enclosureURL"],
   let encType = post.data["enclosureType"],
   encType.hasPrefix("image/"),
   let url = URL(string: encURL) {
    AsyncImage(url: url) { phase in
        switch phase {
        case .success(let image):
            image.resizable().scaledToFit()
                .frame(maxHeight: 160)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.thumbnail))
        default:
            EmptyView()
        }
    }
    .padding(.horizontal, DesignSystem.Spacing.md)
}
```

- [ ] **Step 2: Build and verify**

- [ ] **Step 3: Commit**

```bash
git add Wirc/WircApp/Infrastructure/Feed/FeedCard.swift
git commit -m "fix: render image enclosures in RSS feed cards"
```

---

## Workstream B: IRC Robustness (HIGH + MEDIUM)

**Goal:** Fix connection handling bugs, state consistency, command system, and race conditions. Make IRC reliable.

**Files involved:** `IRCManager.swift`, `IRCClient.swift`, `IRCCommandExecutor.swift`, `IRCChatView.swift`, `IRCMessageDeckView.swift`, `ServerOrchestrator.swift`, `IRCParser.swift`

### Task B.1: Fix IRCClient QUIT race and fatal error handling

**Files:**
- Modify: `Wirc/WircApp/Infrastructure/IRC/IRCClient.swift:51-56` (disconnect)
- Modify: `Wirc/WircApp/Infrastructure/IRC/IRCClient.swift:164-178` (registration handler)

- [ ] **Step 1: Make disconnect wait for QUIT send completion**

Change `disconnect()` to use the contentProcessed callback:
```swift
func disconnect() {
    shouldReconnect = false
    write("QUIT :Wirc")
    // Give the write time to flush, then cancel
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        self?.connection?.cancel()
    }
}
```

- [ ] **Step 2: Handle fatal registration errors**

Add to the registration handler (after `if line.contains(" 433 ")`):
```swift
if line.contains(" 465 ") || line.contains(" 463 ") {
    // ERR_YOUREBANNEDCREEP or ERR_NOPERMFORHOST — stop retrying
    shouldReconnect = false
    onEvent?(.error("Banned from \(config.host)"))
    connection?.cancel()
    return
}
```

- [ ] **Step 3: Fix nick collision handler — use proper fallback**

After 5 nick retries, instead of silently giving up:
```swift
if nickRetry > 5 {
    onEvent?(.error("Could not register nickname on \(config.host) after 5 attempts"))
    disconnect()
    return
}
```

- [ ] **Step 4: Wire exponential backoff into reconnect**

In `scheduleReconnect()`, use `IRCAutomation` backoff:
```swift
private func scheduleReconnect() {
    guard shouldReconnect else { return }
    let delay = automation?.reconnectDelay() ?? 3.0  // use automation's backoff if available
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        guard let self, self.shouldReconnect else { return }
        self.connect()
    }
}
```

Add `weak var automation: IRCAutomation?` property to IRCClient. Set it in IRCManager when creating the client.

- [ ] **Step 5: Build and verify**

- [ ] **Step 6: Commit**

```bash
git add Wirc/WircApp/Infrastructure/IRC/IRCClient.swift Wirc/WircApp/App/IRCManager.swift
git commit -m "fix: IRC QUIT race, fatal error handling, nick fallback, backoff wiring"
```

### Task B.2: Fix ServerOrchestrator leaks and double-counting

**Files:**
- Modify: `Wirc/WircApp/Infrastructure/IRC/ServerOrchestrator.swift:138-155`

- [ ] **Step 1: Disconnect orphaned clients in finishServer**

Add disconnect call in `finishServer`:
```swift
private func finishServer(_ configId: UUID) {
    // Disconnect the client before removing
    if let entry = activeClients.first(where: { $0.configId == configId }) {
        entry.client.disconnect()
    }
    activeClients.removeAll { $0.configId == configId }
    scannedCount += 1
    updateProgress()
    if isScanning { connectNext() }
}
```

- [ ] **Step 2: Guard against double-count in timeout**

In the timeout block (line 138), check if already finished:
```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
    guard let self else { return }
    if self.activeClients.contains(where: { $0.configId == configId }) {
        self.finishServer(configId)
    }
}
```

- [ ] **Step 3: Add disconnect in stopScan**

In `stopScan()`, ensure all active clients are disconnected:
```swift
func stopScan() {
    isScanning = false
    pendingServers = []
    for (_, client, _) in activeClients {
        client.disconnect()
    }
    activeClients = []
    updateProgress()
}
```

- [ ] **Step 4: Build and verify**

- [ ] **Step 5: Commit**

```bash
git add Wirc/WircApp/Infrastructure/IRC/ServerOrchestrator.swift
git commit -m "fix: ServerOrchestrator leak, double-count, cleanup on stop"
```

### Task B.3: Fix IRC state consistency issues

**Files:**
- Modify: `Wirc/WircApp/App/IRCManager.swift:143-148`, `Wirc/WircApp/App/IRCManager.swift:242-247`, `Wirc/WircApp/App/IRCManager.swift:162`

- [ ] **Step 1: Case-insensitive channel handling in joinChannel**

```swift
func joinChannel(_ channel: String, serverId: UUID) {
    let ch = channel.hasPrefix("#") ? channel : "#\(channel)"
    clients[serverId]?.join(channel: ch)
    let lower = ch.lowercased()
    if !(joinedChannels[serverId]?.contains(where: { $0.lowercased() == lower }) ?? false) {
        joinedChannels[serverId, default: []].append(ch)
    }
}
```

- [ ] **Step 2: Scope nick changes to the source server only**

In `handleEvent` for `.nickChange`:
```swift
case .nickChange(let oldNick, let newNick):
    let prefix = "\(config.host)|"
    for (key, _) in channelUsers where key.hasPrefix(prefix) {
        if let idx = channelUsers[key]?.firstIndex(where: { $0.nick == oldNick }) {
            channelUsers[key]?[idx] = ChannelUser(nick: newNick, prefix: channelUsers[key]![idx].prefix)
        }
    }
```

- [ ] **Step 3: Reset isListing on disconnect**

In the `.disconnected` case in `handleEvent`, add:
```swift
isListing[serverId] = false
```

- [ ] **Step 4: Prevent duplicate client creation in connect(to:)**

```swift
func connect(to serverId: UUID) {
    // Disconnect existing client if any
    if let existing = clients[serverId] {
        existing.disconnect()
    }
    guard let config = config(for: serverId) else { return }
    let client = IRCClient(config: config)
    client.automation = automation
    // ...wire up events...
    clients[serverId] = client
    connectionStates[serverId] = .connecting
    client.connect()
}
```

- [ ] **Step 5: Build and verify**

- [ ] **Step 6: Commit**

```bash
git add Wirc/WircApp/App/IRCManager.swift
git commit -m "fix: case-insensitive channels, scoped nick changes, isListing reset, duplicate client prevention"
```

### Task B.4: Fix IRCChatView/DeckView UI issues

**Files:**
- Modify: `Wirc/WircApp/Features/Messages/IRCChatView.swift`
- Modify: `Wirc/WircApp/Features/Messages/IRCMessageDeckView.swift`

- [ ] **Step 1: Fix QuickJoinField to use active server, not always first**

In `IRCChatView.swift` around line 651, change:
```swift
// Before: servers.first?.id (always first server)
// After: use active channel's server, or first server as fallback
let targetServerId = manager.activeChannel?.serverId ?? appState.irc.servers.first?.id
guard let sid = targetServerId else { return }
```

- [ ] **Step 2: Scope expandedUsers by channel key (server + channel)**

Change `expandedUsers: Set<String>` to use full channel key. Update toggling logic:
```swift
func toggleUsers(for channel: ChannelHandle) {
    if expandedUsers.contains(channel.id) {
        expandedUsers.remove(channel.id)
    } else {
        expandedUsers.insert(channel.id)
    }
}
```

- [ ] **Step 3: Fix IRCMessageDeckView All-mode sending without WOM object**

In `IRCMessageDeckView.swift` send function, add local WOM object creation (mirror IRCChatView):
```swift
// After sending to each channel, create a local WOM object
let obj = WOMObject(
    id: WOMIDGenerator.generate(type: "message"),
    type: ["wom:Message"],
    createdAt: Date(),
    attributedTo: WOMReference(id: "local:user", type: ["wom:Person"], name: nick),
    content: WOMContent(format: "text/plain", text: text),
    data: ["network": "irc", "server": config.host, "isBroadcast": "true", "broadcastCount": "\(targets.count)"],
    provenance: .localUser()
)
Task { try? await appState.store.save(obj); appState.womObjects.append(obj) }
```

- [ ] **Step 4: Add command feedback toast to IRCMessageDeckView**

Same pattern as already implemented in IRCChatView (add `@State commandFeedback`, display toast overlay).

- [ ] **Step 5: Build and verify**

- [ ] **Step 6: Commit**

```bash
git add Wirc/WircApp/Features/Messages/IRCChatView.swift Wirc/WircApp/Features/Messages/IRCMessageDeckView.swift
git commit -m "fix: channel server scoping, broadcast WOM object, command feedback"
```

### Task B.5: Fix IRCParser crash safety

**Files:**
- Modify: `Wirc/WircApp/Infrastructure/IRC/IRCParser.swift:24-30`

- [ ] **Step 1: Guard against prefix-only lines**

```swift
func parse(rawLine: String) -> IRCEvent {
    // Handle IRCv3 tags
    var line = rawLine
    if line.hasPrefix("@") {
        if let spaceIdx = line.firstIndex(of: " ") {
            line = String(line[line.index(after: spaceIdx)...])
        }
    }
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .rawLine(rawLine) }
    
    let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    guard parts.count >= 2 else {
        return .rawLine(rawLine) // prefix-only line: ":server" — safe fallback
    }
    // ... rest of parsing
}
```

- [ ] **Step 2: Handle non-UTF-8 data in IRCClient readLoop**

In `IRCClient.swift`, log dropped data:
```swift
if let decoded = String(data: data, encoding: .utf8) {
    readBuffer += decoded
} else {
    // Log that non-UTF-8 data was dropped
    os_log(.debug, "IRCClient: dropped non-UTF-8 data from %{public}@", config.host)
}
```

- [ ] **Step 3: Build and verify**

- [ ] **Step 4: Commit**

```bash
git add Wirc/WircApp/Infrastructure/IRC/IRCParser.swift Wirc/WircApp/Infrastructure/IRC/IRCClient.swift
git commit -m "fix: IRCParser crash safety for prefix-only lines, log non-UTF-8 drops"
```

---

## Workstream C: Data & Persistence (HIGH + MEDIUM)

**Goal:** Fix caps, prevent data loss, add migration path, fix threading issues. Make the store reliable.

**Files involved:** `JSONFileStore.swift`, `AppState.swift`, `WOMObject.swift`, `WOMStore.swift`

### Task C.1: Sync the two 2000-object caps

**Files:**
- Modify: `Wirc/WircApp/App/AppState.swift:22-28`
- Modify: `Wirc/WircApp/Infrastructure/Persistence/JSONFileStore.swift:82-92` (saveMany)

- [ ] **Step 1: Apply cap in JSONFileStore at write time, not just load time**

In `JSONFileStore.swift`, add a `trimIndex()` helper and call it from `save()` and `saveMany()`:
```swift
private func trimIndex() {
    if index.count > maxIndexSize {
        let sorted = index.values.sorted { $0.createdAt > $1.createdAt }
        index = Dictionary(uniqueKeysWithValues: sorted.prefix(maxIndexSize).map { ($0.id, $0) })
    }
}
```

Call `trimIndex()` at the end of `save()`, `saveMany()`, and `saveIfNew()` success paths.

- [ ] **Step 2: Log when cap evicts objects**

In `AppState.swift` didSet for womObjects, log the eviction:
```swift
if womObjects.count > 2000 {
    let dropped = womObjects.count - 2000
    os_log(.debug, "AppState: evicting %d objects from womObjects cap", dropped)
    womObjects = Array(womObjects.suffix(2000))
}
```

- [ ] **Step 3: Add `Store.fullCount` to expose actual disk count**

Add to JSONFileStore:
```swift
var diskCount: Int {
    queue.sync { index.count }
}
```

- [ ] **Step 4: Build and verify**

- [ ] **Step 5: Commit**

```bash
git add Wirc/WircApp/Infrastructure/Persistence/JSONFileStore.swift Wirc/WircApp/App/AppState.swift
git commit -m "fix: synchronized JSONFileStore cap at write time, log evictions"
```

### Task C.2: Mitigate JSONFileStore deadlock risk

**Files:**
- Modify: `Wirc/WircApp/Infrastructure/Persistence/JSONFileStore.swift:98-103,128-133`

- [ ] **Step 1: Replace sync reads with async-safe pattern**

Change all `queue.sync` read calls to use async with continuation (safe against nested barrier calls):
```swift
func get(id: String) async throws -> WOMObject? {
    await withCheckedContinuation { continuation in
        queue.async { [weak self] in
            continuation.resume(returning: self?.index[id])
        }
    }
}
```

Apply same pattern to `list(type:)`, `all()`, `count`, `contains(canonicalURL:)`.

- [ ] **Step 2: Build and verify**

- [ ] **Step 3: Commit**

```bash
git add Wirc/WircApp/Infrastructure/Persistence/JSONFileStore.swift
git commit -m "fix: replace sync reads with async continuation to prevent deadlock"
```

### Task C.3: Add migration path and corruption resilience

**Files:**
- Modify: `Wirc/WircApp/Infrastructure/Persistence/JSONFileStore.swift:189-208` (loadIndex)

- [ ] **Step 1: Add schema version check**

Add a `private static let schemaVersion = 1` to JSONFileStore. Store it in UserDefaults:
```swift
private func checkSchemaVersion() -> Bool {
    let key = "wirc.store.schemaVersion"
    let stored = UserDefaults.standard.integer(forKey: key)
    if stored < Self.schemaVersion {
        // Migration needed — for v1, just reload
        UserDefaults.standard.set(Self.schemaVersion, forKey: key)
        return true
    }
    return stored == Self.schemaVersion
}
```

- [ ] **Step 2: Log corrupted files instead of silently skipping**

In loadIndex, add logging:
```swift
guard let data = try? Data(contentsOf: url) else {
    os_log(.error, "JSONFileStore: could not read file %{public}@", url.lastPathComponent)
    continue
}
guard let obj = try? JSONDecoder().decode(WOMObject.self, from: data) else {
    os_log(.error, "JSONFileStore: corrupted file %{public}@", url.lastPathComponent)
    continue
}
```

- [ ] **Step 3: Add graceful fallback for missing document directory**

```swift
init() {
    guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
        os_log(.error, "JSONFileStore: no document directory — using in-memory mode")
        objectsDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wirc-fallback")
        try? FileManager.default.createDirectory(at: objectsDir, withIntermediateDirectories: true)
        return
    }
    // ... existing init
}
```

- [ ] **Step 4: Build and verify**

- [ ] **Step 5: Commit**

```bash
git add Wirc/WircApp/Infrastructure/Persistence/JSONFileStore.swift
git commit -m "fix: add schema versioning, corruption logging, graceful fallback"
```

### Task C.4: Add secondary index on canonicalUrl for O(1) dedup

**Files:**
- Modify: `Wirc/WircApp/Infrastructure/Persistence/JSONFileStore.swift:137-158`

- [ ] **Step 1: Add canonicalUrl index**

Add `private var canonicalIndex: [String: String] = [:]` (maps canonicalUrl → objectId). Maintain it on save/delete. Update `saveIfNew` to use O(1) lookup:
```swift
func saveIfNew(_ object: WOMObject, byCanonicalURL canonicalURL: String) async throws -> Bool {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
        queue.async(flags: .barrier) { [weak self] in
            guard let self else { continuation.resume(throwing: ...); return }
            if self.canonicalIndex[canonicalURL] != nil {
                continuation.resume(returning: false)
                return
            }
            do {
                try self.writeObject(object)
                self.index[object.id] = object
                self.canonicalIndex[canonicalURL] = object.id
                continuation.resume(returning: true)
            } catch { continuation.resume(throwing: error) }
        }
    }
}
```

- [ ] **Step 2: Build and verify**

- [ ] **Step 3: Commit**

```bash
git add Wirc/WircApp/Infrastructure/Persistence/JSONFileStore.swift
git commit -m "perf: O(1) dedup via canonicalUrl index instead of O(n) scan"
```

---

## Workstream D: Mastodon Integration (CRITICAL + MEDIUM)

**Goal:** Fix broken account creation, secure token storage, improve reliability.

**Files involved:** `AppState.swift`, `MastodonClient.swift`, `MastodonToWOMAdapter.swift`, `MastodonModels.swift`, `WorkshopView.swift`

### Task D.1: Implement Mastodon account creation

**Files:**
- Modify: `Wirc/WircApp/App/AppState.swift:196-198`
- Modify: `Wirc/WircApp/Features/Workshop/WorkshopView.swift`

- [ ] **Step 1: Implement `loadMastodonAccounts()`**

Replace the stub:
```swift
private func loadMastodonAccounts() {
    guard let data = UserDefaults.standard.data(forKey: mastodonAccountsKey) else { return }
    if let accounts = try? JSONDecoder().decode([MastodonServerConfig].self, from: data) {
        mastodonAccounts = accounts
    }
}
```

- [ ] **Step 2: Implement `addMastodonAccount()`**

Replace the stub:
```swift
func addMastodonAccount(name: String, instanceURL: String, token: String) {
    let account = MastodonServerConfig(id: UUID(), name: name, instanceURL: instanceURL, accessToken: token)
    mastodonAccounts.append(account)
}
```

- [ ] **Step 3: Add "Add Account" button to MastodonTransportDetail**

In `WorkshopView.swift` MastodonTransportDetail, add:
```swift
.toolbar {
    ToolbarItem(placement: .navigationBarTrailing) {
        Button { showAddMastodon = true } label: {
            Image(systemName: "plus")
        }
    }
}
.sheet(isPresented: $showAddMastodon) {
    AddMastodonView { name, url, token in
        appState.addMastodonAccount(name: name, instanceURL: url, token: token)
    }
}
```

Add `@State private var showAddMastodon = false` to the view.

- [ ] **Step 4: Add delete support to MastodonTransportDetail**

Add swipe-to-delete:
```swift
ForEach(appState.mastodonAccounts) { account in
    // ...existing row...
}
.onDelete { indexSet in
    for idx in indexSet {
        appState.removeMastodonAccount(id: appState.mastodonAccounts[idx].id)
    }
}
```

- [ ] **Step 5: Build and verify**

- [ ] **Step 6: Commit**

```bash
git add Wirc/WircApp/App/AppState.swift Wirc/WircApp/Features/Workshop/WorkshopView.swift
git commit -m "fix: implement Mastodon account CRUD with add and delete"
```

### Task D.2: Move Mastodon token to Keychain

**Files:**
- Modify: `Wirc/WircApp/App/AppState.swift:195` (save/load)
- Create: `Wirc/WircApp/Infrastructure/Mastodon/KeychainStore.swift`

- [ ] **Step 1: Create KeychainStore helper**

```swift
import Security
import Foundation

enum KeychainStore {
    static func save(key: String, data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }
    
    static func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        return result as? Data
    }
    
    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

- [ ] **Step 2: Store only non-sensitive config in UserDefaults, token in Keychain**

Update `saveMastodonAccounts()`:
```swift
private func saveMastodonAccounts() {
    // Store token in Keychain, rest in UserDefaults
    var safeAccounts: [MastodonStoredConfig] = []
    for account in mastodonAccounts {
        let key = "wirc.mastodon.token.\(account.id.uuidString)"
        if let tokenData = account.accessToken.data(using: .utf8) {
            KeychainStore.save(key: key, data: tokenData)
        }
        safeAccounts.append(MastodonStoredConfig(id: account.id, name: account.name, instanceURL: account.instanceURL))
    }
    if let d = try? JSONEncoder().encode(safeAccounts) {
        UserDefaults.standard.set(d, forKey: mastodonAccountsKey)
    }
}
```

Update `loadMastodonAccounts()` to hydrate tokens from Keychain.

- [ ] **Step 3: Add KeychainStore to Xcode project**

Add `KeychainStore.swift` to the Mastodon group in the Xcode project.

- [ ] **Step 4: Build and verify**

- [ ] **Step 5: Commit**

```bash
git add Wirc/WircApp/Infrastructure/Mastodon/KeychainStore.swift Wirc/WircApp/App/AppState.swift
git commit -m "security: move Mastodon access tokens to Keychain from plaintext UserDefaults"
```

### Task D.3: Add rate limiting and pagination to MastodonClient

**Files:**
- Modify: `Wirc/WircApp/Infrastructure/Mastodon/MastodonClient.swift`
- Modify: `Wirc/WircApp/App/AppState.swift:201-216`

- [ ] **Step 1: Parse rate limit headers in MastodonClient**

Add rate limit tracking:
```swift
private var rateLimitRemaining: Int = 300
private var rateLimitReset: Date = .distantPast

private func updateRateLimits(from response: HTTPURLResponse) {
    if let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining") {
        rateLimitRemaining = Int(remaining) ?? rateLimitRemaining
    }
    if let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset") {
        if let epoch = Double(reset) {
            rateLimitReset = Date(timeIntervalSince1970: epoch)
        }
    }
}

private func checkRateLimit() async throws {
    if rateLimitRemaining <= 0 && Date() < rateLimitReset {
        let wait = rateLimitReset.timeIntervalSinceNow
        if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
    }
}
```

Call `checkRateLimit()` before each API request.

- [ ] **Step 2: Add pagination to refreshMastodonFeed**

Use `maxId` to avoid re-fetching:
```swift
func refreshMastodonFeed(accountId: UUID) {
    // ... setup client ...
    let lastId: String? = nil  // TODO: store last fetched ID per account
    let timeline = try await client.homeTimeline(limit: 40, maxId: lastId)
    // ... process ...
}
```

- [ ] **Step 3: Make MastodonClient JSONDecoder a local variable, not stored property**

Change from `private let decoder = JSONDecoder()` to creating a new one in each request method. Remove the shared instance to eliminate thread safety concern.

- [ ] **Step 4: Build and verify**

- [ ] **Step 5: Commit**

```bash
git add Wirc/WircApp/Infrastructure/Mastodon/MastodonClient.swift Wirc/WircApp/App/AppState.swift
git commit -m "fix: add Mastodon rate limiting, pagination, thread-safe decoder"
```

### Task D.4: Fix Mastodon date parsing and formatter duplication

**Files:**
- Modify: `Wirc/WircApp/Infrastructure/Mastodon/MastodonToWOMAdapter.swift`
- Modify: `Wirc/WircApp/Infrastructure/Mastodon/MastodonModels.swift`

- [ ] **Step 1: Extract shared date parsing to a static utility**

Add to `MastodonToWOMAdapter.swift`:
```swift
extension MastodonToWOMAdapter {
    static let dateFormatters: [DateFormatter] = {
        let fmts = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSSZ",
        ]
        return fmts.map { fmt in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = fmt
            return f
        }
    }()
    
    static let isoFormatter = ISO8601DateFormatter()
    
    static func parseMastodonDate(_ s: String) -> Date? {
        for fmt in dateFormatters {
            if let d = fmt.date(from: s) { return d }
        }
        return isoFormatter.date(from: s)
    }
}
```

- [ ] **Step 2: Update both MastodonToWOMAdapter and MastodonStatus to use shared parser**

Replace inline date parsing in both files with `MastodonToWOMAdapter.parseMastodonDate(s)`.

- [ ] **Step 3: Fix reblog date formatter allocation**

Replace `ISO8601DateFormatter().string(from: date)` with a cached static instance.

- [ ] **Step 4: Build and verify**

- [ ] **Step 5: Commit**

```bash
git add Wirc/WircApp/Infrastructure/Mastodon/MastodonToWOMAdapter.swift Wirc/WircApp/Infrastructure/Mastodon/MastodonModels.swift
git commit -m "fix: shared Mastodon date parser, cached formatters, wider format coverage"
```

---

## Workstream E: Navigation & Architecture (HIGH + MEDIUM)

**Goal:** Restore orphaned views, fix navigation dead ends, implement governance UI, fix inspector.

**Files involved:** `WircApp.swift`, `SettingsView.swift`, `WorkshopView.swift`, `ObjectInspectorSheet.swift`, `AppState.swift`

### Task E.1: Integrate orphaned SettingsView

**Files:**
- Modify: `Wirc/WircApp/App/WircApp.swift:7-35`

- [ ] **Step 1: Add SettingsView as a tab or replace Workshop**

Replace the 4-tab layout with a 5-tab layout, or merge Settings into Workshop. Recommended: add a 5th tab:
```swift
TabView {
    StreamView().tabItem { Label("Stream", systemImage: "waveform") }
    IRCChatView().tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right") }
    LibraryView().tabItem { Label("Library", systemImage: "archivebox") }
    WorkshopView().tabItem { Label("Workshop", systemImage: "hammer") }
    SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
}
.environment(appState)
```

- [ ] **Step 2: Remove duplicate functionality from Workshop**

Move IRC server management and Mastodon account management to SettingsView. Workshop keeps transports overview and debug.

- [ ] **Step 3: Ensure SettingsView uses DesignSystem colors and fonts**

Fix all hardcoded `.secondary`, `.red`, `.blue`, `.gray`, `.orange`, `.green` colors to use `DesignSystem.Colors.*`. Replace all hardcoded `.system(size:)` fonts with `DesignSystem.Fonts.*`.

- [ ] **Step 4: Build and verify**

- [ ] **Step 5: Commit**

```bash
git add Wirc/WircApp/App/WircApp.swift Wirc/WircApp/Features/Settings/SettingsView.swift Wirc/WircApp/Features/Workshop/WorkshopView.swift
git commit -m "feat: add Settings tab, restore orphaned server/mastodon management"
```

### Task E.2: Make governance defaults interactive

**Files:**
- Modify: `Wirc/WircApp/Features/Workshop/WorkshopView.swift:100-138`

- [ ] **Step 1: Replace read-only display with Pickers**

Replace the static labels with interactive controls connected to AppState:
```swift
@AppStorage("wirc.governance.adsUse") private var adsUse: String = WOMAdsUse.notAllowed.rawValue
@AppStorage("wirc.governance.agentUse") private var agentUse: String = "allowed"
@AppStorage("wirc.governance.sharing") private var defaultSharing: String = WOMSharing.friendsOnly.rawValue
@AppStorage("wirc.governance.retention") private var retention: String = "forever"

// In the body:
Section("Defaults for new objects") {
    Picker("Ads use", selection: $adsUse) {
        Text("Not allowed").tag(WOMAdsUse.notAllowed.rawValue)
        Text("Allowed").tag(WOMAdsUse.allowed.rawValue)
    }
    Picker("Agent use", selection: $agentUse) {
        Text("Allowed").tag("allowed")
        Text("Restricted").tag("restricted")
        Text("Prohibited").tag("prohibited")
    }
    Picker("Default sharing", selection: $defaultSharing) {
        ForEach(WOMSharing.allCases, id: \.rawValue) { level in
            Text(level.rawValue.capitalized).tag(level.rawValue)
        }
    }
    Picker("Retention", selection: $retention) {
        Text("Forever").tag("forever")
        Text("1 year").tag("1y")
        Text("90 days").tag("90d")
        Text("30 days").tag("30d")
    }
} footer: {
    Text("Applied to new objects created from this device. Existing objects are not modified.")
}
```

- [ ] **Step 2: Build and verify**

- [ ] **Step 3: Commit**

```bash
git add Wirc/WircApp/Features/Workshop/WorkshopView.swift
git commit -m "feat: make governance defaults interactive with AppStorage persistence"
```

### Task E.3: Improve ObjectInspectorSheet

**Files:**
- Modify: `Wirc/WircApp/Features/Shared/ObjectInspectorSheet.swift`

- [ ] **Step 1: Add content display section**

After the Object ID section, add:
```swift
Section("Content") {
    if let name = object.name {
        LabeledContent("Name", value: name)
    }
    if let text = object.content?.text {
        VStack(alignment: .leading, spacing: 8) {
            Text("Body").font(.caption).foregroundStyle(.secondary)
            Text(text).font(.body)
        }
    }
    if !object.attachments.isEmpty {
        LabeledContent("Attachments", value: "\(object.attachments.count) items")
        ForEach(object.attachments) { att in
            Text(att.id).font(.caption).foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 2: Show transport info for feed objects without bindings**

Replace "No binding" with data from `object.data`:
```swift
if object.data["network"] != nil {
    Section("Transport") {
        if let network = object.data["network"] { LabeledContent("Network", value: network.capitalized) }
        if let feedURL = object.data["feedURL"] { LabeledContent("Feed URL", value: feedURL) }
        if let server = object.data["server"] { LabeledContent("Server", value: server) }
        if let channel = object.data["channel"] { LabeledContent("Channel", value: channel) }
    }
}
```

- [ ] **Step 3: Build and verify**

- [ ] **Step 4: Commit**

```bash
git add Wirc/WircApp/Features/Shared/ObjectInspectorSheet.swift
git commit -m "feat: show content and transport data in ObjectInspectorSheet"
```

### Task E.4: Wire up stubbed buttons

**Files:**
- Modify: `Wirc/WircApp/Features/Messages/IRCChatView.swift:380` (Add Server)
- Modify: `Wirc/WircApp/Features/Workshop/WorkshopView.swift:148` (Import WOM)

- [ ] **Step 1: Wire Add Server button**

Replace the empty comment block:
```swift
Button { showServerManager = true } label: {
    Label("Add Server", systemImage: "plus")
}
// Ensure showServerManager sheet presents IRCServerManagerSheet
```

- [ ] **Step 2: Implement Import WOM file picker**

Replace the empty comment block:
```swift
Button {
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json])
    // Present picker and handle selected file
    isShowingPicker = true
} label: {
    Label("Import WOM Bundle", systemImage: "doc.badge.plus")
}
.fileImporter(isPresented: $isShowingPicker, allowedContentTypes: [.json]) { result in
    if case .success(let url) = result {
        guard let data = try? Data(contentsOf: url),
              let objects = try? JSONDecoder().decode([WOMObject].self, from: data) else { return }
        Task {
            try? await appState.store.saveMany(objects)
            await MainActor.run { appState.womObjects.append(contentsOf: objects) }
        }
    }
}
```

- [ ] **Step 3: Build and verify**

- [ ] **Step 4: Commit**

```bash
git add Wirc/WircApp/Features/Messages/IRCChatView.swift Wirc/WircApp/Features/Workshop/WorkshopView.swift
git commit -m "fix: wire Add Server button, implement Import WOM file picker"
```

---

## Workstream F: Accessibility & Design (HIGH + MEDIUM)

**Goal:** Add Dynamic Type support, Dark Mode, accessibility labels, and design consistency.

**Files involved:** `DesignSystem.swift`, `FeedCard.swift`, `LibraryView.swift`, `IRCChatView.swift`, `WorkshopView.swift`, all settings/add views

### Task F.1: Add Dynamic Type support to DesignSystem.Fonts

**Files:**
- Modify: `Wirc/WircApp/Core/DesignSystem.swift:75-108`

- [ ] **Step 1: Replace fixed-point fonts with scaled fonts**

Update DesignSystem.Fonts:
```swift
enum Fonts {
    static func headline(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }
    static func body(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }
    // Use TextStyle-relative sizing:
    static let messageBody: Font = .body  // scales with Dynamic Type
    static let caption: Font = .caption
    static let chipLabel: Font = .system(.subheadline, design: .default)
    static let provenanceLabel: Font = .caption
    static let provenanceDetail: Font = .caption2
    static let timestamp: Font = .caption2
    static let footer: Font = .caption2
    static let dateHeader: Font = .subheadline
    static let badge: Font = .caption2
    
    // For code/debug text (fixed size acceptable):
    static func mono(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }
    static func data(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}
```

- [ ] **Step 2: Build and verify**

- [ ] **Step 3: Commit**

```bash
git add Wirc/WircApp/Core/DesignSystem.swift
git commit -m "a11y: add Dynamic Type support via text style-relative fonts"
```

### Task F.2: Add Dark Mode support

**Files:**
- Modify: `Wirc/WircApp/Core/DesignSystem.swift:9-26`

- [ ] **Step 1: Add dark mode color variants**

Replace absolute hex colors with color set-based or semantic colors:
```swift
enum Colors {
    static let page = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(hex: "1C1917")
            : UIColor(hex: "F6F3ED")
    })
    static let surface = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(hex: "292524")
            : UIColor.white
    })
    static let ink = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(hex: "F6F3ED")
            : UIColor(hex: "1C1917")
    })
    static let pencil = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(hex: "B8B0A8")
            : UIColor(hex: "78716C")
    })
    static let border = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(hex: "44403C")
            : UIColor(hex: "E7E5E2")
    })
    static let signal = Color(hex: "E85D3A") // same in both modes
    static let irc = signal
    static let mastodon = Color(hex: "6364FF")
    static let rss = Color(hex: "F26522")
    static let youtube = Color(hex: "FF0000")
    static let podcast = Color(hex: "8B5CF6")
    static let github = Color(hex: "2DA44E")
}
```

- [ ] **Step 2: Build and verify**

- [ ] **Step 3: Commit**

```bash
git add Wirc/WircApp/Core/DesignSystem.swift
git commit -m "a11y: add dark mode support with semantic color resolution"
```

### Task F.3: Add accessibility labels to key interactive elements

**Files:**
- Modify: `Wirc/WircApp/Infrastructure/Feed/FeedCard.swift`
- Modify: `Wirc/WircApp/Features/Messages/IRCChatView.swift`
- Modify: `Wirc/WircApp/Features/Library/LibraryView.swift`

- [ ] **Step 1: Add accessibility to FeedCard**

In FeedCard body, add:
```swift
.accessibilityElement(children: .combine)
.accessibilityLabel("\(networkDisplayName) post: \(post.name ?? post.content?.text?.stripHTML.prefix(100) ?? "untitled")")
.accessibilityAddTraits(.isButton)
.accessibilityHint("Double-tap to open article")
```

- [ ] **Step 2: Add accessibility to send button**

In IRCChatView input bar, add:
```swift
Button { send() } label: {
    Image(systemName: "arrow.up.circle.fill")
}
.accessibilityLabel("Send message")
.accessibilityHint("Sends your message to the current channel")
```

- [ ] **Step 3: Add text labels alongside color indicators**

In LibraryRow, add a text label next to the colored circle:
```swift
HStack {
    Circle().fill(sourceColor).frame(width: 8, height: 8)
    Text(networkDisplayName).font(.caption).foregroundStyle(.secondary)
}
.accessibilityElement(children: .combine)
```

- [ ] **Step 4: Fix small tap targets**

In FeedCard action buttons, add minimum touch area:
```swift
Button { ... } label: { ... }
    .frame(minWidth: 44, minHeight: 44)
    .contentShape(Rectangle())
```

- [ ] **Step 5: Build and verify**

- [ ] **Step 6: Commit**

```bash
git add Wirc/WircApp/Infrastructure/Feed/FeedCard.swift Wirc/WircApp/Features/Messages/IRCChatView.swift Wirc/WircApp/Features/Library/LibraryView.swift
git commit -m "a11y: add VoiceOver labels, text alternatives, minimum touch targets"
```

---

## Workstream G: Code Quality & Cleanup (LOW)

**Goal:** Remove dead code, fix design inconsistencies, polish edges.

**Files involved:** Various — ~15 files with hardcoded fonts, colors, dead methods

### Task G.1: Replace hardcoded system fonts with DesignSystem.Fonts

**Files:**
- Modify: `Wirc/WircApp/Features/Workshop/WorkshopView.swift` (~8 occurrences)
- Modify: `Wirc/WircApp/Features/Settings/SettingsView.swift` (~10)
- Modify: `Wirc/WircApp/Features/Debug/RawEventLogView.swift` (~5)
- Modify: `Wirc/WircApp/Features/Debug/WOMObjectInspectorView.swift` (~5)
- Modify: `Wirc/WircApp/Features/Workshop/FeedTransportDetail.swift` (~3)
- Modify: `Wirc/WircApp/Features/Workshop/MastodonTransportDetail.swift` (~2)

- [ ] **Step 1: Replace all remaining `.system(size:)` calls with DesignSystem.Fonts**

Scan and replace in each file. Key mapping:
- `.system(size: 15, weight: .medium)` → `DesignSystem.Fonts.headline(15)`
- `.system(size: 13)` → `DesignSystem.Fonts.data(13)`
- `.caption`, `.caption2` → `DesignSystem.Fonts.caption`
- `.subheadline`, `.headline` → `DesignSystem.Fonts.caption` or appropriate token

- [ ] **Step 2: Build and verify**

- [ ] **Step 3: Commit**

```bash
git add Wirc/WircApp/Features/Workshop/WorkshopView.swift Wirc/WircApp/Features/Settings/SettingsView.swift Wirc/WircApp/Features/Debug/RawEventLogView.swift Wirc/WircApp/Features/Debug/WOMObjectInspectorView.swift
git commit -m "refactor: replace hardcoded fonts with DesignSystem.Fonts tokens"
```

### Task G.2: Replace hardcoded colors with DesignSystem.Colors

**Files:**
- Modify: `Wirc/WircApp/Features/Settings/SettingsView.swift` (~10 occurrences)
- Modify: `Wirc/WircApp/Features/Settings/AddServerView.swift` (~5)
- Modify: `Wirc/WircApp/Features/Debug/RawEventLogView.swift` (~5)

- [ ] **Step 1: Replace all `.foregroundStyle(.secondary)` → `.foregroundStyle(DesignSystem.Colors.pencil)`**

Replace `.foregroundStyle(.red)` → `DesignSystem.Colors.signal`, `.foregroundStyle(.blue)` → appropriate semantic color.

- [ ] **Step 2: Replace SettingsView background**

Add `.scrollContentBackground(.hidden)` and `.background(DesignSystem.Colors.page)` to SettingsView List.

- [ ] **Step 3: Build and verify**

- [ ] **Step 4: Commit**

```bash
git add Wirc/WircApp/Features/Settings/SettingsView.swift Wirc/WircApp/Features/Settings/AddServerView.swift Wirc/WircApp/Features/Debug/RawEventLogView.swift
git commit -m "refactor: replace hardcoded colors with DesignSystem.Colors tokens"
```

### Task G.3: Remove dead code

**Files:**
- Modify: `Wirc/WircApp/Infrastructure/Feed/FeedToWOMAdapter.swift:35-37` (convertSingle)
- Modify: `Wirc/WircApp/App/FeedManager.swift:82` (onBatch parameter — or keep but note it's unused)
- Modify: `Wirc/WircApp/Core/WOM/` — remove unused WOM types

- [ ] **Step 1: Remove `convertSingle` dead code**

Delete the method, it's never called.

- [ ] **Step 2: Remove unused WOM type files**

Delete files that are never instantiated. Keep only: `WOMObject.swift`, `WOMEnums.swift`, `WOMContent.swift`, `WOMReference.swift`, `WOMProvenance.swift`, `WOMClassification.swift`, `WOMGovernance.swift`, `WOMBindings.swift`. Delete: `WOMAnnotation.swift`, `WOMCanonicalizer.swift`, `WOMCrypto.swift`, `WOMEncrypted.swift`, `WOMIdentity.swift`, `WOMKnowledge.swift`, `WOMLite.swift`, `WOMProof.swift`, `WOMRelation.swift`.

- [ ] **Step 3: Remove redundant `defaultGovernance` switch**

Replace with single-line:
```swift
private func defaultGovernance(for sourceType: FeedSourceType) -> WOMGovernance {
    WOMGovernance(purpose: ["curation"], adsUse: WOMAdsUse.notAllowed.rawValue,
                  agentUse: "allowed", sharing: WOMSharing.public.rawValue, retention: "forever")
}
```

- [ ] **Step 4: Remove `feedLoading` toggle in refreshFeed**

Remove lines 126-127 (`feedLoading = true; feedError = nil` and `defer { feedLoading = false }`) since nothing reads `feedLoading`.

- [ ] **Step 5: Remove telemetry from production UI header**

In IRCChatView, gate the debug telemetry line behind `#if DEBUG`:
```swift
#if DEBUG
Text("Σ\(appState.irc.totalEventsReceived) p\(appState.irc.privmsgCount)")
    .font(.system(size: 8))
    .foregroundStyle(DesignSystem.Colors.signal)
#endif
```

- [ ] **Step 6: Build and verify**

- [ ] **Step 7: Commit**

```bash
git add Wirc/WircApp/Infrastructure/Feed/FeedToWOMAdapter.swift Wirc/WircApp/App/FeedManager.swift Wirc/WircApp/Features/Messages/IRCChatView.swift
git commit -m "refactor: remove dead code, gate debug telemetry, simplify governance"
```

### Task G.4: Fix filter bar capitalization inconsistency

**Files:**
- Modify: `Wirc/WircApp/Features/Stream/StreamView.swift:24`

- [ ] **Step 1: Match filter bar caps to FeedCard display**

Change the order list to match `networkDisplayName`:
```swift
let order = ["RSS", "Mastodon", "YouTube", "Podcast", "GitHub"]
// Build sourceFilters using the display name directly
var sources = Set<String>()
for obj in posts {
    let network = obj.data["network"] ?? ""
    if !network.isEmpty { sources.insert(networkDisplayName(network)) }
}
```

- [ ] **Step 2: Extract networkDisplayName as shared helper**

Move `networkDisplayName` logic to a shared location (or duplicate in StreamView for now).

- [ ] **Step 3: Build and verify**

- [ ] **Step 4: Commit**

```bash
git add Wirc/WircApp/Features/Stream/StreamView.swift
git commit -m "fix: consistent source name capitalization between filter bar and cards"
```

### Task G.5: Add card minimum height and visual consistency

**Files:**
- Modify: `Wirc/WircApp/Infrastructure/Feed/FeedCard.swift:36-55`

- [ ] **Step 1: Add minimum height to cards**

```swift
.frame(minHeight: 80)
```

- [ ] **Step 2: Remove duplicate feedTitle in RSS content footer**

In `rssContent`, remove the `Text(author)` from the body area when the same information already appears in the provenance badge. Keep it only in the footer.

- [ ] **Step 3: Fix duplicate YouTube/Podcast pill labels**

Remove the hardcoded "YouTube" / "Podcast" pills — the provenance badge already identifies the source. Keep only the duration and timestamp.

- [ ] **Step 4: Build and verify**

- [ ] **Step 5: Commit**

```bash
git add Wirc/WircApp/Infrastructure/Feed/FeedCard.swift
git commit -m "fix: card visual consistency, remove duplicate labels, min height"
```

---

## Execution Order

### Recommended Order:
1. **C** (Data) — foundation fixes for caps and threading
2. **D** (Mastodon) — unblocks account creation
3. **A** (Feed) — fixes most visible UX issues
4. **B** (IRC) — connection and state reliability
5. **E** (Navigation) — structural fixes
6. **F** (Accessibility) — a11y improvements
7. **G** (Cleanup) — polish

Or run all 7 streams in parallel using subagent-driven development for maximum throughput.

### Dependency Graph:
```
C (Data) ── independent
D (Mastodon) ── independent  
A (Feed) ── independent
B (IRC) ── independent
E (Navigation) ── depends on D.1 (account creation)
F (Accessibility) ── depends on G.1 (font cleanup)
G (Cleanup) ── independent, should run last to avoid conflicts
```

### Estimated Effort:
- Stream A: 6 tasks, ~3 hours
- Stream B: 5 tasks, ~2.5 hours
- Stream C: 4 tasks, ~2 hours
- Stream D: 4 tasks, ~2 hours
- Stream E: 4 tasks, ~1.5 hours
- Stream F: 3 tasks, ~1.5 hours
- Stream G: 5 tasks, ~2 hours
- **Total: 31 tasks, ~14.5 hours**
