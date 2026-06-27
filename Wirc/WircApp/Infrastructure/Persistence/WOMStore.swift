import Foundation

protocol WOMStore: AnyObject, Sendable {
    func save(_ object: WOMObject) async throws
    func saveMany(_ objects: [WOMObject]) async throws
    func get(id: String) async throws -> WOMObject?
    func list(type: String?) async throws -> [WOMObject]
    func delete(id: String) async throws
    func all() async throws -> [WOMObject]

    /// Atomically check if an object with the given canonical URL already exists;
    /// if not, save the object. Returns true if saved, false if duplicate.
    func saveIfNew(_ object: WOMObject, byCanonicalURL canonicalURL: String) async throws -> Bool

    /// Query objects by time range, source network, and/or topic.
    func query(since: Date?, until: Date?, source: String?, topic: String?, limit: Int?) async throws -> [WOMObject]

    /// Synchronous read for init-time use. Guaranteed to be available after init returns.
    func allSync() throws -> [WOMObject]
    /// Number of objects currently in the in-memory index.
    var diskCount: Int { get }
    /// True after the store has finished loading its index from disk.
    var isReady: Bool { get set }
}

extension WOMStore {
    func query(since: Date? = nil, until: Date? = nil, source: String? = nil, topic: String? = nil, limit: Int? = nil) async throws -> [WOMObject] {
        let all = try await all()
        var result = all

        if let since = since { result = result.filter { $0.createdAt >= since } }
        if let until = until { result = result.filter { $0.createdAt <= until } }
        if let source = source { result = result.filter { ($0.data["network"] ?? "") == source } }
        if let topic = topic {
            result = result.filter { obj in
                obj.classification?.topics?.contains(where: { $0.localizedCaseInsensitiveContains(topic) }) ?? false
            }
        }

        result.sort { $0.createdAt > $1.createdAt }
        if let limit = limit { result = Array(result.prefix(limit)) }
        return result
    }
}
