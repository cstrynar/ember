import Foundation

/// The four numbers Ember tracks everywhere: energy and the three macronutrients.
/// Used as the common currency for food items, logged entries, daily totals, and goals.
public struct Macros: Codable, Equatable {
    public var calories: Double
    public var proteinG: Double
    public var carbG: Double
    public var fatG: Double

    public init(calories: Double, proteinG: Double, carbG: Double, fatG: Double) {
        self.calories = calories
        self.proteinG = proteinG
        self.carbG = carbG
        self.fatG = fatG
    }

    public static let zero = Macros(calories: 0, proteinG: 0, carbG: 0, fatG: 0)

    public static func + (lhs: Macros, rhs: Macros) -> Macros {
        Macros(calories: lhs.calories + rhs.calories,
               proteinG: lhs.proteinG + rhs.proteinG,
               carbG: lhs.carbG + rhs.carbG,
               fatG: lhs.fatG + rhs.fatG)
    }

    public static func - (lhs: Macros, rhs: Macros) -> Macros {
        Macros(calories: lhs.calories - rhs.calories,
               proteinG: lhs.proteinG - rhs.proteinG,
               carbG: lhs.carbG - rhs.carbG,
               fatG: lhs.fatG - rhs.fatG)
    }

    /// Scales every component by `factor` (e.g. number of servings).
    public func scaled(by factor: Double) -> Macros {
        Macros(calories: calories * factor,
               proteinG: proteinG * factor,
               carbG: carbG * factor,
               fatG: fatG * factor)
    }

    /// A copy with each component rounded to whole numbers (for display and goals).
    public func rounded() -> Macros {
        Macros(calories: calories.rounded(),
               proteinG: proteinG.rounded(),
               carbG: carbG.rounded(),
               fatG: fatG.rounded())
    }

    /// Energy implied by the macronutrients (4/4/9 kcal per gram). Handy for sanity checks;
    /// it can differ slightly from `calories` due to rounding and labeling conventions.
    public var caloriesFromMacros: Double {
        proteinG * 4 + carbG * 4 + fatG * 9
    }
}
