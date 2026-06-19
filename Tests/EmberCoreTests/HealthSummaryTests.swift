import XCTest
@testable import EmberCore

final class HealthSummaryTests: XCTestCase {

    // A fixed, far-from-DST-edge anchor; offsets within a day stay on the same local day.
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// A sample `daysAfter` whole days from `t0`, optionally nudged by `hours` within that day.
    private func sample(_ daysAfter: Double, _ value: Double, hours: Double = 0) -> HealthQuantitySample {
        HealthQuantitySample(date: t0.addingTimeInterval(daysAfter * 86_400 + hours * 3_600), value: value)
    }

    private func dayKey(_ daysAfter: Double) -> String {
        DayKey.key(for: t0.addingTimeInterval(daysAfter * 86_400))
    }

    // MARK: dailyTotals

    func testDailyTotalsSumsPerDayNewestFirst() {
        // Day 0: 100 + 50 ; day 2: 200 ; day 1: 30 + 70. Two samples per same day must sum.
        let samples = [
            sample(0, 100, hours: 1), sample(0, 50, hours: 3),
            sample(2, 200, hours: 2),
            sample(1, 30, hours: 1), sample(1, 70, hours: 5),
        ]
        let totals = HealthSummary.dailyTotals(samples)
        // Sorted newest day first by dayKey descending: day2, day1, day0.
        XCTAssertEqual(totals, [
            DailyTotal(dayKey: dayKey(2), total: 200),
            DailyTotal(dayKey: dayKey(1), total: 100),
            DailyTotal(dayKey: dayKey(0), total: 150),
        ])
    }

    func testDailyTotalsEmptyIsEmpty() {
        XCTAssertEqual(HealthSummary.dailyTotals([]), [])
    }

    func testDailyTotalsSingleDay() {
        let totals = HealthSummary.dailyTotals([sample(0, 7), sample(0, 3, hours: 2)])
        XCTAssertEqual(totals, [DailyTotal(dayKey: dayKey(0), total: 10)])
    }

    // MARK: latestAndAverage

    func testLatestAndAverageNewestValueAndMean() {
        // Out-of-order input; newest is the day-2 sample (value 70). Mean = (50+60+70)/3 = 60.
        let result = HealthSummary.latestAndAverage([sample(0, 50), sample(2, 70), sample(1, 60)])
        XCTAssertEqual(result.latest, 70)
        XCTAssertEqual(result.average, 60)
        XCTAssertEqual(result.count, 3)
    }

    func testLatestAndAverageEmpty() {
        let result = HealthSummary.latestAndAverage([])
        XCTAssertNil(result.latest)
        XCTAssertNil(result.average)
        XCTAssertEqual(result.count, 0)
    }

    func testLatestAndAverageSingleSample() {
        let result = HealthSummary.latestAndAverage([sample(0, 55)])
        XCTAssertEqual(result.latest, 55)
        XCTAssertEqual(result.average, 55)
        XCTAssertEqual(result.count, 1)
    }

    // MARK: averageDailyTotal

    func testAverageDailyTotalMean() {
        let totals = [
            DailyTotal(dayKey: "2026-06-18", total: 100),
            DailyTotal(dayKey: "2026-06-17", total: 200),
            DailyTotal(dayKey: "2026-06-16", total: 300),
        ]
        XCTAssertEqual(HealthSummary.averageDailyTotal(totals), 200)
    }

    func testAverageDailyTotalEmptyIsNil() {
        XCTAssertNil(HealthSummary.averageDailyTotal([]))
    }

    // MARK: minMaxAverage

    func testMinMaxAverageMultiSample() {
        // Out-of-order input. min 50, max 90, mean = (50+90+70+60)/4 = 67.5, count 4.
        let result = HealthSummary.minMaxAverage([sample(0, 70), sample(2, 90), sample(1, 50), sample(3, 60)])
        XCTAssertEqual(result.min, 50)
        XCTAssertEqual(result.max, 90)
        XCTAssertEqual(result.average, 67.5)
        XCTAssertEqual(result.count, 4)
    }

