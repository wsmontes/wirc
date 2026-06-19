# Wirc Foundation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace in-memory/JSON-file WOM storage with GRDB/SQLite persistence, implement offline-first feed cache with incremental refresh, and extract services from the AppState monolith.

**Architecture:** Add GRDB as SPM dependency. Implement `GRDBWOMStore` replacing `JSONFileStore`, with WAL mode and indexed queries. Persist `FeedSubscription` to SQLite with ETag/Last-Modified for incremental fetch. Extract `WOMRepository`, `FeedService`, `IRCService`, `MastodonService` from `AppState.swift`. Zero provider changes, zero UI changes.

**Tech Stack:** Swift 6, SwiftUI, GRDB 7.x (SQLite), XcodeGen (project.yml)

## Global Constraints

- Zero UI changes — FeedView, StreamView, Messages tabs unchanged
- Zero provider changes — IRCClient, FeedParser, MastodonClient unchanged
- WOMStore protocol extended, not broken — existing callers compile without changes
- `@unchecked Sendable` for GRDB wrapper (SQLite is thread-safe via DatabaseQueue)
- Build must succeed for iOS 17.0+
- No regressions in existing functionality (IRC, RSS, Mastodon)

---

### Task 1: Add GRDB dependency and create GRDBWOMStore

**Files:**
- Create: `Wirc/WircApp/Infrastructure/Persistence/GRDBWOMStore.swift`
- Modify: `Wirc/project.yml` (add SPM package)
- Create: `Wirc/WircApp/Infrastructure/Persistence/GRDBWOMStoreTests.swift` (test helper)

**Interfaces:**
- Consumes: `WOMStore` protocol (existing), `WOMObject` (existing)
- Produces: `GRDBWOMStore` class conforming to `WOMStore`

- [ ] **Step 1: Add GRDB to XcodeGen project.yml**

Add to `Wirc/project.yml` under a top-level `packages:` key, then reference in the Wirc target:

```yaml
packages:
  GRDB:
    url: https://github.com/groue/GRDB.swift
    majorVersion: 7.0.0

targets:
  Wirc:
    type: application
    platform: iOS
    sources:
      - path: WircApp
    dependencies:
      - package: GRDB
    # ... rest unchanged
```

Run `xcodegen generate --spec project.yml` from the `Wirc/` directory to regenerate the `.xcodeproj`.

- [ ] **Step 2: Create GRDBWOMStore**

Create `Wirc/WircApp/Infrastructure/Persistence/GRDBWOMStore.swift`:

