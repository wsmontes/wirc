# Remaining 29 Issues — Final Pass

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Resolve all 29 remaining issues from the Wirc comprehensive audit — data loss bugs, IRC reliability, UI polish, accessibility, and dead code removal.

**Architecture:** 29 issues grouped into 6 independent workstreams. Each stream compiles and ships independently. Tasks are bite-sized — one commit per task with build verification.

**Tech Stack:** Swift 6, SwiftUI, iOS 17+, `@Observable`, `NWConnection`, `URLSession`, `XMLParser`, `JSONFileStore`

## Global Constraints

- iOS 17.0 minimum deployment target
- Swift 6 concurrency safety — no new `@unchecked Sendable` without justification
- All new UI must use `DesignSystem.Colors` and `DesignSystem.Fonts` tokens
- Build must succeed before each commit (`xcodebuild -project Wirc/Wirc.xcodeproj -scheme Wirc -destination 'platform=iOS Simulator,id=D3A8E60A-D820-4E29-A7E3-BC32DE7AD990' build`)
- No feature removal, no scope reduction
- Follow existing patterns: `@Observable` + `@MainActor` for state, async/await for I/O, LazyVStack for lists

---
```

## Workstream H: Remaining Data Integrity (4 tasks)

### Task H.1: FeedParser — don't skip items without title

**Files:**
- Modify: `Wirc/WircApp/Infrastructure/Feed/FeedParser.swift:259-263`

**Goal:** The `commitItem()` method requires `currentTitle` to be non-nil and skips items without it. Many valid Atom entries only have `<summary>` and podcast episodes may use `<itunes:title>`. Change the guard to allow items with at least title OR description.

- [ ] **Step 1: Change the guard in commitItem()**

In `Wirc/WircApp/Infrastructure/Feed/FeedParser.swift`, find `commitItem()` (around line 259). Replace:

```swift
guard let title = currentTitle else {
    resetItemState()
    return
}
```

With:

```swift
let title = currentTitle ?? (currentDescription?.prefix(100).map { String($0) } ?? "Untitled")
```

And remove the `guard let title` below (line 264) since `title` is now a non-optional `String`. The rest of the method uses `title: title` parameter — that stays the same.

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project Wirc/Wirc.xcodeproj -scheme Wirc -destination 'platform=iOS Simulator,id=D3A8E60A-D820-4E29-A7E3-BC32DE7AD990' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Wirc/WircApp/Infrastructure/Feed/FeedParser.swift
git commit -m "fix: don't drop feed items without title, use description prefix fallback"
```

### Task H.2: Store-level pagination for loadOlderMessages

**Files:**
- Modify: `Wirc/WircApp/Infrastructure/IRC/IRCChannelManager.swift:91-125`

**Goal:** `loadOlderMessages()` only reads from in-memory `allObjects`. When objects are evicted by the 2000-item cap, old messages are permanently inaccessible. Fix by falling back to the persistent store.

- [ ] **Step 1: Add store query fallback**

In `loadOlderMessages()`, after filtering `allObjects`, if the result has fewer than 50 items, query the persistent store:

