import XCTest
@testable import EmberCore

final class WorkoutProgressTests: XCTestCase {

    private func set(_ ex: String, _ reps: Int, _ wt: Double) -> LoggedSet {
        LoggedSet(exerciseID: ex, exerciseName: ex.capitalized, reps: reps, weightKg: wt)
    }

    func testEpleyOneRepMax() {
        XCTAssertEqual(WorkoutProgress.estimatedOneRepMax(weightKg: 100, reps: 1), 100, accuracy: 0.001)
        XCTAssertEqual(WorkoutProgress.estimatedOneRepMax(weightKg: 100, reps: 5),
                       100 * (1 + 5 / 30.0), accuracy: 0.001)
        XCTAssertEqual(WorkoutProgress.estimatedOneRepMax(weightKg: 100, reps: 0), 0)
        XCTAssertEqual(WorkoutProgress.estimatedOneRepMax(weightKg: 0, reps: 5), 0)
    }

    func testVolume() {
        XCTAssertEqual(WorkoutProgress.volume(of: [set("bench", 5, 100), set("bench", 5, 100)]),
                       1000, accuracy: 0.001)
    }

    func testBestOneRepMax() {
        // 100×5 → ~116.7 ; 110×3 → 121 ; best is 121
        let w = Workout(dayKey: "d", sets: [set("bench", 5, 100), set("bench", 3, 110)])
        XCTAssertEqual(WorkoutProgress.bestOneRepMax(exerciseID: "bench", in: w), 121, accuracy: 0.001)
    }

    func testOneRepMaxHistorySortedByDate() {
        let d1 = Date(timeIntervalSince1970: 1000)
        let d2 = Date(timeIntervalSince1970: 2000)
        let w1 = Workout(dayKey: "2026-06-14", date: d1, sets: [set("bench", 5, 100)])
        let w2 = Workout(dayKey: "2026-06-15", date: d2, sets: [set("bench", 5, 110)])
        let hist = WorkoutProgress.oneRepMaxHistory(exerciseID: "bench", in: [w2, w1]) // unsorted
        XCTAssertEqual(hist.map { $0.dayKey }, ["2026-06-14", "2026-06-15"])
        XCTAssertEqual(hist.first?.value ?? 0, 100 * (1 + 5 / 30.0), accuracy: 0.001)
    }

    func testVolumeHistoryExcludesOtherExercises() {
        let w = Workout(dayKey: "d", date: Date(timeIntervalSince1970: 1),
                        sets: [set("bench", 5, 100), set("squat", 5, 140)])
        let v = WorkoutProgress.volumeHistory(exerciseID: "squat", in: [w])
        XCTAssertEqual(v.count, 1)
        XCTAssertEqual(v.first?.value ?? 0, 700, accuracy: 0.001)
    }

    func testDistinctExercisesAlphabetical() {
        let w1 = Workout(dayKey: "d1", sets: [set("bench", 5, 100)])
        let w2 = Workout(dayKey: "d2", sets: [set("squat", 5, 140), set("bench", 5, 105)])
        XCTAssertEqual(WorkoutProgress.distinctExercises(in: [w1, w2]).map { $0.id }, ["bench", "squat"])
    }

    func testCatalogSearchAndSlug() {
        let list = ExerciseCatalog.default
        XCTAssertGreaterThan(list.count, 20)
        XCTAssertEqual(ExerciseCatalog.search("bench", in: list).first?.name, "Bench Press")
        XCTAssertEqual(ExerciseCatalog.search("", in: list).count, list.count)
        XCTAssertEqual(ExerciseCatalog.slug("Romanian Deadlift"), "romanian_deadlift")
        XCTAssertEqual(ExerciseCatalog.slug("Pull-up"), "pull_up")
    }
}