```swift
import Foundation
import GRDB

final class GRDBWOMStore: WOMStore, @unchecked Sendable {
    private let db: DatabaseQueue

    init(path: String) throws {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode=WAL")
        }
        db = try DatabaseQueue(path: path, configuration: config)
        try migrator.migrate(db)
    }

    // MARK: - Schema

    private static let migrator: DatabaseMigrator = {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "wom_object") { t in
                t.column("id", .text).primaryKey()
                t.column("type", .text).notNull()
                t.column("createdAt", .double).notNull().indexed()
                t.column("schema", .text)
                t.column("attributedTo", .text)  // JSON
                t.column("content", .text)        // JSON
                t.column("data", .text)           // JSON
                t.column("provenance", .text)     // JSON
                t.column("governance", .text)     // JSON
                t.column("classification", .text) // JSON
                t.column("bindings", .text)       // JSON
                t.column("location", .text)       // JSON
                t.column("temporal", .text)       // JSON
                t.column("canonicalUrl", .text).indexed()
                t.column("raw", .blob).notNull()  // Full JSON backup
            }
            // Index on temporal.expiresAt for prune queries
            try db.execute(sql: """
                CREATE INDEX idx_wom_type ON wom_object(type)
            """)
            try db.create(table: "feed_subscription") { t in
                t.column("id", .text).primaryKey()
                t.column("feedURL", .text).notNull()
                t.column("title", .text)
                t.column("sourceType", .text).notNull()
                t.column("tags", .text)           // JSON array
                t.column("etag", .text)
                t.column("lastModified", .text)
                t.column("lastFetchedAt", .double)
                t.column("errorCount", .integer).defaults(to: 0)
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
            }
            try db.create(table: "feed_item") { t in
                t.column("womId", .text).primaryKey().references("wom_object", onDelete: .cascade)
                t.column("subscriptionId", .text).notNull().references("feed_subscription", onDelete: .cascade)
                t.column("canonicalUrl", .text).notNull().indexed()
                t.column("fetchedAt", .double).notNull()
            }
        }
        return m
    }()

    // MARK: - JSON encoding helpers

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private func encode<T: Encodable>(_ value: T?) -> String? {
        guard let value else { return nil }
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }

    private func rawJSON(_ object: WOMObject) -> Data {
        (try? encoder.encode(object)) ?? Data()
    }

    private func decodeObject(from row: Row) -> WOMObject? {
        guard let raw = row["raw"] as Data? ?? nil else { return nil }
        // Prefer raw column (single decode, preserves all fields)
        if let raw = row["raw"] as Data?, let obj = try? decoder.decode(WOMObject.self, from: raw) {
            return obj
        }
        return nil
    }

    // MARK: - WOMStore implementation

    func save(_ object: WOMObject) async throws {
        try await db.write { db in
            try self.insert(db, object)
        }
    }

    func saveMany(_ objects: [WOMObject]) async throws {
        try await db.write { db in
            for obj in objects {
                try self.insert(db, obj)
            }
        }
    }

    func get(id: String) async throws -> WOMObject? {
        try await db.read { db in
            try Row.fetchOne(db, sql: "SELECT raw FROM wom_object WHERE id = ?", arguments: [id])
                .flatMap { try? decoder.decode(WOMObject.self, from: $0["raw"]) }
        }
    }

    func list(type: String?) async throws -> [WOMObject] {
        try await db.read { db in
            let sql: String
            let args: StatementArguments
            if let type {
                sql = "SELECT raw FROM wom_object WHERE type LIKE ? ORDER BY createdAt DESC"
                args = ["%\(type)%"]
            } else {
                sql = "SELECT raw FROM wom_object ORDER BY createdAt DESC"
                args = []
            }
            return try Row.fetchAll(db, sql: sql, arguments: args).compactMap {
                try? decoder.decode(WOMObject.self, from: $0["raw"])
            }
        }
    }

    func delete(id: String) async throws {
        try await db.write { db in
            try db.execute(sql: "DELETE FROM wom_object WHERE id = ?", arguments: [id])
        }
    }

    func all() async throws -> [WOMObject] {
        try await db.read { db in
            try Row.fetchAll(db, sql: "SELECT raw FROM wom_object ORDER BY createdAt DESC").compactMap {
                try? decoder.decode(WOMObject.self, from: $0["raw"])
            }
        }
    }

    func saveIfNew(_ object: WOMObject, byCanonicalURL canonicalURL: String) async throws -> Bool {
        try await db.write { db in
            let exists = try Row.fetchOne(db, sql: "SELECT 1 FROM wom_object WHERE canonicalUrl = ?", arguments: [canonicalURL]) != nil
            if exists { return false }
            try self.insert(db, object)
            return true
        }
    }

    // MARK: - Extended queries (new)

    func list(type: String?, since: Date?, limit: Int?) async throws -> [WOMObject] {
        try await db.read { db in
            var sql = "SELECT raw FROM wom_object WHERE 1=1"
            var args: [DatabaseValueConvertible] = []
            if let type {
                sql += " AND type LIKE ?"
                args.append("%\(type)%")
            }
            if let since {
                sql += " AND createdAt >= ?"
                args.append(since.timeIntervalSince1970)
            }
            sql += " ORDER BY createdAt DESC"
            if let limit {
                sql += " LIMIT ?"
                args.append(limit)
            }
            return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args)).compactMap {
                try? decoder.decode(WOMObject.self, from: $0["raw"])
            }
        }
    }

    func count(type: String?) async throws -> Int {
        try await db.read { db in
            if let type {
                return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM wom_object WHERE type LIKE ?", arguments: ["%\(type)%"]) ?? 0
            }
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM wom_object") ?? 0
        }
    }

    func pruneExpired() async throws -> Int {
        try await db.write { db in
            let sql = """
                DELETE FROM wom_object WHERE id IN (
                    SELECT id FROM wom_object
                    WHERE json_extract(temporal, '$.expiresAt') IS NOT NULL
                    AND json_extract(temporal, '$.expiresAt') < ?
                )
            """
            try db.execute(sql: sql, arguments: [Date().timeIntervalSince1970])
            return db.changesCount
        }
    }

    func deleteByCanonicalURL(_ url: String) async throws {
        try await db.write { db in
            try db.execute(sql: "DELETE FROM wom_object WHERE canonicalUrl = ?", arguments: [url])
        }
    }

    // MARK: - Migration

    /// Migrates all objects from a JSONFileStore into this GRDB store.
    /// Called once on first launch after upgrade.
    func migrateFrom(_ jsonStore: JSONFileStore) async throws {
        let objects = try await jsonStore.all()
        try await db.write { db in
            for obj in objects {
                try self.insert(db, obj)
            }
        }
    }

    // MARK: - Private

    private func insert(_ db: Database, _ object: WOMObject) throws {
        let json = rawJSON(object)
        try db.execute(sql: """
            INSERT OR REPLACE INTO wom_object
            (id, type, createdAt, schema, attributedTo, content, data, provenance,
             governance, classification, bindings, location, temporal, canonicalUrl, raw)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
            object.id,
            object.type.joined(separator: ","),
            object.createdAt.timeIntervalSince1970,
            object.schema,
            encode(object.attributedTo),
            encode(object.content),
            encode(object.data),
            encode(object.provenance),
            encode(object.governance),
            encode(object.classification),
            encode(object.bindings),
            nil, // location — populated from WOM fields when available
            nil, // temporal — populated from WOM fields when available
            object.data["canonicalUrl"],
            json
        ])
    }
}
```

