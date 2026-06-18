import Foundation

/// A day's hydration total, in milliliters. Clamped non-negative.
public struct HydrationLog: Codable, Equatable {
    public let dayKey: String
    public private(set) var milliliters: Int

    public init(dayKey: String, milliliters: Int = 0) {
        self.dayKey = dayKey
        self.milliliters = max(0, milliliters)
    }

    /// Returns a copy with `ml` added (or removed, if negative); never drops below zero.
    public func adding(_ ml: Int) -> HydrationLog {
        HydrationLog(dayKey: dayKey, milliliters: milliliters + ml)
    }
}
