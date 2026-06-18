import Foundation

/// A single recurring daily reminder (a meal nudge or a hydration nudge).
/// Fires every day at `hour:minute` local time when `enabled`.
public struct DailyReminder: Codable, Equatable, Identifiable {
    /// Stable identity, e.g. "meal.breakfast" or "hydration.afternoon".
    public let id: String
    /// Notification body text.
    public var label: String
    public var hour: Int
    public var minute: Int
    public var enabled: Bool

    public init(id: String, label: String, hour: Int, minute: Int, enabled: Bool = true) {
        self.id = id
        self.label = label
        self.hour = hour
        self.minute = minute
        self.enabled = enabled
    }

    /// "HH:mm" for display.
    public var timeString: String {
        String(format: "%02d:%02d", hour, minute)
    }
}

/// The user's full set of recurring reminders. The coach can edit these via tools.
public struct ReminderSettings: Codable, Equatable {
    public var reminders: [DailyReminder]

    public init(reminders: [DailyReminder]) {
        self.reminders = reminders
    }

    /// Only the reminders that should currently be scheduled.
    public var enabledReminders: [DailyReminder] {
        reminders.filter { $0.enabled }
    }

    /// Sensible gentle defaults — three meals and three hydration nudges.
    public static let `default` = ReminderSettings(reminders: [
        DailyReminder(id: "meal.breakfast", label: "Breakfast time — fuel up and log it.", hour: 8,  minute: 0),
        DailyReminder(id: "meal.lunch",     label: "Lunch — log your meal when you can.",  hour: 12, minute: 30),
        DailyReminder(id: "meal.dinner",    label: "Dinner — round out your day's macros.", hour: 18, minute: 30),
        DailyReminder(id: "hydration.morning",   label: "Water break — have a glass.",       hour: 10, minute: 0),
        DailyReminder(id: "hydration.afternoon", label: "Hydration check — sip some water.", hour: 14, minute: 0),
        DailyReminder(id: "hydration.evening",   label: "One more glass of water today.",    hour: 16, minute: 30),
    ])
}