- [ ] **Step 3: Verify build compiles**

Run from `Wirc/` directory:
```
xcodegen generate --spec project.yml
xcodebuild -project Wirc.xcodeproj -scheme Wirc -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add Wirc/project.yml Wirc/WircApp/Infrastructure/Persistence/GRDBWOMStore.swift
git commit -m "feat: add GRDB dependency and GRDBWOMStore with SQLite persistence

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Extend WOMStore protocol + add migration from JSONFileStore

**Files:**
- Modify: `Wirc/WircApp/Infrastructure/Persistence/WOMStore.swift` (add protocol methods)
- Modify: `Wirc/WircApp/Infrastructure/Persistence/InMemoryWOMStore.swift` (implement new methods)
- Modify: `Wirc/WircApp/App/AppState.swift` (wire migration)

**Interfaces:**
- Consumes: `GRDBWOMStore` (Task 1), `JSONFileStore` (existing)
- Produces: Extended `WOMStore` protocol with `list(type:since:limit:)`, `count(type:)`, `pruneExpired()`, `deleteByCanonicalURL(_:)`

- [ ] **Step 1: Extend WOMStore protocol**

Add to the existing `WOMStore` protocol in `Wirc/WircApp/Infrastructure/Persistence/WOMStore.swift`, after `saveIfNew`:

```swift
    /// List objects of the given type (e.g., "wom:Post"), optionally filtered
    /// by date and capped at a limit. Ordered by createdAt DESC.
    func list(type: String?, since: Date?, limit: Int?) async throws -> [WOMObject]

    /// Count of objects, optionally filtered by type.
    func count(type: String?) async throws -> Int

    /// Delete all objects whose temporal.expiresAt has passed.
    /// Returns the number of deleted objects.
    func pruneExpired() async throws -> Int

    /// Delete all objects matching a canonical URL (for re-fetch dedup).
    func deleteByCanonicalURL(_ url: String) async throws
```

- [ ] **Step 2: Implement new methods in InMemoryWOMStore**

Add to `InMemoryWOMStore`:

```swift
    func list(type: String?, since: Date?, limit: Int?) async throws -> [WOMObject] {
        var result = Array(storage.values)
        if let type { result = result.filter { $0.type.contains(type) } }
        if let since { result = result.filter { $0.createdAt >= since } }
        result.sort { $0.createdAt > $1.createdAt }
        if let limit { result = Array(result.prefix(limit)) }
        return result
    }

    func count(type: String?) async throws -> Int {
        guard let type else { return storage.count }
        return storage.values.filter { $0.type.contains(type) }.count
    }

    func pruneExpired() async throws -> Int {
        let before = storage.count
        storage = storage.filter { _, obj in
            // No temporal field = never expires
            true
        }
        return before - storage.count
    }

    func deleteByCanonicalURL(_ url: String) async throws {
        storage = storage.filter { $0.value.data["canonicalUrl"] != url }
    }
```

- [ ] **Step 3: Update AppState to use GRDBWOMStore and run migration**

In `Wirc/WircApp/App/AppState.swift`, change the `store` initialization:

```swift
// Before:
let store: WOMStore = JSONFileStore()

// After:
let store: WOMStore = {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let dbPath = docs.appendingPathComponent("wirc/wom.db").path
    let grdb = try! GRDBWOMStore(path: dbPath)

    // One-time migration from JSONFileStore
    if !UserDefaults.standard.bool(forKey: "wirc.migration.grdb_v1") {
        let jsonStore = JSONFileStore()
        Task {
            try? await grdb.migrateFrom(jsonStore)
            UserDefaults.standard.set(true, forKey: "wirc.migration.grdb_v1")
        }
    }
    return grdb
}()
```

- [ ] **Step 4: Verify build compiles**

```
cd Wirc && xcodegen generate --spec project.yml && xcodebuild -project Wirc.xcodeproj -scheme Wirc -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -3
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add Wirc/WircApp/Infrastructure/Persistence/WOMStore.swift \
        Wirc/WircApp/Infrastructure/Persistence/InMemoryWOMStore.swift \
        Wirc/WircApp/App/AppState.swift
git commit -m "feat: extend WOMStore protocol with list/count/prune/deleteByCanonicalURL, migrate to GRDB

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Persist FeedSubscription to GRDB

