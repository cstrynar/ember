import Foundation

public enum ExerciseCategory: String, Codable, Equatable, CaseIterable {
    case strength, cardio, mobility
}

/// A named exercise the user can log sets against.
public struct Exercise: Codable, Equatable, Identifiable {
    public let id: String
    public var name: String
    public var category: ExerciseCategory

    public init(id: String, name: String, category: ExerciseCategory) {
        self.id = id
        self.name = name
        self.category = category
    }
}

/// A small built-in catalog of common exercises plus name search. Users can add custom
/// exercises, which the app merges on top of this list.
public enum ExerciseCatalog {

    public static let `default`: [Exercise] = [
        ex("Back Squat", .strength),
        ex("Front Squat", .strength),
        ex("Deadlift", .strength),
        ex("Romanian Deadlift", .strength),
        ex("Bench Press", .strength),
        ex("Incline Bench Press", .strength),
        ex("Dumbbell Bench Press", .strength),
        ex("Overhead Press", .strength),
        ex("Dumbbell Shoulder Press", .strength),
        ex("Lateral Raise", .strength),
        ex("Barbell Row", .strength),
        ex("Dumbbell Row", .strength),
        ex("Seated Cable Row", .strength),
        ex("Lat Pulldown", .strength),
        ex("Pull-up", .strength),
        ex("Chin-up", .strength),
        ex("Face Pull", .strength),
        ex("Barbell Curl", .strength),
        ex("Dumbbell Curl", .strength),
        ex("Tricep Pushdown", .strength),
        ex("Leg Press", .strength),
        ex("Leg Extension", .strength),
        ex("Leg Curl", .strength),
        ex("Calf Raise", .strength),
        ex("Walking Lunge", .strength),
        ex("Hip Thrust", .strength),
        ex("Push-up", .strength),
        ex("Plank", .mobility),
        ex("Running", .cardio),
        ex("Cycling", .cardio),
        ex("Rowing Machine", .cardio),
    ]

    /// Case-insensitive name search (exact → prefix → contains), shortest-name tie-break.
    public static func search(_ query: String, in list: [Exercise], limit: Int = 25) -> [Exercise] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return list }

        func rank(_ name: String) -> Int? {
            let n = name.lowercased()
            if n == q { return 0 }
            if n.hasPrefix(q) { return 1 }
            if n.contains(q) { return 2 }
            return nil
        }

        return list
            .compactMap { item -> (item: Exercise, rank: Int)? in
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

    /// Slug an arbitrary exercise name into a stable id.
    public static func slug(_ name: String) -> String {
        let lowered = name.lowercased()
        let mapped = lowered.map { ch -> Character in
            (ch.isLetter || ch.isNumber) ? ch : "_"
        }
        let collapsed = String(mapped).split(separator: "_").joined(separator: "_")
        return collapsed
    }

    private static func ex(_ name: String, _ category: ExerciseCategory) -> Exercise {
        Exercise(id: slug(name), name: name, category: category)
    }
}
