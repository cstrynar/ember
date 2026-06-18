import XCTest
@testable import EmberCore

final class RecentExercisesTests: XCTestCase {

    private func set(_ ex: String, _ reps: Int, _ wt: Double) -> LoggedSet {
        LoggedSet(exerciseID: ex, exerciseName: ex.capitalized, reps: reps, weightKg: wt)
    }

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testNewestFirst() {
        let older = Workout(dayKey: "d1", date: t0, sets: [set("squat", 5, 100)])
        let newer = Workout(dayKey: "d2", date: t0.addingTimeInterval(86_400),
                            sets: [set("bench", 5, 80)])
        let recents = RecentExercises.from([older, newer])
        XCTAssertEqual(recents.map(\.exerciseID), ["bench", "squat"])
    }

    func testDedupesByExerciseKeepingMostRecentSet() {
        let older = Workout(dayKey: "d1", date: t0, sets: [set("bench", 5, 80)])
        let newer = Workout(dayKey: "d2", date: t0.addingTimeInterval(86_400),
                            sets: [set("bench", 3, 90)])
        let recents = RecentExercises.from([older, newer])
        XCTAssertEqual(recents.count, 1)
        // Snapshot is the newest workout's set (3 × 90), not the older 5 × 80.
        XCTAssertEqual(recents.first?.lastReps, 3)
        XCTAssertEqual(recents.first?.lastWeightKg, 90)
    }

    func testSnapshotIsLastSetWithinNewestWorkout() {
        // Newest workout has two sets of bench: 5×100 then 3×110 → snapshot is the last (3×110),
        // matching AppModel.lastSet(forExerciseID:).
        let w = Workout(dayKey: "d", date: t0,
                        sets: [set("bench", 5, 100), set("bench", 3, 110)])
        let recent = RecentExercises.from([w]).first
        XCTAssertEqual(recent?.lastReps, 3)
        XCTAssertEqual(recent?.lastWeightKg, 110)
    }

    func testHonorsLimit() {
        let workouts = (0..<5).map {
            Workout(dayKey: "d\($0)", date: t0.addingTimeInterval(Double($0) * 86_400),
                    sets: [set("ex\($0)", 5, 100)])
        }
        let recents = RecentExercises.from(workouts, limit: 3)
        XCTAssertEqual(recents.map(\.exerciseID), ["ex4", "ex3", "ex2"])
    }

    func testEmpty() {
        XCTAssertTrue(RecentExercises.from([]).isEmpty)
    }
}
