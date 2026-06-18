import XCTest
@testable import EmberCore

final class RecentFoodsTests: XCTestCase {

    private func entry(_ name: String, foodID: String?, at: Date,
                       cals: Double = 100, servings: Double = 1,
                       meal: Meal = .lunch) -> FoodEntry {
        FoodEntry(dayKey: "2026-06-15", loggedAt: at, foodID: foodID, name: name,
                  servings: servings, macrosPerServing: Macros(calories: cals, proteinG: 1, carbG: 1, fatG: 1),
                  meal: meal)
    }

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testNewestFirst() {
        let day = DayNutrition(dayKey: "d", entries: [
            entry("Apple", foodID: "apple", at: t0),
            entry("Banana", foodID: "banana", at: t0.addingTimeInterval(60)),
        ])
        let recents = RecentFoods.from([day])
        XCTAssertEqual(recents.map(\.name), ["Banana", "Apple"])
    }

    func testDedupesByFoodIDKeepingMostRecent() {
        let day = DayNutrition(dayKey: "d", entries: [
            entry("Eggs", foodID: "eggs", at: t0, cals: 70),
            entry("Eggs", foodID: "eggs", at: t0.addingTimeInterval(120), cals: 75),
            entry("Toast", foodID: "toast", at: t0.addingTimeInterval(60)),
        ])
        let recents = RecentFoods.from([day])
        XCTAssertEqual(recents.map(\.name), ["Eggs", "Toast"])
        // The kept Eggs is the most recent one (75 kcal, logged latest).
        XCTAssertEqual(recents.first?.macrosPerServing.calories, 75)
    }

    func testDedupesByNameWhenNoFoodID() {
        let day = DayNutrition(dayKey: "d", entries: [
            entry("oatmeal", foodID: nil, at: t0),
            entry("Oatmeal", foodID: nil, at: t0.addingTimeInterval(30)),
        ])
        XCTAssertEqual(RecentFoods.from([day]).count, 1)
    }

    func testMergesAcrossDaysAndHonorsLimit() {
        let d1 = DayNutrition(dayKey: "d1", entries: (0..<5).map {
            entry("f\($0)", foodID: "f\($0)", at: t0.addingTimeInterval(Double($0)))
        })
        let d2 = DayNutrition(dayKey: "d2", entries: (5..<10).map {
            entry("f\($0)", foodID: "f\($0)", at: t0.addingTimeInterval(Double($0)))
        })
        let recents = RecentFoods.from([d1, d2], limit: 3)
        XCTAssertEqual(recents.map(\.name), ["f9", "f8", "f7"])
    }

    func testEmpty() {
        XCTAssertTrue(RecentFoods.from([]).isEmpty)
    }

    func testSnapshotsLastServingsAndMeal() {
        let day = DayNutrition(dayKey: "d", entries: [
            entry("Rice", foodID: "rice", at: t0, servings: 3, meal: .dinner),
        ])
        let recent = RecentFoods.from([day]).first
        XCTAssertEqual(recent?.lastServings, 3)
        XCTAssertEqual(recent?.lastMeal, .dinner)
    }

    func testSnapshotUsesMostRecentEntry() {
        let day = DayNutrition(dayKey: "d", entries: [
            entry("Rice", foodID: "rice", at: t0, servings: 1, meal: .lunch),
            entry("Rice", foodID: "rice", at: t0.addingTimeInterval(120),
                  servings: 2.5, meal: .dinner),
        ])
        let recent = RecentFoods.from([day]).first
        XCTAssertEqual(recent?.lastServings, 2.5)
        XCTAssertEqual(recent?.lastMeal, .dinner)
    }
}