**Files:**
- Modify: `Wirc/WircApp/Infrastructure/Feed/FeedSubscriptionStore.swift`
- Modify: `Wirc/WircApp/App/AppState.swift` (update feed refresh to use GRDB)

**Interfaces:**
- Consumes: `GRDBWOMStore` (Task 1), `FeedSubscription` (existing)
- Produces: `FeedSubscriptionStore` backed by GRDB instead of JSON file

- [ ] **Step 1: Rewrite FeedSubscriptionStore with GRDB backend**

Replace `Wirc/WircApp/Infrastructure/Feed/FeedSubscriptionStore.swift`:

```swift
import Foundation
import GRDB

final class FeedSubscriptionStore {
    private let db: DatabaseQueue

    init(db: DatabaseQueue) {
        self.db = db
    }

    func add(_ sub: FeedSubscription) {
        do {
            try db.write { db in try self.insert(db, sub) }
        } catch {
            AppLog.error("feed", "FeedSubscriptionStore.add failed: \(error)")
        }
    }

    func addMany(_ subs: [FeedSubscription]) {
        do {
            try db.write { db in
                for sub in subs { try self.insert(db, sub) }
            }
        } catch {
            AppLog.error("feed", "FeedSubscriptionStore.addMany failed: \(error)")
        }
    }

    func remove(id: UUID) {
        do {
            try db.write { db in
                try db.execute(sql: "DELETE FROM feed_subscription WHERE id = ?", arguments: [id.uuidString])
            }
        } catch {
            AppLog.error("feed", "FeedSubscriptionStore.remove failed: \(error)")
        }
    }

    func update(_ sub: FeedSubscription) {
        do {
            try db.write { db in
                try db.execute(sql: """
                    UPDATE feed_subscription SET
                        title = ?, etag = ?, lastModified = ?, lastFetchedAt = ?,
                        errorCount = ?, updatedAt = ?
                    WHERE id = ?
                """, arguments: [
                    sub.title, sub.etag, sub.lastModified,
                    sub.lastFetchedAt?.timeIntervalSince1970,
                    sub.errorCount, Date().timeIntervalSince1970,
                    sub.id.uuidString
                ])
            }
        } catch {
            AppLog.error("feed", "FeedSubscriptionStore.update failed: \(error)")
        }
    }

    func get(id: UUID) -> FeedSubscription? {
        try? db.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM feed_subscription WHERE id = ?", arguments: [id.uuidString])
                .flatMap { self.decode($0) }
        }
    }

    func getAll() -> [FeedSubscription] {
        (try? db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM feed_subscription ORDER BY updatedAt DESC")
                .compactMap { self.decode($0) }
        }) ?? []
    }

    // MARK: - Private

    private func insert(_ db: Database, _ sub: FeedSubscription) throws {
        try db.execute(sql: """
            INSERT OR REPLACE INTO feed_subscription
            (id, feedURL, title, sourceType, tags, etag, lastModified,
             lastFetchedAt, errorCount, createdAt, updatedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
            sub.id.uuidString, sub.feedURL, sub.title, sub.sourceType.rawValue,
            (try? JSONEncoder().encode(sub.tags)).flatMap { String(data: $0, encoding: .utf8) },
            sub.etag, sub.lastModified,
            sub.lastFetchedAt?.timeIntervalSince1970,
            sub.errorCount,
            Date().timeIntervalSince1970, // createdAt — only set on insert
            Date().timeIntervalSince1970  // updatedAt
        ])
    }

    private func decode(_ row: Row) -> FeedSubscription? {
        guard let idStr: String = row["id"],
              let id = UUID(uuidString: idStr),
              let feedURL: String = row["feedURL"],
              let sourceTypeRaw: String = row["sourceType"],
              let sourceType = FeedSourceType(rawValue: sourceTypeRaw) else { return nil }

        let tags: [String] = {
            guard let json: String = row["tags"],
                  let data = json.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return arr
        }()

        return FeedSubscription(
            id: id,
            feedURL: feedURL,
            title: row["title"] ?? "",
            sourceType: sourceType,
            tags: tags,
            lastFetchedAt: (row["lastFetchedAt"] as Double?).map { Date(timeIntervalSince1970: $0) },
            etag: row["etag"],
            lastModified: row["lastModified"],
            errorCount: row["errorCount"] ?? 0
        )
    }
}
```

- [ ] **Step 2: Update AppState.init to pass db to FeedSubscriptionStore**

In `AppState.swift`, update `feedStore` initialization:

```swift
// Before:
let feedStore = FeedSubscriptionStore()

// After:
let store: WOMStore = { ... }() // From Task 2 — now a let
let feedStore: FeedSubscriptionStore

init() {
    // Extract the db from the GRDB store to share with FeedSubscriptionStore
    if let grdb = store as? GRDBWOMStore {
        feedStore = FeedSubscriptionStore(db: grdb.db) // Expose db as internal
    } else {
        // Fallback for non-GRDB stores (tests, previews)
        feedStore = FeedSubscriptionStore(db: try! DatabaseQueue())
    }
    // ... rest
}
```

