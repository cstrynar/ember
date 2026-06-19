import Foundation

/// A generic timestamped scalar read from Apple Health, mapped to a plain value type so
/// EmberCore stays HealthKit-free. The App layer maps an `HKQuantitySample` (or an "asleep"
/// `HKCategorySample`'s duration) to this.
///
/// `value`'s unit is metric-per-caller — kilocalories for active energy, a count for steps,
/// beats-per-minute for resting heart rate, and minutes for asleep duration. The summary
/// functions in `HealthSummary` interpret `value` according to the metric they're given.
public struct HealthQuantitySample: Codable, Equatable {
    /// When the sample was recorded (the sample's start date for ranged samples).
    public let date: Date
    /// The scalar value in the caller's metric unit (kcal / steps / bpm / asleep-minutes).
    public let value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}