    func testMinMaxAverageEmpty() {
        let result = HealthSummary.minMaxAverage([])
        XCTAssertNil(result.min)
        XCTAssertNil(result.max)
        XCTAssertNil(result.average)
        XCTAssertEqual(result.count, 0)
    }

    func testMinMaxAverageSingleSample() {
        let result = HealthSummary.minMaxAverage([sample(0, 72)])
        XCTAssertEqual(result.min, 72)
        XCTAssertEqual(result.max, 72)
        XCTAssertEqual(result.average, 72)
        XCTAssertEqual(result.count, 1)
    }

    // MARK: distance-style daily rollup (km values, same primitives)

    func testDistanceRollupPerDayTotalsAndAveragePerDay() {
        // Day 0: 2.5 + 1.0 = 3.5 km ; day 1: 4.5 km (two walks on day 0 must sum).
        let walks = [
            sample(0, 2.5, hours: 1), sample(0, 1.0, hours: 6),
            sample(1, 3.0, hours: 2), sample(1, 1.5, hours: 7),
        ]
        let totals = HealthSummary.dailyTotals(walks)
        XCTAssertEqual(totals, [
            DailyTotal(dayKey: dayKey(1), total: 4.5),
            DailyTotal(dayKey: dayKey(0), total: 3.5),
        ])
        // Avg per day = (3.5 + 4.5) / 2 = 4.0 km.
        XCTAssertEqual(HealthSummary.averageDailyTotal(totals), 4.0)
    }

    // MARK: mindful-minutes daily rollup (same primitives serve mindfulness)

    func testMindfulMinutesRollupPerDayTotalsAndAveragePerDay() {
        // Day 0: 10 + 5 = 15 min ; day 1: 20 min (two sessions on day 0 must sum).
        let sessions = [
            sample(0, 10, hours: 1), sample(0, 5, hours: 8),
            sample(1, 20, hours: 2),
        ]
        let totals = HealthSummary.dailyTotals(sessions)
        XCTAssertEqual(totals, [
            DailyTotal(dayKey: dayKey(1), total: 20),
            DailyTotal(dayKey: dayKey(0), total: 15),
        ])
        // Avg per day = (15 + 20) / 2 = 17.5 min.
        XCTAssertEqual(HealthSummary.averageDailyTotal(totals), 17.5)
    }

    // MARK: blood-oxygen-style latest+average (same primitives serve SpO₂ %)

    func testLatestAndAverageBloodOxygenPercent() {
        // SpO₂ % values; newest is the day-2 sample (98). Mean = (97+99+98)/3 = 98.
        let result = HealthSummary.latestAndAverage([sample(0, 97), sample(2, 98), sample(1, 99)])
        XCTAssertEqual(result.latest, 98)
        XCTAssertEqual(result.average, 98)
        XCTAssertEqual(result.count, 3)
    }

    // MARK: sleep-style rollup (same primitives serve sleep)

    func testSleepRollupPerNightTotalsAndAveragePerNight() {
        // Two nights of "asleep minutes" samples (e.g. core + deep + REM segments).
        let nights = [
            sample(0, 180, hours: 1), sample(0, 120, hours: 3),   // night 0: 300 min
            sample(1, 200, hours: 1), sample(1, 220, hours: 4),   // night 1: 420 min
        ]
        let totals = HealthSummary.dailyTotals(nights)
        XCTAssertEqual(totals, [
            DailyTotal(dayKey: dayKey(1), total: 420),
            DailyTotal(dayKey: dayKey(0), total: 300),
        ])
        // Avg per night = (300 + 420) / 2 = 360 min.
        XCTAssertEqual(HealthSummary.averageDailyTotal(totals), 360)
    }
}