Note: `GRDBWOMStore` needs to expose its `db` property as `internal`:
```swift
final class GRDBWOMStore: WOMStore, @unchecked Sendable {
    let db: DatabaseQueue  // Changed from private to internal
    // ...
}
```

- [ ] **Step 3: Update feed refresh to persist WOMs**

In `AppState.refreshFeed()`, the `FeedToWOMAdapter.convert()` already calls `store.saveIfNew()` — no changes needed to the adapter. The store now persists to SQLite.

- [ ] **Step 4: Verify build compiles**

```
cd Wirc && xcodegen generate --spec project.yml && xcodebuild -project Wirc.xcodeproj -scheme Wirc -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -3
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add Wirc/WircApp/Infrastructure/Feed/FeedSubscriptionStore.swift \
        Wirc/WircApp/App/AppState.swift \
        Wirc/WircApp/Infrastructure/Persistence/GRDBWOMStore.swift
git commit -m "feat: persist FeedSubscription to GRDB, share db with feed store

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: Implement offline-first feed cache

**Files:**
- Modify: `Wirc/WircApp/App/AppState.swift` (update init and refresh logic)

**Interfaces:**
- Consumes: `GRDBWOMStore` (Task 1), `FeedSubscriptionStore` (Task 3)
- Produces: Offline-first feed loading with cache and background refresh

- [ ] **Step 1: Add offline-first feed loading to AppState.init**

Update `AppState.init()` to load cached WOMs immediately:

```swift
init() {
    // ... existing setup ...

    // Offline-first: load cached WOMs immediately
    Task { @MainActor in
        do {
            let cached = try await store.list(type: "wom:Post", since: nil, limit: 500)
            self.womObjects = cached
        } catch {
            AppLog.error("app", "Failed to load cached feed: \(error)")
        }
    }

    // Background: refresh subscriptions
    let subs = feedStore.getAll()
    if !subs.isEmpty {
        Task { @MainActor [weak self] in
            await self?.refreshAllFeedsBatched()
        }
    } else {
        // First launch: load defaults
        let loaded = DefaultFeedsLoader.loadIfEmpty(into: feedStore)
        if loaded > 0 {
            Task { @MainActor [weak self] in
                await self?.refreshAllFeedsBatched()
            }
        }
    }

    // Schedule periodic cleanup
    Task { @MainActor [weak self] in
        let pruned = (try? await self?.store.pruneExpired()) ?? 0
        if pruned > 0 { AppLog.info("app", "Pruned \(pruned) expired WOMs") }
    }
}
```

- [ ] **Step 2: Add incremental refresh via ETag/Last-Modified**

In `refreshFeed()`, the existing `FeedFetcher.fetch()` already returns `(Data, URLResponse)`. The response headers contain ETag and Last-Modified. The subscription already stores them. No code changes needed — the existing feed refresh logic already uses incremental fetch.

- [ ] **Step 3: Verify offline behavior**

Test procedure:
1. Launch app → feed loads from RSS
2. Kill app
3. Turn on Airplane Mode
4. Launch app → feed shows cached items with titles
5. Turn off Airplane Mode
6. Pull to refresh → incremental updates

- [ ] **Step 4: Commit**

```bash
git add Wirc/WircApp/App/AppState.swift
git commit -m "feat: offline-first feed cache — load cached WOMs on launch, background refresh

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: Extract WOMRepository wrapper

**Files:**
- Create: `Wirc/WircApp/Infrastructure/Persistence/WOMRepository.swift`
- Modify: `Wirc/WircApp/App/AppState.swift` (use repository instead of raw store)

**Interfaces:**
- Consumes: `WOMStore` protocol (existing, extended in Task 2)
- Produces: `WOMRepository` actor with feed-specific queries

- [ ] **Step 1: Create WOMRepository**

Create `Wirc/WircApp/Infrastructure/Persistence/WOMRepository.swift`:

```swift
import Foundation

/// High-level data access layer for WOM objects.
/// Wraps WOMStore with feed-specific queries and batch operations.
struct WOMRepository: Sendable {
    private let store: any WOMStore

    init(store: any WOMStore) {
        self.store = store
    }

    // MARK: - Feed

    func fetchFeed(limit: Int = 200, since: Date? = nil) async throws -> [WOMObject] {
        try await store.list(type: "wom:Post", since: since, limit: limit)
    }

    func recentMessages(server: String, channel: String, limit: Int = 100) async throws -> [WOMObject] {
        try await store.list(type: "wom:Message", since: nil, limit: limit)
    }

    // MARK: - Write

    func save(_ object: WOMObject) async throws {
        try await store.save(object)
    }

    func saveMany(_ objects: [WOMObject]) async throws {
        try await store.saveMany(objects)
    }

    /// Atomically save if no object with the same canonical URL exists.
    /// Returns true if saved, false if duplicate skipped.
    func saveIfNew(_ object: WOMObject, canonicalURL: String) async throws -> Bool {
        try await store.saveIfNew(object, byCanonicalURL: canonicalURL)
    }

    // MARK: - Maintenance

    func pruneExpired() async throws -> Int {
        try await store.pruneExpired()
    }

    func deleteByCanonicalURL(_ url: String) async throws {
        try await store.deleteByCanonicalURL(url)
    }

    func count(type: String?) async throws -> Int {
        try await store.count(type: type)
    }
}
```

