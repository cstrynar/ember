import Foundation

/// Utility for mapping `Date` values to local-calendar day keys (yyyy-MM-dd strings).
/// A day key is stable within a single local calendar day and changes at local midnight.
public enum DayKey {
    /// The date formatter used to produce day keys — local timezone, fixed format.
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        // Uses the device's current time zone by default (DateFormatter default).
        return f
    }()

    /// Returns the day key string (yyyy-MM-dd) for the given date in the local timezone.
    public static func key(for date: Date, calendar: Calendar = .current) -> String {
        // We use Calendar to extract components and then re-format to ensure
        // the key is purely a local-day identity — independent of DST edge cases.
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        guard
            let year = comps.year,
            let month = comps.month,
            let day = comps.day
        else {
            // Fallback: format directly (should never happen for valid dates).
            return formatter.string(from: date)
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Returns true if `a` and `b` fall on the same local calendar day.
    public static func sameDay(_ a: Date, _ b: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }
}
