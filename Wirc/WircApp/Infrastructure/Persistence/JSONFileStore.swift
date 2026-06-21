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
    private let objectsDir: URL
    private let queue = DispatchQueue(label: "wirc.jsonfilestore", attributes: .concurrent)

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
            fatalError("No document directory available")
        }
        objectsDir = docs.appendingPathComponent("wirc/objects", isDirectory: true)
        try? FileManager.default.createDirectory(at: objectsDir, withIntermediateDirectories: true)
        // Load index on background queue — avoids blocking init on 2000 JSON file reads.
        queue.async { [weak self] in
            self?.loadIndex()
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
        queue.sync { index[id] }
    }

    func list(type: String?) async throws -> [WOMObject] {
        queue.sync {
            let all = Array(index.values)
            guard let type = type else { return all }
            // Array.contains checks exact element match since $0.type is [String]
            return all.filter { $0.type.contains(type) }
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
                    self.index.removeValue(forKey: id)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func all() async throws -> [WOMObject] {
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
                if index.values.contains(where: { $0.data["canonicalUrl"] == canonicalURL }) {
                    continuation.resume(returning: false)
                    return
                }
                do {
                    try self.writeObject(object)
                    self.index[object.id] = object
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
            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONDecoder().decode(WOMObject.self, from: data) else { continue }
            allObjects.append(obj)
        }
        // Sort by date descending, keep most recent
        allObjects.sort { $0.createdAt > $1.createdAt }
        for obj in allObjects.prefix(maxIndexSize) {
            index[obj.id] = obj
        }
    }

    /// Enforces the in-memory index cap by evicting the oldest objects
    /// when the index exceeds maxIndexSize. Called from write success paths.
    private func trimIndex() {
        let before = index.count
        guard before > maxIndexSize else { return }
        let sorted = index.values.sorted { $0.createdAt > $1.createdAt }
        index = Dictionary(uniqueKeysWithValues: sorted.prefix(maxIndexSize).map { ($0.id, $0) })
        let dropped = before - index.count
        os_log(.debug, "JSONFileStore: trimmed index from %d to %d (dropped %d)", before, index.count, dropped)
    }

    /// The number of objects currently in the on-disk index (for tests/debug).
    var diskCount: Int {
        queue.sync { index.count }
    }
}
