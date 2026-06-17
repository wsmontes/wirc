import Foundation

/// Persistent WOMStore backed by individual JSON files on disk.
/// One file per WOMObject: ~/Documents/wirc/objects/{id}.json
/// Maintains an in-memory index for fast queries.
final class JSONFileStore: WOMStore, @unchecked Sendable {
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
