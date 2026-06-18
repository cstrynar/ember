import XCTest
@testable import EmberCore

final class FrictionReportTests: XCTestCase {

    func testFrictionAppendAndClear() {
        let store = InMemoryHealthStore()
        XCTAssertTrue(store.loadFrictionLog().isEmpty)
        store.appendFriction(FrictionEntry(context: "food", note: "hard to find oats"))
        store.appendFriction(FrictionEntry(context: "workout", note: "no superset support"))
        XCTAssertEqual(store.loadFrictionLog().count, 2)
        store.clearFrictionLog()
        XCTAssertTrue(store.loadFrictionLog().isEmpty)
    }

    func testReportSaveLoadAndOverwriteByDay() {
        let store = InMemoryHealthStore()
        XCTAssertTrue(store.loadReports().isEmpty)
        store.saveReport(CoachReport(id: "2026-06-15", createdAt: Date(timeIntervalSince1970: 1), markdown: "# r1"))
        store.saveReport(CoachReport(id: "2026-06-08", createdAt: Date(timeIntervalSince1970: 2), markdown: "# r2"))
        XCTAssertEqual(store.loadReports().count, 2)
        // Same day id overwrites rather than duplicating.
        store.saveReport(CoachReport(id: "2026-06-15", createdAt: Date(timeIntervalSince1970: 3), markdown: "# r1b"))
        XCTAssertEqual(store.loadReports().count, 2)
        XCTAssertEqual(store.loadReports().first { $0.id == "2026-06-15" }?.markdown, "# r1b")
    }

    func testCodableRoundTrips() throws {
        let f = FrictionEntry(context: "c", note: "n")
        XCTAssertEqual(try JSONDecoder().decode(FrictionEntry.self, from: JSONEncoder().encode(f)), f)
        let r = CoachReport(id: "d", createdAt: Date(timeIntervalSince1970: 5), markdown: "x")
        XCTAssertEqual(try JSONDecoder().decode(CoachReport.self, from: JSONEncoder().encode(r)), r)
    }
}
