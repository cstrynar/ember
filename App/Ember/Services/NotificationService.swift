import Foundation
import UserNotifications
import EmberCore

/// Schedules Ember's recurring daily reminders as local notifications.
///
/// Design:
/// - Permission is requested lazily, non-blockingly. The app is fully usable if denied —
///   the user just won't receive reminders.
/// - `sync` is the single entry point: it clears Ember's pending notifications and
///   re-adds one repeating daily trigger per enabled reminder, keyed by stable id.
/// - Local notifications only — no remote push, no network.
@MainActor
final class NotificationService {

    private let center = UNUserNotificationCenter.current()
    private let idPrefix = "ember."

    // MARK: - Permission

    /// Requests notification permission if not yet determined. Non-blocking either way.
    func requestPermissionIfNeeded() {
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            guard settings.authorizationStatus == .notDetermined else { return }
            self.center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    // MARK: - Scheduling

    /// Replaces all Ember reminders with the currently-enabled set (repeating daily).
    func sync(_ settings: ReminderSettings) {
        let enabled = settings.enabledReminders
        center.getPendingNotificationRequests { [weak self] existing in
            guard let self else { return }
            let staleIDs = existing.map { $0.identifier }.filter { $0.hasPrefix(self.idPrefix) }
            self.center.removePendingNotificationRequests(withIdentifiers: staleIDs)
            Task { @MainActor in
                for reminder in enabled { self.schedule(reminder) }
            }
        }
    }

    // MARK: - Private

    private func schedule(_ reminder: DailyReminder) {
        let content = UNMutableNotificationContent()
        content.title = "Ember"
        content.body = reminder.label
        content.sound = .default

        var comps = DateComponents()
        comps.hour = reminder.hour
        comps.minute = reminder.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)

        let request = UNNotificationRequest(
            identifier: idPrefix + reminder.id,
            content: content,
            trigger: trigger
        )
        center.add(request) { _ in }
    }
}
