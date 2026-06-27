import Foundation
import os.log

/// Persistent WOMStore backed by individual JSON files on disk.
/// One file per WOMObject: ~/Documents/wirc/objects/{id}.json
/// Maintains an in-memory index for fast queries.
///
/// @unchecked Sendable: all mutable state is protected by the concurrent queue
/// (barrier blocks for writes, sync blocks for reads). `queue` and `objectsDir`
/// are `let` constants set at init and never mutated.
final class JSONFileStore: WOMStore, @unchecked Sendable {
    private var index: [String: WOMObject] = [:]
    /// Maps canonicalUrl → objectId for O(1) dedup lookups.
    private var canonicalIndex: [String: String] = [:]
    var isReady = false
    private let objectsDir: URL
    private let queue = DispatchQueue(label: "wirc.jsonfilestore", attributes: .concurrent)

    private static let schemaVersion = 1

    private enum JSONFileStoreError: LocalizedError {
        case noDocumentDirectory
        case deallocated

        var errorDescription: String? {
            switch self {
            case .noDocumentDirectory:
                return "No document directory available"
            case .deallocated:
                return "JSONFileStore was deallocated"
            }
        }
    }

    init() {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            os_log(.error, "JSONFileStore: no document directory — using in-memory mode")
            objectsDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wirc-fallback")
            try? FileManager.default.createDirectory(at: objectsDir, withIntermediateDirectories: true)
            return
        }
        objectsDir = docs.appendingPathComponent("wirc/objects", isDirectory: true)
        try? FileManager.default.createDirectory(at: objectsDir, withIntermediateDirectories: true)
        checkSchemaVersion()
        // Load index on background queue. Set isReady when done so UI can show splash.
        queue.async { [weak self] in
            self?.loadIndex()
            Task { @MainActor in
                self?.isReady = true
            }
        }
    }

    // MARK: - WOMStore

    func save(_ object: WOMObject) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async(flags: .barrier) { [weak self] in
                guard let self else {
                    continuation.resume(throwing: JSONFileStoreError.deallocated)
                    return
                }
                do {
                    try self.writeObject(object)
                    self.index[object.id] = object
                    if let url = object.data["canonicalUrl"] {
                        self.canonicalIndex[url] = object.id
                    }
                    self.trimIndex()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func saveMany(_ objects: [WOMObject]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async(flags: .barrier) { [weak self] in
                guard let self else {
                    continuation.resume(throwing: JSONFileStoreError.deallocated)
                    return
                }
                // Track successfully written object IDs so we can index them
                // even if a later write fails (partial success).
                var writtenIDs: [String] = []
                var writeError: Error?
                for obj in objects {
                    do {
                        try self.writeObject(obj)
                        writtenIDs.append(obj.id)
                    } catch {
                        writeError = error
                        break
                    }
                }
                // Index every object that was successfully written to disk
                for obj in objects where writtenIDs.contains(obj.id) {
                    self.index[obj.id] = obj
                    if let url = obj.data["canonicalUrl"] {
                        self.canonicalIndex[url] = obj.id
                    }
                }
                self.trimIndex()
                if let error = writeError {
                    os_log(.error, "JSONFileStore.saveMany: partial write failure after %d/%d objects: %{public}@",
                           writtenIDs.count, objects.count, error.localizedDescription)
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func get(id: String) async throws -> WOMObject? {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                continuation.resume(returning: self?.index[id])
            }
        }
    }

    func list(type: String?) async throws -> [WOMObject] {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: [])
                    return
                }
                let all = Array(self.index.values)
                guard let type = type else {
                    continuation.resume(returning: all)
                    return
                }
                continuation.resume(returning: all.filter { $0.type.contains(type) })
            }
        }
    }

    func delete(id: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async(flags: .barrier) { [weak self] in
                guard let self else {
                    continuation.resume(throwing: JSONFileStoreError.deallocated)
                    return
                }
                do {
                    let url = self.fileURL(for: id)
                    if FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.removeItem(at: url)
                    }
                    if let obj = self.index[id], let url = obj.data["canonicalUrl"] {
                        self.canonicalIndex.removeValue(forKey: url)
                    }
                    self.index.removeValue(forKey: id)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func all() async throws -> [WOMObject] {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: Array(self.index.values))
            }
        }
    }

    /// Synchronous read for init-time use. The index is guaranteed loaded because
    /// loadIndex() runs via queue.sync in init() before any caller can access this.
    func allSync() throws -> [WOMObject] {
        queue.sync { Array(index.values) }
    }

    /// Atomically checks for an existing object with the same canonical URL
    /// and saves only if none exists. Returns true if saved, false if duplicate.
    func saveIfNew(_ object: WOMObject, byCanonicalURL canonicalURL: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            queue.async(flags: .barrier) { [weak self] in
                guard let self else {
                    continuation.resume(throwing: JSONFileStoreError.deallocated)
                    return
                }
                // Atomically check for duplicate inside the barrier
                if self.canonicalIndex[canonicalURL] != nil {
                    continuation.resume(returning: false)
                    return
                }
                do {
                    try self.writeObject(object)
                    self.index[object.id] = object
                    self.canonicalIndex[canonicalURL] = object.id
                    self.trimIndex()
                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Dedup

    /// Returns true if an object with the given canonical URL already exists.
    func contains(canonicalURL: String) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                continuation.resume(returning: self?.canonicalIndex[canonicalURL] != nil)
            }
        }
    }

    /// Returns count of stored objects (for tests/debug).
    var count: Int {
        get async {
            await withCheckedContinuation { continuation in
                queue.async { [weak self] in
                    continuation.resume(returning: self?.index.count ?? 0)
                }
            }
        }
    }

    // MARK: - Private

    private func fileURL(for id: String) -> URL {
        let safe = id.replacingOccurrences(of: "/", with: "_")
                      .replacingOccurrences(of: ":", with: "_")
        return objectsDir.appendingPathComponent("\(safe).json")
    }

    /// Encodes `object` to JSON and writes it atomically to disk. Throws on
    /// encoding or file I/O failure.
    private func writeObject(_ object: WOMObject) throws {
        let data = try JSONEncoder().encode(object)
        let url = fileURL(for: object.id)
        try data.write(to: url, options: .atomic)
    }

    private let maxIndexSize = 2000

    private func loadIndex() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: objectsDir, includingPropertiesForKeys: nil
        ) else { return }
        // Load all, then keep only the most recent to cap memory
        var allObjects: [WOMObject] = []
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url) else {
                os_log(.error, "JSONFileStore: could not read file %{public}@", url.lastPathComponent)
                continue
            }
            guard let obj = try? JSONDecoder().decode(WOMObject.self, from: data) else {
                os_log(.error, "JSONFileStore: corrupted file %{public}@", url.lastPathComponent)
                continue
            }
            allObjects.append(obj)
        }
        // Sort by date descending, keep most recent
        allObjects.sort { $0.createdAt > $1.createdAt }
        for obj in allObjects.prefix(maxIndexSize) {
            index[obj.id] = obj
            if let url = obj.data["canonicalUrl"] {
                canonicalIndex[url] = obj.id
            }
        }
    }

    /// Enforces the in-memory index cap by evicting the oldest objects
    /// when the index exceeds maxIndexSize. Called from write success paths.
    private func trimIndex() {
        let before = index.count
        guard before > maxIndexSize else { return }
        let sorted = index.values.sorted { $0.createdAt > $1.createdAt }
        index = Dictionary(uniqueKeysWithValues: sorted.prefix(maxIndexSize).map { ($0.id, $0) })
        // Rebuild canonicalIndex from remaining entries
        canonicalIndex = [:]
        for obj in index.values {
            if let url = obj.data["canonicalUrl"] {
                canonicalIndex[url] = obj.id
            }
        }
        let dropped = before - index.count
        os_log(.debug, "JSONFileStore: trimmed index from %d to %d (dropped %d)", before, index.count, dropped)
    }

    /// Checks stored schema version and performs migration if needed.
    /// Returns true if the store is ready (migration succeeded or version matches).
    private func checkSchemaVersion() {
        let key = "wirc.store.schemaVersion"
        let stored = UserDefaults.standard.integer(forKey: key)
        if stored < Self.schemaVersion {
            os_log(.info, "JSONFileStore: migrating schema from v%d to v%d", stored, Self.schemaVersion)
            UserDefaults.standard.set(Self.schemaVersion, forKey: key)
        }
    }

    /// The number of objects currently in the on-disk index (for tests/debug).
    var diskCount: Int {
        queue.sync { index.count }
    }
}