```swift
func loadOlderMessages() async {
    guard !isLoadingOlder, let oldest = oldestVisibleTimestamp else { return }
    isLoadingOlder = true
    defer { isLoadingOlder = false }

    // 1. Try in-memory first
    let all = allObjects
    let filtered: [WOMObject]
    if let ch = activeChannel {
        filtered = all.filter { obj in
            (obj.type.contains("wom:Message") || obj.type.contains("wom:SystemEvent")) &&
            obj.data["server"] == ch.serverHost &&
            obj.data["channel"] == ch.name &&
            obj.createdAt < oldest
        }
    } else {
        let channelKeys = Set(channels.map { "\($0.serverHost)|\($0.name)" })
        filtered = all.filter { obj in
            guard (obj.type.contains("wom:Message") || obj.type.contains("wom:SystemEvent")),
                  obj.createdAt < oldest else { return false }
            guard let server = obj.data["server"], let channel = obj.data["channel"] else { return false }
            return channelKeys.contains("\(server)|\(channel)")
        }
    }
    
    var older = Array(filtered.sorted { $0.createdAt > $1.createdAt }.prefix(50))
    
    // 2. If in-memory is insufficient, query persistent store
    if older.count < 50, let ch = activeChannel {
        do {
            let allStored = try await store.all()
            let storedFiltered = allStored.filter { obj in
                (obj.type.contains("wom:Message") || obj.type.contains("wom:SystemEvent")) &&
                obj.data["server"] == ch.serverHost &&
                obj.data["channel"] == ch.name &&
                obj.createdAt < oldest
            }.sorted { $0.createdAt > $1.createdAt }
            // Merge, dedup by id, take 50
            var seen = Set(older.map(\.id))
            for obj in storedFiltered where !seen.contains(obj.id) {
                seen.insert(obj.id)
                older.append(obj)
                if older.count >= 50 { break }
            }
        } catch {
            os_log(.error, "loadOlderMessages store query failed: %{public}@", error.localizedDescription)
        }
    }
    
    visibleMessages.append(contentsOf: older)
    oldestVisibleTimestamp = visibleMessages.last?.createdAt
}
```

- [ ] **Step 2: Build and verify**

- [ ] **Step 3: Commit**

```bash
git add Wirc/WircApp/Infrastructure/IRC/IRCChannelManager.swift
git commit -m "fix: query persistent store for older messages when in-memory cap exhausted"
```

### Task H.3: Prevent feed posts from being evicted by IRC messages

**Files:**
- Modify: `Wirc/WircApp/App/AppState.swift:22-29`

**Goal:** The single `womObjects` array mixes IRC messages and feed posts. The 2000-item cap uses `suffix(2000)` which keeps only the most recent. Busy IRC sessions can evict all feed posts. Fix by reserving headroom for feed posts.

- [ ] **Step 1: Add eviction logging and headroom**

Replace the current didSet cap logic:

```swift
var womObjects: [WOMObject] = [] {
    didSet {
        if womObjects.count > 2000 {
            let feedPosts = womObjects.filter { $0.type.contains("wom:Post") }
            let ircMessages = womObjects.filter { !$0.type.contains("wom:Post") }
            // Keep all feed posts + most recent IRC messages up to 2000 total
            let feedCap = min(feedPosts.count, 400)
            let keptFeed = Array(feedPosts.prefix(feedCap))
            let ircCap = 2000 - keptFeed.count
            let keptIRC = Array(ircMessages.suffix(ircCap))
            womObjects = keptFeed + keptIRC
            let totalDropped = oldValue.count - womObjects.count
            if totalDropped > 0 {
                os_log(.debug, "AppState: evicted %d objects (kept %d feed, %d IRC)", totalDropped, keptFeed.count, keptIRC.count)
            }
        }
        invalidateIndexes()
    }
}
```

- [ ] **Step 2: Build and verify**

- [ ] **Step 3: Commit**

```bash
git add Wirc/WircApp/App/AppState.swift
git commit -m "fix: reserve 400-item headroom for feed posts, prevent IRC eviction"
```

### Task H.4: Remove 9 unused WOM type files + dead code

**Files:**
- Delete: `Wirc/WircApp/Core/WOM/WOMAnnotation.swift`, `WOMCanonicalizer.swift`, `WOMCrypto.swift`, `WOMEncrypted.swift`, `WOMIdentity.swift`, `WOMKnowledge.swift`, `WOMLite.swift`, `WOMProof.swift`, `WOMRelation.swift`
- Modify: `Wirc/WircApp/Infrastructure/Feed/FeedToWOMAdapter.swift:35-37` (remove `convertSingle`)
- Modify: `Wirc/WircApp/App/FeedManager.swift:82` (remove unused `onBatch` parameter from public API — or mark deprecated)

**Goal:** Delete all WOM type files that are never instantiated. Remove dead methods. Reduce binary size and cognitive overhead.

- [ ] **Step 1: Delete the 9 WOM type files**

