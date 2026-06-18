import Foundation

/// The result of merging manual workouts with Apple Health workout summaries. The manual
/// list is passed through unchanged so per-exercise `WorkoutProgress` charts keep reading
/// real `LoggedSet` data; the Health list is a parallel, read-only summary surfaced alongside.
public struct MergedWorkoutHistory: Equatable {
    /// Manually logged workouts, byte-for-byte as passed in (the charts read only these).
    public let manual: [Workout]
    /// Apple Health workout summaries, deduped by `id` and sorted newest-first.
    public let health: [HealthWorkout]

    public init(manual: [Workout], health: [HealthWorkout]) {
        self.manual = manual
        self.health = health
    }
}

/// Pure prefer-Health-else-manual selection/merge helpers for weight and workouts. Imports
/// no HealthKit — the App layer maps `HKSample`s to the value types these operate on.
public enum HealthMerge {

    /// The user's current weight: the most-recent Health body-mass sample (max by `date`)
    /// when any exist, else the manual profile weight (which may itself be `nil`).
    public static func currentWeightKg(health: [HealthWeightSample], manual: Double?) -> Double? {
        guard let latest = health.max(by: { $0.date < $1.date }) else { return manual }
        return latest.weightKg
    }

    /// Merges manual workouts with Apple Health workout summaries. Manual workouts pass
    /// through unchanged; Health workouts are deduped by `id` and sorted newest-first. Both
    /// are surfaced as separate row kinds, so the per-exercise charts (which read only the
    /// manual list) are never affected. Health empty → `health` is `[]` and only manual shows.
    public static func mergedWorkouts(manual: [Workout], health: [HealthWorkout]) -> MergedWorkoutHistory {
        var seen = Set<String>()
        var deduped: [HealthWorkout] = []
        for workout in health where seen.insert(workout.id).inserted {
            deduped.append(workout)
        }
        deduped.sort { $0.date > $1.date }
        return MergedWorkoutHistory(manual: manual, health: deduped)
    }
}
