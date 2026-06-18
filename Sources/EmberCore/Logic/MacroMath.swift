import Foundation

/// Deterministic macro-target math: Mifflin–St Jeor BMR → activity-adjusted TDEE →
/// goal-adjusted calories → a macro split driven by the chosen dietary pattern.
///
/// Numbers are intentionally simple and documented so they're easy to test and tweak.
/// This is general fitness math, not medical or clinical advice.
public enum MacroMath {

    // MARK: - Tunable constants

    /// Calorie adjustments applied to TDEE per goal.
    public static let loseDeficit: Double = 500
    public static let gainSurplus: Double = 350
    /// Floor to avoid recommending an unsafely low intake.
    public static let minimumCalories: Double = 1200

    // MARK: - Energy

    /// Mifflin–St Jeor basal metabolic rate (kcal/day).
    public static func basalMetabolicRate(profile: UserProfile) -> Double {
        let base = 10 * profile.weightKg + 6.25 * profile.heightCm - 5 * Double(profile.age)
        switch profile.sex {
        case .male:   return base + 5
        case .female: return base - 161
        }
    }

    /// Total daily energy expenditure (kcal/day).
    public static func totalDailyEnergyExpenditure(profile: UserProfile) -> Double {
        basalMetabolicRate(profile: profile) * profile.activity.multiplier
    }

    /// Goal-adjusted daily calorie target (kcal/day), floored at `minimumCalories`.
    public static func goalCalories(profile: UserProfile) -> Double {
        let tdee = totalDailyEnergyExpenditure(profile: profile)
        let adjusted: Double
        switch profile.goal {
        case .lose:     adjusted = tdee - loseDeficit
        case .maintain: adjusted = tdee
        case .gain:     adjusted = tdee + gainSurplus
        }
        return max(minimumCalories, adjusted)
    }

    // MARK: - Macro split

    /// Grams of protein per kg bodyweight, by dietary pattern.
    private static func proteinPerKg(_ pattern: DietaryPattern) -> Double {
        switch pattern {
        case .balanced:    return 1.6
        case .highProtein: return 2.2
        case .lowCarb:     return 2.0
        case .keto:        return 1.8
        }
    }

    /// Recommended daily macro goal for the profile.
    ///
    /// Protein is set per bodyweight; the calories left after protein are split between
    /// carbs and fat by pattern (so carbs/fat can never go negative). Grams are rounded.
    public static func recommendedGoal(profile: UserProfile) -> Macros {
        let calories = goalCalories(profile: profile)
        let proteinG = (proteinPerKg(profile.dietaryPattern) * profile.weightKg).rounded()
        let proteinKcal = proteinG * 4
        let remaining = max(0, calories - proteinKcal)

        let carbKcal: Double
        switch profile.dietaryPattern {
        case .balanced:    carbKcal = remaining * 0.55
        case .highProtein: carbKcal = remaining * 0.50
        case .lowCarb:     carbKcal = remaining * 0.25
        case .keto:        carbKcal = min(100, remaining) // ~25 g carb cap
        }
        let fatKcal = remaining - carbKcal

        return Macros(
            calories: calories.rounded(),
            proteinG: proteinG,
            carbG: (carbKcal / 4).rounded(),
            fatG: (fatKcal / 9).rounded()
        )
    }
}
