import XCTest
@testable import EmberCore

final class NutritionTests: XCTestCase {

    func testFoodEntryConsumedScales() {
        let e = FoodEntry(dayKey: "2026-06-15", name: "X", servings: 2,
                          macrosPerServing: Macros(calories: 100, proteinG: 10, carbG: 5, fatG: 2),
                          meal: .lunch)
        XCTAssertEqual(e.consumed, Macros(calories: 200, proteinG: 20, carbG: 10, fatG: 4))
    }

    func testFoodEntryFromFoodItem() {
        let item = FoodItem(id: "egg", name: "Egg", servingDescription: "1 large",
                            macrosPerServing: Macros(calories: 72, proteinG: 6, carbG: 0.4, fatG: 4.8),
                            source: .preloaded)
        let e = FoodEntry(food: item, dayKey: "d", servings: 3, meal: .breakfast)
        XCTAssertEqual(e.foodID, "egg")
        XCTAssertEqual(e.name, "Egg")
        XCTAssertEqual(e.consumed.proteinG, 18, accuracy: 0.001)
    }

    func testDayConsumedSums() {
        var day = DayNutrition(dayKey: "2026-06-15")
        day = day.appending(FoodEntry(dayKey: "2026-06-15", name: "A", servings: 1,
                macrosPerServing: Macros(calories: 100, proteinG: 10, carbG: 5, fatG: 2), meal: .breakfast))
        day = day.appending(FoodEntry(dayKey: "2026-06-15", name: "B", servings: 2,
                macrosPerServing: Macros(calories: 50, proteinG: 4, carbG: 8, fatG: 1), meal: .lunch))
        XCTAssertEqual(day.consumed, Macros(calories: 200, proteinG: 18, carbG: 21, fatG: 4))
    }

    func testConsumedByMeal() {
        var day = DayNutrition(dayKey: "d")
        day = day.appending(FoodEntry(dayKey: "d", name: "A", servings: 1,
                macrosPerServing: Macros(calories: 100, proteinG: 10, carbG: 0, fatG: 0), meal: .breakfast))
        day = day.appending(FoodEntry(dayKey: "d", name: "B", servings: 1,
                macrosPerServing: Macros(calories: 200, proteinG: 20, carbG: 0, fatG: 0), meal: .lunch))
        XCTAssertEqual(day.consumed(for: .breakfast).calories, 100, accuracy: 0.001)
        XCTAssertEqual(day.consumed(for: .lunch).proteinG, 20, accuracy: 0.001)
        XCTAssertEqual(day.consumed(for: .dinner), .zero)
    }

    func testRemainingAgainstGoal() {
        let goal = Macros(calories: 2000, proteinG: 150, carbG: 200, fatG: 60)
        var day = DayNutrition(dayKey: "d")
        day = day.appending(FoodEntry(dayKey: "d", name: "A", servings: 1,
                macrosPerServing: Macros(calories: 500, proteinG: 40, carbG: 50, fatG: 10), meal: .lunch))
        XCTAssertEqual(day.remaining(against: goal),
                       Macros(calories: 1500, proteinG: 110, carbG: 150, fatG: 50))
    }

    func testRemovingEntry() {
        let e = FoodEntry(dayKey: "d", name: "A", servings: 1,
                macrosPerServing: Macros(calories: 100, proteinG: 0, carbG: 0, fatG: 0), meal: .snack)
        var day = DayNutrition(dayKey: "d", entries: [e])
        day = day.removing(id: e.id)
        XCTAssertTrue(day.entries.isEmpty)
        XCTAssertEqual(day.consumed, .zero)
    }

    func testHydrationClampsAndAdds() {
        let h = HydrationLog(dayKey: "d", milliliters: -50)
        XCTAssertEqual(h.milliliters, 0)
        XCTAssertEqual(h.adding(500).milliliters, 500)
        XCTAssertEqual(h.adding(500).adding(-200).milliliters, 300)
        XCTAssertEqual(h.adding(100).adding(-500).milliliters, 0)
    }
}