```bash
cd Wirc
git rm WircApp/Core/WOM/WOMAnnotation.swift
git rm WircApp/Core/WOM/WOMCanonicalizer.swift
git rm WircApp/Core/WOM/WOMCrypto.swift
git rm WircApp/Core/WOM/WOMEncrypted.swift
git rm WircApp/Core/WOM/WOMIdentity.swift
git rm WircApp/Core/WOM/WOMKnowledge.swift
git rm WircApp/Core/WOM/WOMLite.swift
git rm WircApp/Core/WOM/WOMProof.swift
git rm WircApp/Core/WOM/WOMRelation.swift
```

Also remove them from the Xcode project file (`project.pbxproj`). Search for each filename in the pbxproj and remove the 4 lines per file (fileRef, buildFile, and group entries).

- [ ] **Step 2: Remove `convertSingle` dead method**

In `Wirc/WircApp/Infrastructure/Feed/FeedToWOMAdapter.swift`, delete lines 35-37:
```swift
func convertSingle(item: FeedItem, subscription: FeedSubscription) -> WOMObject {
    convertItem(item, subscription: subscription, index: 0)
}
```

- [ ] **Step 3: Build and verify**

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: remove 9 unused WOM type files and dead convertSingle method"
```

---

## Workstream I: IRC Reliability (5 tasks)

### Task I.1: Add reachability monitoring to FeedManager

**Files:**
- Modify: `Wirc/WircApp/App/FeedManager.swift:1-20`

**Goal:** No reachability check exists. When the device is offline, all feed fetches fail silently. Add `NWPathMonitor` so the UI can show connectivity status.

- [ ] **Step 1: Add NWPathMonitor to FeedManager**

Add to FeedManager:

```swift
import Network

// In the class body:
private let monitor = NWPathMonitor()
private let monitorQueue = DispatchQueue(label: "wirc.reachability")
var isOnline = true

// In init():
init() {
    // ... existing init ...
    monitor.pathUpdateHandler = { [weak self] path in
        Task { @MainActor in
            self?.isOnline = (path.status == .satisfied)
        }
    }
    monitor.start(queue: monitorQueue)
}
```

- [ ] **Step 2: Skip feed refresh when offline**

In `refreshAllFeedsBatched()`, add at the top:

```swift
guard isOnline else {
    feedError = "No internet connection"
    return []
}
```

- [ ] **Step 3: Show offline status in StreamView status bar**

In `StreamView.swift`, add a condition to show offline status:

```swift
// Show status bar when offline
if !appState.feed.isOnline && appState.feed.timeline.isEmpty {
    statusBar  // will show error state from feedError
}
```

- [ ] **Step 4: Build and verify**

- [ ] **Step 5: Commit**

```bash
git add Wirc/WircApp/App/FeedManager.swift Wirc/WircApp/Features/Stream/StreamView.swift
git commit -m "feat: add reachability monitoring, skip feed refresh when offline"
```

### Task I.2: Increase feed fetch parallelism

**Files:**
- Modify: `Wirc/WircApp/App/FeedManager.swift:80-115`

**Goal:** Feed fetching is purely sequential within each batch. Every feed waits for the previous one to finish (including 30s timeouts). Change to concurrent fetching within each batch for dramatic speedup.

- [ ] **Step 1: Make batch fetches concurrent**

Replace the sequential `for i in batch..<end` loop with `TaskGroup`:

```swift
func refreshAllFeedsBatched(womStore: WOMStore, onBatch: (([WOMObject]) async -> Void)? = nil) async -> [WOMObject] {
    let all = subscriptionStore.getAll()
    let batchSize = 15
    isRefreshing = true
    refreshSummary = nil
    refreshProgress = (0, all.count)

    var allNew: [WOMObject] = []
    var completed = 0
    for batch in stride(from: 0, to: all.count, by: batchSize) {
        let end = min(batch + batchSize, all.count)
        let batchSubs = Array(all[batch..<end])
        
        // Fetch batch concurrently
        let batchResults: [[WOMObject]] = await withTaskGroup(of: [WOMObject].self) { group in
            for sub in batchSubs {
                group.addTask { await self.refreshFeed(sub, womStore: womStore) }
            }
            var results: [[WOMObject]] = []
            for await items in group { results.append(items) }
            return results
        }
        
        let batchItems = batchResults.flatMap { $0 }
        allNew.append(contentsOf: batchItems)
        completed += batchSubs.count
        refreshProgress = (completed, all.count)
        if !batchItems.isEmpty { await onBatch?(batchItems) }
        try? await Task.sleep(for: .milliseconds(100))
    }

    isRefreshing = false
    refreshProgress = (all.count, all.count)
    refreshSummary = "✓ \(all.count) sources · \(allNew.count) new posts"
    Task { @MainActor in
        try? await Task.sleep(for: .seconds(4))
        if refreshSummary == "✓ \(all.count) sources · \(allNew.count) new posts" {
            refreshSummary = nil
        }
    }
    return allNew
}
```

- [ ] **Step 2: Build and verify**

- [ ] **Step 3: Commit**

```bash
git add Wirc/WircApp/App/FeedManager.swift
git commit -m "perf: concurrent feed fetching within batches via TaskGroup"
```

### Task I.3: Parse IRCv3 tags in IRCParser

**Files:**
- Modify: `Wirc/WircApp/Infrastructure/IRC/IRCParser.swift:16-20`

**Goal:** IRCv3 tags (prefixed with `@`) are currently stripped and discarded. Parse them minimally so `msgid` and `time` are available for deduplication and server-time ordering.

- [ ] **Step 1: Parse tags into a dictionary**

Replace the tag-stripping code at the top of `parse(rawLine:)`:

```swift
func parse(rawLine: String) -> IRCEvent {
    var line = rawLine
    var tags: [String: String] = [:]
    if line.hasPrefix("@") {
        if let spaceIdx = line.firstIndex(of: " ") {
            let tagString = String(line[line.index(after: line.startIndex)..<spaceIdx])
            for tag in tagString.split(separator: ";") {
                let parts = tag.split(separator: "=", maxSplits: 1)
                let key = String(parts[0])
                let value = parts.count > 1 ? String(parts[1]) : ""
                tags[key] = value
            }
            line = String(line[line.index(after: spaceIdx)...])
        }
    }
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .rawLine(rawLine) }
    // ... rest of parsing unchanged ...