- [ ] **Step 2: Update AppState to use WOMRepository**

In `AppState.swift`:

```swift
// Before:
let store: WOMStore = { ... }()

// After:
let store: any WOMStore = { ... }()
let womRepo: WOMRepository

init() {
    // ...
    self.womRepo = WOMRepository(store: store)
    // ...
}
```

Replace all `store.save(...)` with `womRepo.save(...)` and `store.list(...)` with `womRepo.fetchFeed(...)`.

- [ ] **Step 3: Verify build compiles + commit**

```bash
xcodegen generate --spec Wirc/project.yml && xcodebuild -project Wirc/Wirc.xcodeproj -scheme Wirc -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -3
```
Expected: `BUILD SUCCEEDED`

```bash
git add Wirc/WircApp/Infrastructure/Persistence/WOMRepository.swift Wirc/WircApp/App/AppState.swift
git commit -m "feat: extract WOMRepository — high-level data access layer wrapping WOMStore

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: Extract FeedService from AppState

**Files:**
- Create: `Wirc/WircApp/Infrastructure/Feed/FeedService.swift`
- Modify: `Wirc/WircApp/App/AppState.swift` (delegate to FeedService)

**Interfaces:**
- Consumes: `WOMRepository` (Task 5), `FeedSubscriptionStore` (Task 3), `FeedFetcher` (existing), `FeedToWOMAdapter` (existing)
- Produces: `FeedService` actor with add/remove/refresh/import methods

- [ ] **Step 1: Create FeedService**

Create `Wirc/WircApp/Infrastructure/Feed/FeedService.swift`:

```swift
import Foundation

final class FeedService: Sendable {
    private let repo: WOMRepository
    private let subscriptionStore: FeedSubscriptionStore
    private let fetcher = FeedFetcher()
    private let adapter = FeedToWOMAdapter()
    private let maxConsecutiveErrors = 5

    init(repo: WOMRepository, subscriptionStore: FeedSubscriptionStore) {
        self.repo = repo
        self.subscriptionStore = subscriptionStore
    }

    // MARK: - Subscriptions

    func loadSubscriptions() -> [FeedSubscription] {
        subscriptionStore.getAll()
    }

    func addFeed(url: String) async throws -> FeedSubscription {
        guard let feedURL = URL(string: url) else { throw FeedError.invalidURL(url) }

        let finalURL: String
        let detectedType: FeedSourceType

        if url.hasSuffix(".xml") || url.hasSuffix(".rss") || url.contains("/feed") {
            finalURL = url
            detectedType = .rss
        } else {
            let discovered = try await fetcher.discoverFeed(from: feedURL)
            guard let first = discovered.first else { throw FeedError.invalidURL("No feed found at \(url)") }
            finalURL = first.absoluteString
            detectedType = detectSourceType(from: finalURL)
        }

        var sub = FeedSubscription(feedURL: finalURL, sourceType: detectedType)
        do {
            let (data, _) = try await fetcher.fetch(subscription: sub)
            let result = try await Task.detached(priority: .utility) {
                try FeedParser.parse(data: data, sourceURL: finalURL)
            }.value
            sub.title = result.title ?? finalURL
        } catch {
            sub.title = finalURL
        }

        subscriptionStore.add(sub)
        Task { await refreshFeed(sub) }
        return sub
    }

    func removeFeed(id: UUID) {
        subscriptionStore.remove(id: id)
    }

    // MARK: - Refresh

    func refreshFeed(_ subscription: FeedSubscription) async -> [WOMObject] {
        if subscription.errorCount >= maxConsecutiveErrors { return [] }

        do {
            let (data, response) = try await fetcher.fetch(subscription: subscription)
            if let http = response as? HTTPURLResponse, http.statusCode == 304 {
                var sub = subscription
                sub.lastFetchedAt = Date()
                sub.errorCount = 0
                subscriptionStore.update(sub)
                return []
            }

            let sourceURL = subscription.feedURL
            let result = try await Task.detached(priority: .utility) {
                try FeedParser.parse(data: data, sourceURL: sourceURL)
            }.value

            var sub = subscription
            if let t = result.title { sub.title = t }
            sub.lastFetchedAt = Date()
            sub.errorCount = 0
            if let http = response as? HTTPURLResponse {
                sub.etag = http.allHeaderFields["ETag"] as? String ?? http.allHeaderFields["Etag"] as? String
                sub.lastModified = http.allHeaderFields["Last-Modified"] as? String
            }
            subscriptionStore.update(sub)

            let objects = await adapter.convert(items: result.items, subscription: sub, store: repo)
            return objects
        } catch {
            var sub = subscription
            sub.errorCount += 1
            sub.lastFetchedAt = Date()
            subscriptionStore.update(sub)
            return []
        }
    }

