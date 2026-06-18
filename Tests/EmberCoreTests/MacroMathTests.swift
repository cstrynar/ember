import XCTest
@testable import EmberCore

final class MacroMathTests: XCTestCase {

    private func profile(sex: BiologicalSex = .male, age: Int = 30, h: Double = 180,
                         w: Double = 80, activity: ActivityLevel = .moderate,
                         goal: Goal = .maintain,
                         pattern: DietaryPattern = .balanced) -> UserProfile {
        UserProfile(sex: sex, age: age, heightCm: h, weightKg: w, activity: activity,
                    goal: goal, dietaryPattern: pattern)
    }

    // MARK: - Energy (hand-computed anchors)

    func testBMRMale() {
        // 10*80 + 6.25*180 - 5*30 + 5 = 1780
        XCTAssertEqual(MacroMath.basalMetabolicRate(profile: profile()), 1780, accuracy: 0.001)
    }

    func testBMRFemale() {
        // 10*60 + 6.25*165 - 5*25 - 161 = 1345.25
        let p = profile(sex: .female, age: 25, h: 165, w: 60)
        XCTAssertEqual(MacroMath.basalMetabolicRate(profile: p), 1345.25, accuracy: 0.001)
    }

    func testTDEE() {
        // 1780 * 1.55 = 2759
        XCTAssertEqual(MacroMath.totalDailyEnergyExpenditure(profile: profile()), 2759, accuracy: 0.001)
    }

    func testGoalCaloriesMaintain() {
        XCTAssertEqual(MacroMath.goalCalories(profile: profile(goal: .maintain)), 2759, accuracy: 0.001)
    }

    func testGoalCaloriesLose() {
        XCTAssertEqual(MacroMath.goalCalories(profile: profile(goal: .lose)), 2259, accuracy: 0.001)
    }

    func testGoalCaloriesGain() {
        XCTAssertEqual(MacroMath.goalCalories(profile: profile(goal: .gain)), 3109, accuracy: 0.001)
    }

    func testMinimumCalorieFloor() {
        // Small, sedentary, losing: raw target falls below 1200 and is floored.
        let p = profile(sex: .female, age: 60, h: 150, w: 45, activity: .sedentary, goal: .lose)
        XCTAssertEqual(MacroMath.goalCalories(profile: p), 1200, accuracy: 0.001)
    }

    // MARK: - Macro split

    func testBalancedSplit() {
        let goal = MacroMath.recommendedGoal(profile: profile(goal: .maintain, pattern: .balanced))
        XCTAssertEqual(goal, Macros(calories: 2759, proteinG: 128, carbG: 309, fatG: 112))
    }

    func testKetoSplit() {
        let goal = MacroMath.recommendedGoal(profile: profile(goal: .maintain, pattern: .keto))
        XCTAssertEqual(goal.calories, 2759, accuracy: 0.001)
        XCTAssertEqual(goal.proteinG, 144, accuracy: 0.001) // 1.8 * 80
        XCTAssertEqual(goal.carbG, 25, accuracy: 0.001)     // ~100 kcal cap / 4
        XCTAssertEqual(goal.fatG, 231, accuracy: 0.001)
    }

    func testHighProteinHasMoreProteinThanBalanced() {
        let hp = MacroMath.recommendedGoal(profile: profile(pattern: .highProtein))
        let bal = MacroMath.recommendedGoal(profile: profile(pattern: .balanced))
        XCTAssertGreaterThan(hp.proteinG, bal.proteinG)
    }

    func testMacroEnergyRoughlyMatchesCalories() {
        let goal = MacroMath.recommendedGoal(profile: profile())
        XCTAssertEqual(goal.caloriesFromMacros, goal.calories, accuracy: 30)
    }

    func testGoalMacrosNeverNegative() {
        // keto + floored low calories must still keep every macro non-negative.
        let p = profile(sex: .female, age: 60, h: 150, w: 45,
                        activity: .sedentary, goal: .lose, pattern: .keto)
        let goal = MacroMath.recommendedGoal(profile: p)
        XCTAssertGreaterThanOrEqual(goal.proteinG, 0)
        XCTAssertGreaterThanOrEqual(goal.carbG, 0)
        XCTAssertGreaterThanOrEqual(goal.fatG, 0)
    }
}