```

Update the `IRCEvent` enum to carry tags. Add `tags: [String: String]?` as an associated value to relevant cases, or add a simpler approach: store tags on the event wrapper. For now, add a `tags` field to the `IRCMessage` struct:

```swift
// In IRCMessage.swift:
struct IRCMessage {
    let prefix: String?
    let command: String
    let params: [String]
    let trailing: String?
    var tags: [String: String] = [:]  // NEW
}
```

Populate `ircMessage.tags = tags` in the parser when creating `.message` events.

- [ ] **Step 2: Pass tags through to WOMObject data**

In `IRCToWOMAdapter.swift`, when creating message WOM objects, add:

```swift
if let msgid = ircMsg.tags["msgid"] { data["ircMsgId"] = msgid }
if let serverTime = ircMsg.tags["time"] { data["ircServerTime"] = serverTime }
```

- [ ] **Step 3: Build and verify**

- [ ] **Step 4: Commit**

```bash
git add Wirc/WircApp/Infrastructure/IRC/IRCParser.swift Wirc/WircApp/Infrastructure/IRC/IRCMessage.swift Wirc/WircApp/Infrastructure/IRC/IRCToWOMAdapter.swift
git commit -m "feat: parse IRCv3 message tags for msgid and server-time"
```

### Task I.4: Fix system event batching — deliver immediately

**Files:**
- Modify: `Wirc/WircApp/App/IRCManager.swift:280-305`

**Goal:** System events are batched with a 500ms timer, creating temporal gaps where messages appear before the corresponding JOIN. Fix by delivering system events immediately (they're low-volume compared to messages).

- [ ] **Step 1: Remove system event batching**

Replace the batching logic:

```swift
// Convert IRC event to WOM objects
let objects = ircToWOM.convert(event, config: config)
guard !objects.isEmpty else { return }

