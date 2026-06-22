import XCTest
@testable import Wirc

final class JSONFileStoreTests: XCTestCase {
    var store: JSONFileStore!

    override func setUp() {
        store = JSONFileStore()
    }

    func testSaveAndRetrieve() async throws {
        let obj = makeObject(id: "test-1", title: "Hello")
        try await store.save(obj)
        let retrieved = try await store.get(id: "test-1")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.name, "Hello")
    }

    func testSaveIfNew() async throws {
        let obj = makeObject(id: "test-2", title: "First")
        let saved = try await store.saveIfNew(obj, byCanonicalURL: "https://example.com/1")
        XCTAssertTrue(saved)
        let duplicate = try await store.saveIfNew(obj, byCanonicalURL: "https://example.com/1")
        XCTAssertFalse(duplicate)
    }

    func testDelete() async throws {
        let obj = makeObject(id: "test-3")
        try await store.save(obj)
        try await store.delete(id: "test-3")
        let gone = try await store.get(id: "test-3")
        XCTAssertNil(gone)
    }

    func testTrimIndex() async throws {
        for i in 0..<2100 {
            try await store.save(makeObject(id: "obj-\(i)", date: Date().addingTimeInterval(Double(-i))))
        }
        let count = await store.count
        XCTAssertLessThanOrEqual(count, 2000)
    }

    private func makeObject(id: String, title: String? = nil, date: Date = Date()) -> WOMObject {
        WOMObject(id: id, type: ["wom:Post"], createdAt: date, name: title,
                  data: ["network": "test"], provenance: .localUser())
    }
}
