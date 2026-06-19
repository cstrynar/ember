import Foundation

/// A per-day rollup: a local-calendar day key (yyyy-MM-dd) and the summed value for that day.
public struct DailyTotal: Equatable {
    /// The local-calendar day key (yyyy-MM-dd).
    public let dayKey: String
    /// The sum of all sample values that fell on `dayKey`.
    public let total: Double

    public init(dayKey: String, total: Double) {
        self.dayKey = dayKey
        self.total = total
    }
}

/// The latest (newest-by-date) value, the mean across all samples, and the sample count.
/// `latest` / `average` are `nil` and `count` is `0` for an empty input.
public struct LatestAndAverage: Equatable {
    /// The value of the newest sample (max by `date`), or `nil` when empty.
    public let latest: Double?
    /// The mean of all sample values, or `nil` when empty.
    public let average: Double?
    /// The number of samples summarized.
    public let count: Int

    public init(latest: Double?, average: Double?, count: Int) {
        self.latest = latest
        self.average = average
        self.count = count
    }
}

/// Pure rollup helpers over `HealthQuantitySample` arrays. Imports no HealthKit — the App
/// layer maps `HKSample`s to the value types these operate on. Mirrors `HealthMerge` /
/// `MacroMath`: a stateless `enum` namespace of deterministic functions.
public enum HealthSummary {

    /// Groups samples by their local-calendar day (via `DayKey.key(for:)`), sums each day's
    /// values, and returns the daily totals sorted newest-day-first (by `dayKey` descending —
    /// yyyy-MM-dd keys are lexically sortable). Empty input → `[]`. Used for active energy,
    /// steps, and sleep (where each sample's value is asleep minutes).
    public static func dailyTotals(_ samples: [HealthQuantitySample]) -> [DailyTotal] {
        var totals: [String: Double] = [:]
        for sample in samples {
            let key = DayKey.key(for: sample.date)
            totals[key, default: 0] += sample.value
        }
        return totals
            .map { DailyTotal(dayKey: $0.key, total: $0.value) }
            .sorted { $0.dayKey > $1.dayKey }
    }

    /// The newest-by-date value, the mean of all values, and the count. Empty → `(nil, nil, 0)`.
    /// Used for resting heart rate (a point metric) and reusable for any point series.
    public static func latestAndAverage(_ samples: [HealthQuantitySample]) -> LatestAndAverage {
        guard !samples.isEmpty else { return LatestAndAverage(latest: nil, average: nil, count: 0) }
        let latest = samples.max(by: { $0.date < $1.date })?.value
        let average = samples.reduce(0) { $0 + $1.value } / Double(samples.count)
        return LatestAndAverage(latest: latest, average: average, count: samples.count)
    }

    /// The mean of a list of daily totals (e.g. avg steps/day, avg active kcal/day, avg
    /// sleep/night). Empty → `nil`.
    public static func averageDailyTotal(_ totals: [DailyTotal]) -> Double? {
        guard !totals.isEmpty else { return nil }
        return totals.reduce(0) { $0 + $1.total } / Double(totals.count)
    }
}