// Deliver all WOM objects immediately — the debounce in views prevents UI overload
onWOMObjects?(objects)
```

Remove `womBatch`, `womBatchTimer`, and the associated cap/flush logic. These are no longer needed.

- [ ] **Step 2: Build and verify**

- [ ] **Step 3: Commit**

```bash
git add Wirc/WircApp/App/IRCManager.swift
git commit -m "fix: deliver system events immediately instead of batching with 500ms delay"
```

### Task I.5: Fix ServerOrchestrator — add estimated completion

**Files:**
- Modify: `Wirc/WircApp/Infrastructure/IRC/ServerOrchestrator.swift:168-175`

**Goal:** The scan progress string shows counts but no time estimate. Add elapsed time and ETA to `scanProgress`.

- [ ] **Step 1: Track elapsed and estimate remaining**

Add a `private var scanStartTime: Date = .distantPast` property. Set it in `startScan()`. Update `updateProgress()`:

```swift
private func updateProgress() {
    let active = activeClients.count
    let elapsed = Date().timeIntervalSince(scanStartTime)
    if isScanning {
        let fraction = totalServers > 0 ? Double(scannedCount) / Double(totalServers) : 0
        let eta: String
        if scannedCount > 0 && fraction > 0 {
            let total = elapsed / fraction
            let remaining = total - elapsed
            eta = remaining < 60 ? "~\(Int(remaining))s left" : "~\(Int(remaining / 60))m left"
        } else {
            eta = "estimating..."
        }
        scanProgress = "\(scannedCount)/\(totalServers) servers · \(active) active · \(globalChannels.count) channels · \(eta)"
    } else {
        scanProgress = "\(globalChannels.count) channels from \(scannedCount)/\(totalServers) servers in \(Int(elapsed))s"
    }
}
```

- [ ] **Step 2: Build and verify**

- [ ] **Step 3: Commit**

```bash
git add Wirc/WircApp/Infrastructure/IRC/ServerOrchestrator.swift
git commit -m "feat: add elapsed time and ETA to ServerOrchestrator scan progress"
```

---

## Workstream J: Mastodon Completion (2 tasks)

### Task J.1: Persistent Mastodon cursor — avoid re-fetching same posts

**Files:**
- Modify: `Wirc/WircApp/App/AppState.swift:201-216`

**Goal:** `refreshMastodonFeed` always fetches the most recent 40 posts regardless of what was already fetched. Store the last-fetched post ID per account and pass it as `maxId` for proper pagination.

- [ ] **Step 1: Store and use last fetched ID**

In `MastodonServerConfig` (MastodonModels.swift), add:

```swift
var lastFetchedId: String?
```

Update `refreshMastodonFeed`:

```swift
func refreshMastodonFeed(accountId: UUID) {
    guard let client = mastodonClients[accountId] ?? {
        if let acct = mastodonAccounts.first(where: { $0.id == accountId }) {
            let c = MastodonClient(config: acct); mastodonClients[accountId] = c; return c
        }; return nil
    }() else { return }
    feed.feedLoading = true; feed.feedError = nil
    let adapter = MastodonToWOMAdapter(instanceURL: client.config.instanceURL)
    Task { @MainActor in
        do {
            let lastId = mastodonAccounts.first(where: { $0.id == accountId })?.lastFetchedId
            let timeline = try await client.homeTimeline(maxId: lastId, limit: 40)
            for status in timeline {
                let obj = adapter.convert(status: status)
                try? await store.save(obj)
                if !womObjects.contains(where: { $0.id == obj.id }) { womObjects.append(obj) }
            }
            // Store last ID for next refresh
            if let latestStatus = timeline.first,
               let idx = mastodonAccounts.firstIndex(where: { $0.id == accountId }) {
                mastodonAccounts[idx].lastFetchedId = latestStatus.id
                saveMastodonAccounts()
            }
            feed.feedLoading = false
        } catch { feed.feedError = error.localizedDescription; feed.feedLoading = false }
    }
}
```

- [ ] **Step 2: Build and verify**

- [ ] **Step 3: Commit**

```bash
git add Wirc/WircApp/App/AppState.swift Wirc/WircApp/Infrastructure/Mastodon/MastodonModels.swift
git commit -m "fix: persist Mastodon cursor to avoid re-fetching same posts"
```

### Task J.2: Fix Color(hex:) fallback and pencil contrast

**Files:**
- Modify: `Wirc/WircApp/Core/DesignSystem.swift:120-135`

**Goal:** Invalid hex strings produce pure black silently. Also, the `pencil` color contrast ratio (4.8:1) is borderline for small text. Fix both.

- [ ] **Step 1: Log warning on invalid hex, darken pencil**

```swift
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6, let int = UInt64(hex, radix: 16) else {
            os_log(.error, "DesignSystem: invalid hex color '%{public}@', falling back to black", hex)
            self = .black
            return
        }
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
```

For the `pencil` token, use `#615E5A` (was `#78716C`) — a darker shade that passes 4.5:1 on `#F6F3ED`:

