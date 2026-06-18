import Foundation

/// An in-memory, searchable collection of foods (preloaded + the user's custom items).
public struct FoodDatabase {
    public let items: [FoodItem]

    public init(items: [FoodItem]) {
        self.items = items
    }

    /// Looks up a food by id.
    public func item(id: String) -> FoodItem? {
        items.first { $0.id == id }
    }

    /// Case-insensitive name search. Ranking: exact match, then prefix, then substring;
    /// ties broken by shorter (more specific) name. An empty query returns `[]`.
    public func search(_ query: String, limit: Int = 25) -> [FoodItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        func rank(_ name: String) -> Int? {
            let n = name.lowercased()
            if n == q { return 0 }
            if n.hasPrefix(q) { return 1 }
            if n.contains(q) { return 2 }
            return nil
        }

        return items
            .compactMap { item -> (item: FoodItem, rank: Int)? in
                guard let r = rank(item.name) else { return nil }
                return (item, r)
            }
            .sorted { a, b in
                if a.rank != b.rank { return a.rank < b.rank }
                if a.item.name.count != b.item.name.count { return a.item.name.count < b.item.name.count }
                return a.item.name < b.item.name
            }
            .prefix(limit)
            .map { $0.item }
    }

    /// A new database with custom items merged in (custom overrides preloaded on matching id).
    public func merging(custom: [FoodItem]) -> FoodDatabase {
        var byID: [String: FoodItem] = [:]
        for item in items { byID[item.id] = item }
        for item in custom { byID[item.id] = item }
        return FoodDatabase(items: Array(byID.values))
    }

    // MARK: - Preloaded data

    /// Loads the bundled preloaded food list. Returns an empty database if the resource
    /// is missing or unreadable (the app still works; the user can add custom foods).
    public static func loadPreloaded() -> FoodDatabase {
        guard
            let url = Bundle.module.url(forResource: "preloaded-foods", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let records = try? JSONDecoder().decode([PreloadedFood].self, from: data)
        else {
            return FoodDatabase(items: [])
        }
        return FoodDatabase(items: records.map { $0.asFoodItem })
    }
}

/// On-disk schema for `preloaded-foods.json` — flat and easy to hand-edit or extend.
/// Decoupled from `FoodItem` so the data file stays compact and diff-friendly.
struct PreloadedFood: Codable, Equatable {
    let id: String
    let name: String
    let serving: String
    let kcal: Double
    let protein: Double
    let carb: Double
    let fat: Double

    var asFoodItem: FoodItem {
        FoodItem(
            id: id,
            name: name,
            servingDescription: serving,
            macrosPerServing: Macros(calories: kcal, proteinG: protein, carbG: carb, fatG: fat),
            source: .preloaded
        )
    }
}
