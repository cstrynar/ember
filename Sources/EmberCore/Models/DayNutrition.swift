import Foundation

/// All food logged on a single local day.
public struct DayNutrition: Codable, Equatable {
    public let dayKey: String
    public var entries: [FoodEntry]

    public init(dayKey: String, entries: [FoodEntry] = []) {
        self.dayKey = dayKey
        self.entries = entries
    }

    public func appending(_ entry: FoodEntry) -> DayNutrition {
        DayNutrition(dayKey: dayKey, entries: entries + [entry])
    }

    public func removing(id: UUID) -> DayNutrition {
        DayNutrition(dayKey: dayKey, entries: entries.filter { $0.id != id })
    }

    /// Total macros consumed across all entries.
    public var consumed: Macros {
        entries.reduce(.zero) { $0 + $1.consumed }
    }

    /// Macros consumed for a single meal.
    public func consumed(for meal: Meal) -> Macros {
        entries.filter { $0.meal == meal }.reduce(.zero) { $0 + $1.consumed }
    }

    /// What's left against a goal. Components go negative once you're over.
    public func remaining(against goal: Macros) -> Macros {
        goal - consumed
    }
}
