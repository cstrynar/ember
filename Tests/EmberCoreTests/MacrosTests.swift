import XCTest
@testable import EmberCore

final class MacrosTests: XCTestCase {

    func testAddition() {
        let a = Macros(calories: 100, proteinG: 10, carbG: 5, fatG: 2)
        let b = Macros(calories: 50, proteinG: 4, carbG: 8, fatG: 1)
        XCTAssertEqual(a + b, Macros(calories: 150, proteinG: 14, carbG: 13, fatG: 3))
    }

    func testSubtraction() {
        let goal = Macros(calories: 2000, proteinG: 150, carbG: 200, fatG: 60)
        let eaten = Macros(calories: 500, proteinG: 40, carbG: 50, fatG: 20)
        XCTAssertEqual(goal - eaten, Macros(calories: 1500, proteinG: 110, carbG: 150, fatG: 40))
    }

    func testScaled() {
        let m = Macros(calories: 100, proteinG: 10, carbG: 5, fatG: 2)
        XCTAssertEqual(m.scaled(by: 2.5), Macros(calories: 250, proteinG: 25, carbG: 12.5, fatG: 5))
    }

    func testZeroIsAdditiveIdentity() {
        let m = Macros(calories: 42, proteinG: 3, carbG: 7, fatG: 1)
        XCTAssertEqual(m + .zero, m)
    }

    func testRounded() {
        let m = Macros(calories: 2758.6, proteinG: 128.4, carbG: 308.96, fatG: 112.35)
        XCTAssertEqual(m.rounded(), Macros(calories: 2759, proteinG: 128, carbG: 309, fatG: 112))
    }

    func testCaloriesFromMacros() {
        let m = Macros(calories: 0, proteinG: 10, carbG: 20, fatG: 5)
        let expected: Double = 10 * 4 + 20 * 4 + 5 * 9
        XCTAssertEqual(m.caloriesFromMacros, expected, accuracy: 0.0001)
    }
}