```swift
static let pencil = Color(hex: "615E5A")  // was 78716C, improved contrast
```

- [ ] **Step 2: Build and verify**

- [ ] **Step 3: Commit**

```bash
git add Wirc/WircApp/Core/DesignSystem.swift
git commit -m "fix: log invalid hex colors, improve pencil contrast to pass WCAG AA"
```

---

## Workstream K: Remaining UX Polish (2 tasks)

### Task K.1: Wire stubbed buttons (E.4 carryover)

**Files:**
- Modify: `Wirc/WircApp/Features/Messages/IRCChatView.swift:380`
- Modify: `Wirc/WircApp/Features/Workshop/WorkshopView.swift:148`

**Goal:** The "Add Server" button in IRCChatView channel sheet has an empty action. The "Import WOM Bundle" button in Workshop is a stub. Wire both.

- [ ] **Step 1: Wire Add Server button**

In `IRCChatView.swift`, find the button with comment `/* AddServerView sheet */` (around line 380). Replace with:

```swift
Button {
    showSheet = true
    sheetHeight = .large
} label: {
    Label("Add Server", systemImage: "plus")
}
```

The existing `channelSheet` already contains `IRCServerManagerSheet` which provides add/remove functionality.

- [ ] **Step 2: Wire Import WOM file picker**

In `WorkshopView.swift`, find the button with comment `/* file picker stub */` (around line 148). Add `@State private var showImporter = false` and replace the button with:

```swift
Button {
    showImporter = true
} label: {
    Label("Import WOM Bundle", systemImage: "doc.badge.plus")
}
.fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
    if case .success(let url) = result {
        Task {
            guard let data = try? Data(contentsOf: url),
                  let objects = try? JSONDecoder().decode([WOMObject].self, from: data) else { return }
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
git commit -m "fix: wire Add Server button and Import WOM file picker"
```

### Task K.2: Replace timeline header debug telemetry with production-safe alternative

**Files:**
- Modify: `Wirc/WircApp/Features/Messages/IRCChatView.swift:118-121`

**Goal:** The IRC header bar shows raw debug counters (`Σ123 p45 v200 MSG`) in 8pt signal-orange text visible to all users. Gate it behind `#if DEBUG`.

- [ ] **Step 1: Wrap in #if DEBUG**

```swift
#if DEBUG
Text("Σ\(appState.irc.totalEventsReceived) p\(appState.irc.privmsgCount) v\(manager.visibleMessages.count) \(appState.irc.lastEventType)")
    .font(.system(size: 8))
    .foregroundStyle(DesignSystem.Colors.signal)
    .lineLimit(1)
#endif
```

Note: This was already attempted in Task G.3 but may not have been committed as part of that batch. Verify and apply if needed.

- [ ] **Step 2: Build and verify**

- [ ] **Step 3: Commit**

```bash
git add Wirc/WircApp/Features/Messages/IRCChatView.swift
git commit -m "fix: gate IRC debug telemetry behind #if DEBUG"
```

---

## Workstream L: Remaining Loose Ends (2 tasks)

### Task L.1: Remove dead `onBatch` parameter from FeedManager API

**Files:**
- Modify: `Wirc/WircApp/App/FeedManager.swift:81`

