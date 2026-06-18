import XCTest
@testable import EmberCore

final class ReminderSettingsTests: XCTestCase {

    func testDefaultHasMealAndHydrationReminders() {
        let s = ReminderSettings.default
        XCTAssertEqual(s.reminders.count, 6)
        XCTAssertTrue(s.reminders.contains { $0.id == "meal.breakfast" })
        XCTAssertTrue(s.reminders.contains { $0.id == "hydration.morning" })
    }

    func testEnabledRemindersFilters() {
        var s = ReminderSettings.default
        s.reminders[0].enabled = false
        XCTAssertEqual(s.enabledReminders.count, 5)
        XCTAssertFalse(s.enabledReminders.contains { $0.id == s.reminders[0].id })
    }

    func testTimeString() {
        let r = DailyReminder(id: "x", label: "L", hour: 8, minute: 5)
        XCTAssertEqual(r.timeString, "08:05")
    }

    func testCodableRoundTrip() throws {
        let s = ReminderSettings.default
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(ReminderSettings.self, from: data)
        XCTAssertEqual(decoded, s)
    }
}
