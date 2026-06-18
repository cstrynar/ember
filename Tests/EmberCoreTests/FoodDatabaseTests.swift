import XCTest
@testable import EmberCore

final class FoodDatabaseTests: XCTestCase {

    private func food(_ id: String, _ name: String, source: FoodSource = .preloaded) -> FoodItem {
        FoodItem(id: id, name: name, servingDescription: "1", macrosPerServing: .zero, source: source)
    }

    func testSearchRanksExactThenPrefixThenContains() {
        let db = FoodDatabase(items: [
            food("a", "Apple"),
            food("aj", "Apple juice"),
            food("pa", "Pineapple"),
            food("b", "Banana"),
        ])
        XCTAssertEqual(db.search("apple").map { $0.name }, ["Apple", "Apple juice", "Pineapple"])
    }

    func testSearchIsCaseInsensitiveAndTrimmed() {
        let db = FoodDatabase(items: [food("a", "Apple")])
        XCTAssertEqual(db.search("  APPLE ").first?.id, "a")
    }

    func testEmptyQueryReturnsNothing() {
        let db = FoodDatabase(items: [food("a", "Apple")])
        XCTAssertTrue(db.search("").isEmpty)
        XCTAssertTrue(db.search("   ").isEmpty)
    }

    func testSearchLimit() {
        let db = FoodDatabase(items: [food("a", "Apple"), food("aj", "Apple juice"), food("pa", "Pineapple")])
        XCTAssertEqual(db.search("apple", limit: 1).count, 1)
    }

    func testItemByID() {
        let db = FoodDatabase(items: [food("a", "Apple"), food("b", "Banana")])
        XCTAssertEqual(db.item(id: "b")?.name, "Banana")
        XCTAssertNil(db.item(id: "zzz"))
    }

    func testMergingCustomOverridesByID() {
        let db = FoodDatabase(items: [food("a", "Apple", source: .preloaded)])
        let merged = db.merging(custom: [
            food("a", "Apple (mine)", source: .custom),
            food("c", "Custom Cookie", source: .custom),
        ])
        XCTAssertEqual(merged.items.count, 2)
        XCTAssertEqual(merged.item(id: "a")?.source, .custom)
        XCTAssertEqual(merged.item(id: "a")?.name, "Apple (mine)")
        XCTAssertEqual(merged.item(id: "c")?.source, .custom)
    }

    func testLoadPreloadedBundledData() {
        let db = FoodDatabase.loadPreloaded()
        XCTAssertGreaterThan(db.items.count, 100)
        XCTAssertEqual(db.item(id: "banana")?.name, "Banana")
        XCTAssertNotNil(db.item(id: "chicken_breast_cooked"))
        XCTAssertTrue(db.items.allSatisfy { $0.source == .preloaded })
    }
}
