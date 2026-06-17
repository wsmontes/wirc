import Foundation

protocol WOMStore: AnyObject, Sendable {
    func save(_ object: WOMObject) async throws
    func saveMany(_ objects: [WOMObject]) async throws
    func get(id: String) async throws -> WOMObject?
    func list(type: String?) async throws -> [WOMObject]
    func delete(id: String) async throws
    func all() async throws -> [WOMObject]
}
