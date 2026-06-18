import XCTest
@testable import EmberCore

final class HealthStoreTests: XCTestCase {

    func testProfileRoundTrip() {
        let store = InMemoryHealthStore()
        XCTAssertNil(store.loadProfile())
        // Profile without a target weight: goalWeightKg defaults to nil and round-trips.
        let p = UserProfile(sex: .female, age: 28, heightCm: 168, weightKg: 62,
                            activity: .active, goal: .maintain, dietaryPattern: .highProtein)
        XCTAssertNil(p.goalWeightKg)
        store.saveProfile(p)
        XCTAssertEqual(store.loadProfile(), p)
        // Profile with a target weight round-trips equal.
        let pGoal = UserProfile(sex: .female, age: 28, heightCm: 168, weightKg: 62,
                                activity: .active, goal: .lose, dietaryPattern: .highProtein,
                                goalWeightKg: 70)
        store.saveProfile(pGoal)
        XCTAssertEqual(store.loadProfile(), pGoal)
    }

    /// A pre-Stage-6 `profile.json` omits the `goalWeightKg` key; it must still decode,
    /// with the new optional field defaulting to nil (synthesized Codable backward-compat).
    func testProfileDecodesWithoutGoalWeightKey() throws {
        let json = """
        {"sex":"male","age":35,"heightCm":180,"weightKg":80,"activity":"moderate",
         "goal":"maintain","dietaryPattern":"balanced","notes":""}
        """
        let decoded = try JSONDecoder().decode(UserProfile.self, from: Data(json.utf8))
        XCTAssertNil(decoded.goalWeightKg)
    }

    func testGoalOverrideNilByDefaultAndClearable() {
        let store = InMemoryHealthStore()
        XCTAssertNil(store.loadGoalOverride())
        let m = Macros(calories: 2200, proteinG: 180, carbG: 200, fatG: 70)
        store.saveGoalOverride(m)
        XCTAssertEqual(store.loadGoalOverride(), m)
        store.saveGoalOverride(nil)
        XCTAssertNil(store.loadGoalOverride())
    }

    func testDayAndAllDays() {
        let store = InMemoryHealthStore()
        XCTAssertNil(store.loadDay("2026-06-15"))
        let day = DayNutrition(dayKey: "2026-06-15", entries: [
            FoodEntry(dayKey: "2026-06-15", name: "A", servings: 1,
                      macrosPerServing: Macros(calories: 100, proteinG: 5, carbG: 5, fatG: 5), meal: .lunch),
        ])
        store.saveDay(day)
        store.saveDay(DayNutrition(dayKey: "2026-06-14"))
        XCTAssertEqual(store.loadDay("2026-06-15"), day)
        XCTAssertEqual(store.allDays().count, 2)
    }

    func testHydrationAndCustomFoodsAndReminders() {
        let store = InMemoryHealthStore()
        XCTAssertEqual(store.loadReminderSettings(), .default) // default before any save

        store.saveHydration(HydrationLog(dayKey: "d", milliliters: 750))
        XCTAssertEqual(store.loadHydration("d")?.milliliters, 750)

        let food = FoodItem(id: "custom_x", name: "My Smoothie", servingDescription: "1",
                            macrosPerServing: Macros(calories: 250, proteinG: 30, carbG: 20, fatG: 5),
                            source: .custom)
        store.saveCustomFoods([food])
        XCTAssertEqual(store.loadCustomFoods(), [food])

        var settings = ReminderSettings.default
        settings.reminders[0].enabled = false
        store.saveReminderSettings(settings)
        XCTAssertEqual(store.loadReminderSettings(), settings)
    }
}