    func refreshAllFeeds() async -> [WOMObject] {
        var all: [WOMObject] = []
        for sub in subscriptionStore.getAll() {
            let objs = await refreshFeed(sub)
            all.append(contentsOf: objs)
        }
        return all
    }

    func refreshAllFeedsBatched() async -> [WOMObject] {
        let all = subscriptionStore.getAll()
        var results: [WOMObject] = []
        let batchSize = 5
        for batch in stride(from: 0, to: all.count, by: batchSize) {
            let end = min(batch + batchSize, all.count)
            for i in batch..<end {
                results.append(contentsOf: await refreshFeed(all[i]))
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return results
    }

    func importOPML(data: Data) async throws -> Int {
        let outlines = try fetcher.parseOPML(data)
        var count = 0
        for outline in outlines {
            let sub = FeedSubscription(
                feedURL: outline.xmlURL,
                title: outline.title ?? outline.xmlURL,
                sourceType: detectSourceType(from: outline.xmlURL),
                tags: outline.folderName.map { [$0] } ?? []
            )
            subscriptionStore.add(sub)
            count += 1
        }
        return count
    }

    private func detectSourceType(from url: String) -> FeedSourceType {
        if url.contains("youtube.com") { return .youtube }
        if url.contains("github.com") { return .github }
        if url.contains("/podcast") || url.contains("itunes") { return .podcast }
        return .rss
    }
}
```

- [ ] **Step 2: Update AppState to delegate to FeedService**

In `AppState.swift`:

```swift
// Before:
let feedStore = FeedSubscriptionStore(...)
// ... long feed methods ...

// After:
let feedService: FeedService

init() {
    // ...
    self.feedService = FeedService(repo: womRepo, subscriptionStore: feedStore)
    // ...
}

func addFeed(url: String) async throws {
    let sub = try await feedService.addFeed(url: url)
    // Refresh UI
    let fresh = await feedService.refreshAllFeeds()
    womObjects.append(contentsOf: fresh)
}

func refreshAllFeedsBatched() async {
    let fresh = await feedService.refreshAllFeedsBatched()
    womObjects.append(contentsOf: fresh)
}

func importOPML(data: Data) async throws -> Int {
    try await feedService.importOPML(data: data)
}
```

Remove the old inline implementations of `addFeed`, `refreshFeed`, `refreshAllFeedsBatched`, `discoverFeedURL`, `detectSourceType`.

- [ ] **Step 3: Verify build + commit**

```bash
cd Wirc && xcodegen generate --spec project.yml && xcodebuild -project Wirc.xcodeproj -scheme Wirc -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -3
```
Expected: `BUILD SUCCEEDED`

```bash
git add Wirc/WircApp/Infrastructure/Feed/FeedService.swift Wirc/WircApp/App/AppState.swift
git commit -m "feat: extract FeedService from AppState — 150 lines out of the monolith

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: Extract IRCService from AppState

**Files:**
- Create: `Wirc/WircApp/Infrastructure/IRC/IRCService.swift`
- Modify: `Wirc/WircApp/App/AppState.swift` (delegate to IRCService)

**Interfaces:**
- Consumes: `WOMRepository` (Task 5), `IRCClient` (existing), `IRCToWOMAdapter` (existing)
- Produces: `IRCService` actor with connect/disconnect/join/send/handleEvent

- [ ] **Step 1: Create IRCService**

Create `Wirc/WircApp/Infrastructure/IRC/IRCService.swift`:

```swift
import Foundation

@MainActor
final class IRCService: Sendable {
    private let repo: WOMRepository
    private let ircToWOM = IRCToWOMAdapter()
    private var clients: [UUID: IRCClient] = [:]

    var onEvent: ((IRCEvent, UUID) -> Void)?
    var onConnectionChange: ((UUID, ConnectionState) -> Void)?

    enum ConnectionState { case disconnected, connecting, online }

    init(repo: WOMRepository) {
        self.repo = repo
    }

    func connect(to config: IRCConnectionConfig) {
        let client = IRCClient(config: config)
        clients[config.id] = client

        client.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.onConnectionChange?(config.id, .connecting)
                let objects = self?.ircToWOM.convert(event, config: config) ?? []
                if !objects.isEmpty {
                    try? await self?.repo.saveMany(objects)
                }
                self?.onEvent?(event, config.id)
                if case .connected = event { self?.onConnectionChange?(config.id, .online) }
                if case .disconnected = event { self?.onConnectionChange?(config.id, .disconnected) }
            }
        }
        client.connect()
    }

    func disconnect(from id: UUID) {
        clients[id]?.disconnect()
        clients[id] = nil
        onConnectionChange?(id, .disconnected)
    }

    func joinChannel(_ channel: String, serverId: UUID) {
        let ch = channel.hasPrefix("#") ? channel : "#\(channel)"
        clients[serverId]?.join(channel: ch)
    }

    func sendMessage(_ text: String, channel: String, serverId: UUID, config: IRCConnectionConfig) async throws -> WOMObject? {
        let objectId = WOMIDGenerator.generate(type: "message")
        let obj = WOMObject(
            id: objectId,
            type: ["wom:Message"],
            createdAt: Date(),
            schema: WOMSchema.message,
            attributedTo: WOMReference(id: "local:user", type: ["wom:Person"], name: config.nickname),
            content: WOMContent(format: "text/plain", text: text),
            data: ["network": "irc", "server": config.host, "channel": channel],
            provenance: .localUser(),
            governance: WOMGovernance(
                purpose: ["messaging"],
                adsUse: WOMAdsUse.notAllowed.rawValue,
                agentUse: "allowed",
                sharing: WOMSharing.groupOnly.rawValue,
                retention: "forever"
            ),
            classification: WOMClassification(
                semanticType: "social.message",
                dataSubject: "local_user",
                origin: WOMOrigin.userProvided.rawValue,
                sensitivity: WOMDataSensitivity.personal.rawValue
            ),
            bindings: WOMBindings(irc: WOMIRCBinding(server: config.host, channel: channel, nick: config.nickname))
        )
        clients[serverId]?.sendMessage(text, to: channel)
        try await repo.save(obj)
        return obj
    }

    func localNick(for serverId: UUID, servers: [IRCConnectionConfig]) -> String {
        servers.first(where: { $0.id == serverId })?.nickname ?? "user"
    }

    var activeClients: [UUID: IRCClient] { clients }
}
```

- [ ] **Step 2: Update AppState to delegate to IRCService**

Replace `connect`, `disconnect`, `sendMessage`, `handleEvent` with delegation to `ircService`. Remove the inline IRC client management code.

- [ ] **Step 3: Verify build + commit**

```bash
cd Wirc && xcodegen generate --spec project.yml && xcodebuild -project Wirc.xcodeproj -scheme Wirc -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -3
```
Expected: `BUILD SUCCEEDED`

```bash
git add Wirc/WircApp/Infrastructure/IRC/IRCService.swift Wirc/WircApp/App/AppState.swift
git commit -m "feat: extract IRCService from AppState — 120 lines out of the monolith

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 8: Final cleanup — verify AppState <200 lines, all features work

**Files:**
- Modify: `Wirc/WircApp/App/AppState.swift` (remove dead code, simplify)
- Modify: `Wirc/WircApp/App/WircApp.swift` (verify no regressions)

**Interfaces:**
- Consumes: All previous tasks
- Produces: AppState <200 lines, all existing features working

- [ ] **Step 1: Verify AppState line count**

```
wc -l Wirc/WircApp/App/AppState.swift
```
Expected: <200 lines (down from ~500)

- [ ] **Step 2: Run full build and test**

```
cd Wirc && xcodegen generate --spec project.yml && xcodebuild -project Wirc.xcodeproj -scheme Wirc -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Manual smoke test checklist**

- [ ] Feed tab loads RSS items
- [ ] Messages tab connects to IRC
- [ ] Add feed via Settings
- [ ] Kill app, relaunch — feed shows cached items (offline)
- [ ] Kill app, relaunch — IRC server settings persist

- [ ] **Step 4: Commit**

```bash
git add Wirc/WircApp/App/AppState.swift Wirc/WircApp/App/WircApp.swift
git commit -m "refactor: finalize AppState service extraction — <200 lines, all features intact

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Completion Checklist

- [ ] Task 1: GRDB dependency + GRDBWOMStore
- [ ] Task 2: Extended WOMStore protocol + migration
- [ ] Task 3: FeedSubscriptionStore GRDB backend
- [ ] Task 4: Offline-first feed cache
- [ ] Task 5: WOMRepository wrapper
- [ ] Task 6: FeedService extracted
- [ ] Task 7: IRCService extracted
- [ ] Task 8: Cleanup + verification
- [ ] All 8 tasks build successfully
- [ ] AppState <200 lines
- [ ] No regressions in IRC, RSS, Mastodon
- [ ] Feed works offline (cached WOMs survive relaunch)
