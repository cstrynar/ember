import Foundation

/// Pure workout analytics: estimated 1RM, volume, and per-exercise progress series.
public enum WorkoutProgress {

    /// A distinct exercise that appears in workout history.
    public struct ExerciseRef: Equatable, Identifiable {
        public let id: String
        public let name: String
        public init(id: String, name: String) { self.id = id; self.name = name }
    }

    /// A single point in a progress series (one workout day).
    public struct Point: Equatable, Identifiable {
        public let id: String       // dayKey (unique per workout)
        public let date: Date
        public let value: Double
        public init(id: String, date: Date, value: Double) {
            self.id = id; self.date = date; self.value = value
        }
        public var dayKey: String { id }
    }

    /// Epley estimated one-rep max. Returns the weight directly for a single rep, 0 for
    /// non-positive reps/weight.
    public static func estimatedOneRepMax(weightKg: Double, reps: Int) -> Double {
        guard reps > 0, weightKg > 0 else { return 0 }
        return reps == 1 ? weightKg : weightKg * (1 + Double(reps) / 30.0)
    }

    public static func estimatedOneRepMax(_ set: LoggedSet) -> Double {
        estimatedOneRepMax(weightKg: set.weightKg, reps: set.reps)
    }

    /// Total tonnage (Σ reps × weight) for a list of sets.
    public static func volume(of sets: [LoggedSet]) -> Double {
        sets.reduce(0) { $0 + $1.weightKg * Double($1.reps) }
    }

    /// Best estimated 1RM across the sets of `exerciseID` in a single workout.
    public static func bestOneRepMax(exerciseID: String, in workout: Workout) -> Double {
        workout.sets(for: exerciseID).map(estimatedOneRepMax).max() ?? 0
    }

    /// Estimated-1RM series for an exercise across all workouts, oldest first.
    public static func oneRepMaxHistory(exerciseID: String, in workouts: [Workout]) -> [Point] {
        workouts.compactMap { w -> Point? in
            let sets = w.sets(for: exerciseID)
            guard !sets.isEmpty else { return nil }
            return Point(id: w.dayKey, date: w.date, value: sets.map(estimatedOneRepMax).max() ?? 0)
        }
        .sorted { $0.date < $1.date }
    }

    /// Volume series for an exercise across all workouts, oldest first.
    public static func volumeHistory(exerciseID: String, in workouts: [Workout]) -> [Point] {
        workouts.compactMap { w -> Point? in
            let sets = w.sets(for: exerciseID)
            guard !sets.isEmpty else { return nil }
            return Point(id: w.dayKey, date: w.date, value: volume(of: sets))
        }
        .sorted { $0.date < $1.date }
    }

    /// Distinct exercises seen across all workouts, alphabetical by name.
    public static func distinctExercises(in workouts: [Workout]) -> [ExerciseRef] {
        var nameByID: [String: String] = [:]
        for w in workouts {
            for set in w.sets { nameByID[set.exerciseID] = set.exerciseName }
        }
        return nameByID
            .map { ExerciseRef(id: $0.key, name: $0.value) }
            .sorted { $0.name < $1.name }
    }
}