**Goal:** The `onBatch` parameter is never passed a non-nil value by any caller. Remove it from the public API. This is a cosmetic cleanup but removes confusion.

- [ ] **Step 1: Remove onBatch parameter**

```swift
// Before:
func refreshAllFeedsBatched(womStore: WOMStore, onBatch: (([WOMObject]) async -> Void)? = nil) async -> [WOMObject]

// After:
func refreshAllFeedsBatched(womStore: WOMStore) async -> [WOMObject]
```

Remove the `onBatch?()` call line inside the function body. All callers already pass `nil` or omit it — they don't need changes.

- [ ] **Step 2: Build and verify**

- [ ] **Step 3: Commit**

```bash
git add Wirc/WircApp/App/FeedManager.swift
git commit -m "refactor: remove unused onBatch callback parameter"
```

### Task L.2: Add Mastodon streaming API support stub + share sheet fix

**Files:**
- Modify: `Wirc/WircApp/Infrastructure/Feed/FeedCard.swift:79-83`
- Create: `Wirc/WircApp/Infrastructure/Mastodon/MastodonStreamer.swift`

**Goal:** Fix the share sheet presentation issue (can fail when another sheet is active) and add a streaming client stub for future use.

- [ ] **Step 1: Fix share sheet with host resolution**

Replace the `UIApplication.shared.connectedScenes.first?.windows.first?.rootViewController` chain with a more robust approach:

```swift
// In FeedCard, replace the share button's view controller lookup:
Button {
    let avc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    // Use the window scene's key window for reliable presentation
    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
       let window = windowScene.windows.first(where: { $0.isKeyWindow }),
       let root = window.rootViewController {
        // Find the topmost presented VC
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(avc, animated: true)
    }
} label: { ... }
```

- [ ] **Step 2: Add MastodonStreamer stub**

Create `Wirc/WircApp/Infrastructure/Mastodon/MastodonStreamer.swift`:

```swift
import Foundation

/// Streaming client for Mastodon timeline updates via WebSocket.
/// Currently a stub — REST polling is used until this is implemented.
final class MastodonStreamer {
    private var task: URLSessionWebSocketTask?
    
    func connect(instanceURL: String, token: String) {
        // TODO: Implement WebSocket connection to /api/v1/streaming
    }
    
    func disconnect() {
        task?.cancel()
        task = nil
    }
}
```

Add to Xcode project.

- [ ] **Step 3: Build and verify**

- [ ] **Step 4: Commit**

```bash
git add Wirc/WircApp/Infrastructure/Feed/FeedCard.swift Wirc/WircApp/Infrastructure/Mastodon/MastodonStreamer.swift Wirc/Wirc.xcodeproj/project.pbxproj
git commit -m "fix: robust share sheet presentation, add Mastodon streaming stub"
```

---

## Execution Order

Workstreams are independent — execute in any order. Within each stream, tasks are sequential.

### Recommended Order (by impact):
1. **H.1** (lost items without title — data loss fix)
2. **H.4** (dead WOM files — cleanup that reduces build time)
3. **K.1** (stubbed buttons — user-facing broken UI)
4. **I.2** (concurrent feed fetch — dramatic speed improvement)
5. **I.1** (reachability — prevents silent failures)
6. **I.4** (immediate system events — fixes temporal gaps)
7. **J.1** (Mastodon cursor — prevents re-fetching)
8. **H.3** (IRC feed eviction — prevents data loss)
9. **I.5** (scan ETA — UX polish)
10. **I.3** (IRCv3 tags — future-proofing)
11. **H.2** (store pagination for old messages)
12. **J.2** (color contrast fix)
13. **K.2** (debug telemetry gate)
14. **L.1** (dead onBatch parameter)
15. **L.2** (share sheet + streaming stub)

### Estimated Effort:
- Stream H: 4 tasks, ~2 hours
- Stream I: 5 tasks, ~2 hours
- Stream J: 2 tasks, ~1 hour
- Stream K: 2 tasks, ~30 min
- Stream L: 2 tasks, ~30 min
- **Total: 15 tasks, ~6 hours**
