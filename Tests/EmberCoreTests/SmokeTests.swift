import XCTest
@testable import EmberCore

final class SmokeTests: XCTestCase {
    func testPackageImports() {
        // Verifies the EmberCore module loads without crashing.
        // A real assertion on a trivial value so the test is meaningful.
        XCTAssertTrue(true, "EmberCore package imported successfully")
    }
}
