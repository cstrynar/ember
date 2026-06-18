import Foundation

/// A food the user logged recently, in a form that can be re-logged with one tap.
/// Snapshots per-serving macros so it stays loggable even if the source food is gone.
public struct RecentFood: Equatable, Identifiable {
    public let name: String
    public let foodID: String?
    public let macrosPerServing: Macros
    public let lastLoggedAt: Date
    /// Servings + meal from the newest logged entry, so a one-tap re-log reproduces it.
    public let lastServings: Double
    public let lastMeal: Meal

    /// Stable identity: the source food id when known, else the (lowercased) name.
    public var id: String { foodID ?? "name:\(name.lowercased())" }

    public init(name: String, foodID: String?, macrosPerServing: Macros, lastLoggedAt: Date,
                lastServings: Double, lastMeal: Meal) {
        self.name = name
        self.foodID = foodID
        self.macrosPerServing = macrosPerServing
        self.lastLoggedAt = lastLoggedAt
        self.lastServings = lastServings
        self.lastMeal = lastMeal
    }
}

/// Derives the user's most recently logged foods from their day history — pure, so the
/// "recent" list that powers quick-add is unit-tested rather than reconstructed in the UI.
public enum RecentFoods {
    /// Distinct foods most-recently logged across `days`, newest first. Two entries are the
    /// "same food" when they share a food id, or (lacking ids) a case-insensitive name.
    public static func from(_ days: [DayNutrition], limit: Int = 12) -> [RecentFood] {
        let entries = days.flatMap { $0.entries }.sorted { $0.loggedAt > $1.loggedAt }
        var seen = Set<String>()
        var result: [RecentFood] = []
        for entry in entries {
            let key = entry.foodID ?? "name:\(entry.name.lowercased())"
            guard seen.insert(key).inserted else { continue }
            result.append(RecentFood(name: entry.name, foodID: entry.foodID,
                                     macrosPerServing: entry.macrosPerServing,
                                     lastLoggedAt: entry.loggedAt,
                                     lastServings: entry.servings, lastMeal: entry.meal))
            if result.count >= limit { break }
        }
        return result
    }
}
