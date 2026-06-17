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
}
