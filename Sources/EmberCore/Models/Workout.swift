import Foundation

/// One logged set. Snapshots the exercise name so history survives catalog edits.
public struct LoggedSet: Codable, Equatable, Identifiable {
    public let id: UUID
    public var exerciseID: String
    public var exerciseName: String
    public var reps: Int
    public var weightKg: Double

    public init(id: UUID = UUID(), exerciseID: String, exerciseName: String,
                reps: Int, weightKg: Double) {
        self.id = id
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.reps = reps
        self.weightKg = weightKg
    }
}

/// All sets logged on a single local day, as a flat list (grouped by exercise for display).
public struct Workout: Codable, Equatable {
    public let dayKey: String
    public var date: Date
    public var sets: [LoggedSet]
    public var notes: String

    public init(dayKey: String, date: Date = Date(), sets: [LoggedSet] = [], notes: String = "") {
        self.dayKey = dayKey
        self.date = date
        self.sets = sets
        self.notes = notes
    }

    /// Sets belonging to one exercise, in logged order.
    public func sets(for exerciseID: String) -> [LoggedSet] {
        sets.filter { $0.exerciseID == exerciseID }
    }

    public var isEmpty: Bool { sets.isEmpty }
}
