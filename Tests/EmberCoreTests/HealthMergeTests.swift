import XCTest
@testable import EmberCore

final class HealthMergeTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func weight(_ daysAfter: Double, _ kg: Double) -> HealthWeightSample {
        HealthWeightSample(date: t0.addingTimeInterval(daysAfter * 86_400), weightKg: kg)
    }

    private func workout(_ id: String, _ daysAfter: Double) -> HealthWorkout {
        let date = t0.addingTimeInterval(daysAfter * 86_400)
        return HealthWorkout(id: id, dayKey: "d\(Int(daysAfter))", date: date,
                             kind: "Functional Strength Training", durationMin: 42,
                             activeEnergyKcal: 310)
    }

    private func set(_ ex: String, _ reps: Int, _ wt: Double) -> LoggedSet {
        LoggedSet(exerciseID: ex, exerciseName: ex.capitalized, reps: reps, weightKg: wt)
    }

    // MARK: currentWeightKg

    func testWeightHealthPresentMostRecentWins() {
        // Newest Health sample (88 kg) wins over an older sample (90 kg) and over manual (95).
        let health = [weight(0, 90), weight(2, 88), weight(1, 89)]
        XCTAssertEqual(HealthMerge.currentWeightKg(health: health, manual: 95), 88)
    }

    func testWeightHealthEmptyUsesManual() {
        XCTAssertEqual(HealthMerge.currentWeightKg(health: [], manual: 82), 82)
    }

    func testWeightHealthEmptyAndManualNilIsNil() {
        XCTAssertNil(HealthMerge.currentWeightKg(health: [], manual: nil))
    }

    // MARK: mergedWorkouts

    func testWorkoutsHealthPresentNonEmptyAndNewestFirst() {
        let manual = [Workout(dayKey: "m1", date: t0, sets: [set("squat", 5, 100)])]
        let health = [workout("a", 0), workout("b", 2), workout("c", 1)]
        let merged = HealthMerge.mergedWorkouts(manual: manual, health: health)
        XCTAssertEqual(merged.health.map(\.id), ["b", "c", "a"]) // newest (day 2) first
        // Manual passes through byte-for-byte (charts unaffected).
        XCTAssertEqual(merged.manual, manual)
    }

    func testWorkoutsHealthEmptyPassesManualThrough() {
        let manual = [Workout(dayKey: "m1", date: t0, sets: [set("bench", 5, 80)])]
        let merged = HealthMerge.mergedWorkouts(manual: manual, health: [])
        XCTAssertTrue(merged.health.isEmpty)
        XCTAssertEqual(merged.manual, manual)
    }

    func testWorkoutsBothPresentManualUnchangedAndHealthSurfaced() {
        let manual = [Workout(dayKey: "m1", date: t0, sets: [set("squat", 5, 100)])]
        let health = [workout("a", 1)]
        let merged = HealthMerge.mergedWorkouts(manual: manual, health: health)
        XCTAssertEqual(merged.manual, manual)
        XCTAssertEqual(merged.health.map(\.id), ["a"])
    }

    func testWorkoutsDedupesById() {
        let manual: [Workout] = []
        let health = [workout("dup", 1), workout("dup", 3), workout("other", 2)]
        let merged = HealthMerge.mergedWorkouts(manual: manual, health: health)
        // Only the first "dup" survives dedup; sorted newest-first: dup(day1) vs other(day2).
        XCTAssertEqual(merged.health.map(\.id), ["other", "dup"])
        XCTAssertEqual(merged.health.count, 2)
    }

    func testWorkoutsSortedByDateDescending() {
        let health = [workout("a", 0), workout("b", 5), workout("c", 3)]
        let merged = HealthMerge.mergedWorkouts(manual: [], health: health)
        let dates = merged.health.map(\.date)
        XCTAssertEqual(dates, dates.sorted(by: >))
    }
}
