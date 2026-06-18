import Foundation

public enum Meal: String, Codable, Equatable, CaseIterable {
    case breakfast, lunch, dinner, snack
}

/// One logged food. Snapshots the per-serving macros so history stays correct even if the
/// underlying `FoodItem` is later edited or deleted.
public struct FoodEntry: Codable, Equatable, Identifiable {
    public let id: UUID
    public let dayKey: String
    public let loggedAt: Date
    public var foodID: String?
    public var name: String
    public var servings: Double
    public var macrosPerServing: Macros
    public var meal: Meal

    public init(id: UUID = UUID(), dayKey: String, loggedAt: Date = Date(),
                foodID: String? = nil, name: String, servings: Double,
                macrosPerServing: Macros, meal: Meal) {
        self.id = id
        self.dayKey = dayKey
        self.loggedAt = loggedAt
        self.foodID = foodID
        self.name = name
        self.servings = servings
        self.macrosPerServing = macrosPerServing
        self.meal = meal
    }

    /// Convenience: log a known `FoodItem`.
    public init(food: FoodItem, dayKey: String, servings: Double, meal: Meal,
                id: UUID = UUID(), loggedAt: Date = Date()) {
        self.init(id: id, dayKey: dayKey, loggedAt: loggedAt, foodID: food.id,
                  name: food.name, servings: servings,
                  macrosPerServing: food.macrosPerServing, meal: meal)
    }

    /// Macros actually consumed (per-serving × servings).
    public var consumed: Macros { macrosPerServing.scaled(by: servings) }
}
