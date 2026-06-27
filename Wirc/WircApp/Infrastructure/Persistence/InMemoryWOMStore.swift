import Foundation

final class InMemoryWOMStore: WOMStore, @unchecked Sendable {
    private var storage: [String: WOMObject] = [:]
    var isReady = true  // No disk I/O, always ready

    func save(_ object: WOMObject) async throws {
        storage[object.id] = object
    }

    func saveMany(_ objects: [WOMObject]) async throws {
        for obj in objects {
            storage[obj.id] = obj
        }
    }

    func get(id: String) async throws -> WOMObject? {
        return storage[id]
    }

    func list(type: String?) async throws -> [WOMObject] {
        let all = Array(storage.values)
        guard let type = type else { return all }
        return all.filter { $0.type.contains(type) }
    }

    func delete(id: String) async throws {
        storage.removeValue(forKey: id)
    }

    func all() async throws -> [WOMObject] {
        return Array(storage.values)
    }

    func saveIfNew(_ object: WOMObject, byCanonicalURL canonicalURL: String) async throws -> Bool {
        if storage.values.contains(where: { $0.data["canonicalUrl"] == canonicalURL }) {
            return false
        }
        storage[object.id] = object
        return true
    }

    func allSync() throws -> [WOMObject] {
        Array(storage.values)
    }

    var diskCount: Int { storage.count }
}
