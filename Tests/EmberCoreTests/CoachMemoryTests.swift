import XCTest
@testable import EmberCore

final class CoachMemoryTests: XCTestCase {

    func testAddingAppends() {
        let m = CoachMemory.empty
            .adding(category: "diet", text: "vegetarian")
            .adding(text: "wants to gain muscle")
        XCTAssertEqual(m.items.count, 2)
        XCTAssertEqual(m.items[0].category, "diet")
        XCTAssertEqual(m.items[0].text, "vegetarian")
        // Default category.
        XCTAssertEqual(m.items[1].category, "general")
        XCTAssertEqual(m.items[1].text, "wants to gain muscle")
    }

    func testUpdatingTargetsOnlyMatchingIDAndNoOpsOnUnknown() {
        let m = CoachMemory.empty
            .adding(category: "diet", text: "vegetarian")
            .adding(category: "goals", text: "gain muscle")
        let targetID = m.items[1].id

        let updated = m.updating(id: targetID, text: "gain 5 kg muscle")
        XCTAssertEqual(updated.items[0].text, "vegetarian")          // untouched
        XCTAssertEqual(updated.items[1].text, "gain 5 kg muscle")    // changed
        XCTAssertEqual(updated.items[1].category, "goals")           // unchanged when nil

        // Unknown id no-ops.
        let unchanged = m.updating(id: UUID(), text: "nope")
        XCTAssertEqual(unchanged, m)
    }

    func testRemovingDropsTargetedID() {
        let m = CoachMemory.empty
            .adding(text: "a")
            .adding(text: "b")
        let dropID = m.items[0].id
        let after = m.removing(id: dropID)
        XCTAssertEqual(after.items.count, 1)
        XCTAssertEqual(after.items[0].text, "b")
        // Unknown id no-ops.
        XCTAssertEqual(m.removing(id: UUID()), m)
    }

    func testCappedKeepsMostRecentN() {
        var m = CoachMemory.empty
        for i in 0..<5 { m = m.adding(text: "fact \(i)") }
        let capped = m.capped(to: 3)
        XCTAssertEqual(capped.items.count, 3)
        XCTAssertEqual(capped.items.map { $0.text }, ["fact 2", "fact 3", "fact 4"])
        // No-op when under the cap.
        XCTAssertEqual(m.capped(to: 10), m)
    }

    func testPromptLinesRenderCategoryBracketExceptGeneral() {
        let m = CoachMemory.empty
            .adding(category: "injuries", text: "left knee — avoid deep squats")
            .adding(category: "general", text: "trains in the morning")
            .adding(text: "no category given")
        XCTAssertEqual(m.promptLines(), [
            "- [injuries] left knee — avoid deep squats",
            "- trains in the morning",
            "- no category given",
        ])
    }

    func testEmptyHasNoPromptLines() {
        XCTAssertTrue(CoachMemory.empty.isEmpty)
        XCTAssertTrue(CoachMemory.empty.promptLines().isEmpty)
    }

    func testCodableRoundTrips() throws {
        let item = CoachMemoryItem(category: "diet", text: "vegetarian",
                                   createdAt: Date(timeIntervalSince1970: 10))
        let m = CoachMemory(items: [item])
        XCTAssertEqual(try JSONDecoder().decode(CoachMemory.self, from: JSONEncoder().encode(m)), m)
    }

    func testInMemoryStoreDefaultsEmptyAndRoundTrips() {
        let store = InMemoryHealthStore()
        XCTAssertEqual(store.loadCoachMemory(), .empty)
        let m = CoachMemory.empty.adding(category: "goals", text: "run 5k")
        store.saveCoachMemory(m)
        XCTAssertEqual(store.loadCoachMemory(), m)
    }
}
