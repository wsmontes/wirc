import Foundation

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
        loadIndex()
    }

    // MARK: - WOMStore

    func save(_ object: WOMObject) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async(flags: .barrier) { [weak self] in
                guard let self else {
                    continuation.resume(throwing: JSONFileStoreError.deallocated)
                    return
                }
                do {
                    try self.writeObject(object)
                    self.index[object.id] = object
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func saveMany(_ objects: [WOMObject]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async(flags: .barrier) { [weak self] in
                guard let self else {
                    continuation.resume(throwing: JSONFileStoreError.deallocated)
                    return
                }
                do {
                    for obj in objects {
                        try self.writeObject(obj)
                        self.index[obj.id] = obj
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
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
        try await withCheckedThrowingContinuation { continuation in
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
