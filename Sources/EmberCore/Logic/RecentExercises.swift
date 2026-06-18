import Foundation

/// An exercise the user trained recently, in a form whose last set can be re-logged with one
/// tap. Snapshots that set's reps + weight so it stays loggable straight from history.
public struct RecentExercise: Equatable, Identifiable {
    public let exerciseID: String
    public let name: String
    public let lastReps: Int
    public let lastWeightKg: Double
    public let lastLoggedAt: Date

    /// Stable identity: the exercise id.
    public var id: String { exerciseID }

    public init(exerciseID: String, name: String, lastReps: Int, lastWeightKg: Double,
                lastLoggedAt: Date) {
        self.exerciseID = exerciseID
        self.name = name
        self.lastReps = lastReps
        self.lastWeightKg = lastWeightKg
        self.lastLoggedAt = lastLoggedAt
    }
}

/// Derives the user's most recently trained exercises from their workout history — pure, so
/// the "recent" list that powers quick-add is unit-tested rather than reconstructed in the UI.
public enum RecentExercises {
    /// Distinct exercises most-recently trained across `workouts`, newest first, deduped by
    /// `exerciseID`. The snapshot is the **last** matching set in the newest workout containing
    /// that exercise — the same set `AppModel.lastSet(forExerciseID:)` returns.
    public static func from(_ workouts: [Workout], limit: Int = 12) -> [RecentExercise] {
        let sorted = workouts.sorted { $0.date > $1.date }
        var seen = Set<String>()
        var result: [RecentExercise] = []
        for workout in sorted {
            for set in workout.sets {
                guard !seen.contains(set.exerciseID) else { continue }
                guard let last = workout.sets(for: set.exerciseID).last else { continue }
                seen.insert(set.exerciseID)
                result.append(RecentExercise(exerciseID: last.exerciseID, name: last.exerciseName,
                                             lastReps: last.reps, lastWeightKg: last.weightKg,
                                             lastLoggedAt: workout.date))
                if result.count >= limit { break }
            }
            if result.count >= limit { break }
        }
        return result
    }
}
