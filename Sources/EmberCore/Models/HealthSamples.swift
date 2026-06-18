import Foundation

/// A body-mass sample read from Apple Health, mapped to a plain value type so EmberCore
/// stays HealthKit-free. The App layer maps `HKQuantitySample(.bodyMass)` to this.
public struct HealthWeightSample: Codable, Equatable {
    /// When the sample was recorded.
    public let date: Date
    /// Body mass in kilograms.
    public let weightKg: Double

    public init(date: Date, weightKg: Double) {
        self.date = date
        self.weightKg = weightKg
    }
}

/// A workout session read from Apple Health (e.g. an Apple-Watch-recorded session). Apple
/// records a summary — type, date, duration, energy — not per-exercise sets/reps, so this
/// is a distinct, additive record (NOT a `Workout` with synthetic sets). Mapped to a plain
/// value type so EmberCore stays HealthKit-free.
public struct HealthWorkout: Codable, Equatable, Identifiable {
    /// Stable identity — the HealthKit sample UUID string on device, or a synthesized key in tests.
    public let id: String
    /// The local-calendar day key (yyyy-MM-dd) the session started on.
    public let dayKey: String
    /// When the session started.
    public let date: Date
    /// A human-readable activity name, e.g. "Functional Strength Training".
    public let kind: String
    /// Session duration in minutes.
    public let durationMin: Double
    /// The session's own active energy in kilocalories, if Apple recorded it.
    public let activeEnergyKcal: Double?

    public init(id: String, dayKey: String, date: Date, kind: String,
                durationMin: Double, activeEnergyKcal: Double?) {
        self.id = id
        self.dayKey = dayKey
        self.date = date
        self.kind = kind
        self.durationMin = durationMin
        self.activeEnergyKcal = activeEnergyKcal
    }
}
