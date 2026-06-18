import XCTest
@testable import EmberCore

final class DayKeyTests: XCTestCase {

    // A fixed calendar so tests are timezone-independent.
    private var utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0,
                          second: Int = 0, in calendar: Calendar) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        return calendar.date(from: comps)!
    }

    func testDateMapsToExpectedKey() {
        let date = makeDate(year: 2026, month: 6, day: 11, hour: 14, minute: 30, in: utcCalendar)
        let key = DayKey.key(for: date, calendar: utcCalendar)
        XCTAssertEqual(key, "2026-06-11")
    }

    func testTwoTimesInSameDayShareKey() {
        let morning = makeDate(year: 2026, month: 6, day: 11, hour: 8, minute: 0, in: utcCalendar)
        let evening = makeDate(year: 2026, month: 6, day: 11, hour: 22, minute: 59, in: utcCalendar)
        XCTAssertEqual(DayKey.key(for: morning, calendar: utcCalendar),
                       DayKey.key(for: evening, calendar: utcCalendar))
        XCTAssertTrue(DayKey.sameDay(morning, evening, calendar: utcCalendar))
    }

    func testCrossMidnightTimesDoNotShareKey() {
        let beforeMidnight = makeDate(year: 2026, month: 6, day: 11, hour: 23, minute: 59, second: 59, in: utcCalendar)
        let afterMidnight  = makeDate(year: 2026, month: 6, day: 12, hour: 0, minute: 0, second: 0, in: utcCalendar)
        XCTAssertNotEqual(DayKey.key(for: beforeMidnight, calendar: utcCalendar),
                          DayKey.key(for: afterMidnight, calendar: utcCalendar))
        XCTAssertFalse(DayKey.sameDay(beforeMidnight, afterMidnight, calendar: utcCalendar))
    }

    func testKeyFormatIsYyyyMmDd() {
        let date = makeDate(year: 2026, month: 1, day: 5, in: utcCalendar)
        let key = DayKey.key(for: date, calendar: utcCalendar)
        // Expect zero-padded month and day.
        XCTAssertEqual(key, "2026-01-05")
        XCTAssertEqual(key.count, 10)
    }

    func testDifferentCalendarDaysProduceDifferentKeys() {
        let day1 = makeDate(year: 2026, month: 6, day: 10, in: utcCalendar)
        let day2 = makeDate(year: 2026, month: 6, day: 11, in: utcCalendar)
        XCTAssertNotEqual(DayKey.key(for: day1, calendar: utcCalendar),
                          DayKey.key(for: day2, calendar: utcCalendar))
    }
}
