import Foundation
import EmberCore

/// `HealthStore` backed by JSON files in the app's Application Support directory.
/// Local-only — no network, no sync.
///
/// File layout (under `applicationSupportDirectory/Ember/`):
///   profile.json, goal.json, custom-foods.json, reminders.json, coach-memory.json,
///   nutrition-<dayKey>.json, hydration-<dayKey>.json
///
/// Thread safety: drive from a single actor (the app uses the main actor).
final class FileHealthStore: HealthStore {

    private let rootURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        rootURL = support.appendingPathComponent("Ember", isDirectory: true)
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    // MARK: Profile & goals

    func loadProfile() -> UserProfile? { load(UserProfile.self, "profile.json") }
    func saveProfile(_ profile: UserProfile) { save(profile, "profile.json") }

    func loadGoalOverride() -> Macros? { load(Macros.self, "goal.json") }
    func saveGoalOverride(_ goal: Macros?) {
        if let goal { save(goal, "goal.json") } else { remove("goal.json") }
    }

    // MARK: Nutrition

    func loadDay(_ dayKey: String) -> DayNutrition? { load(DayNutrition.self, "nutrition-\(dayKey).json") }
    func saveDay(_ day: DayNutrition) { save(day, "nutrition-\(day.dayKey).json") }
    func allDays() -> [DayNutrition] {
        files(prefix: "nutrition-").compactMap { load(DayNutrition.self, url: $0) }
    }

    // MARK: Hydration

    func loadHydration(_ dayKey: String) -> HydrationLog? { load(HydrationLog.self, "hydration-\(dayKey).json") }
    func saveHydration(_ log: HydrationLog) { save(log, "hydration-\(log.dayKey).json") }

    // MARK: Custom foods

    func loadCustomFoods() -> [FoodItem] { load([FoodItem].self, "custom-foods.json") ?? [] }
    func saveCustomFoods(_ foods: [FoodItem]) { save(foods, "custom-foods.json") }

    // MARK: Favorite foods

    func loadFavoriteFoodIDs() -> [String] { load([String].self, "favorite-foods.json") ?? [] }
    func saveFavoriteFoodIDs(_ ids: [String]) { save(ids, "favorite-foods.json") }

    // MARK: Workouts

    func loadWorkout(_ dayKey: String) -> Workout? { load(Workout.self, "workout-\(dayKey).json") }
    func saveWorkout(_ workout: Workout) { save(workout, "workout-\(workout.dayKey).json") }
    func allWorkouts() -> [Workout] {
        files(prefix: "workout-").compactMap { load(Workout.self, url: $0) }
    }

    // MARK: Custom exercises

    func loadCustomExercises() -> [Exercise] { load([Exercise].self, "custom-exercises.json") ?? [] }
    func saveCustomExercises(_ exercises: [Exercise]) { save(exercises, "custom-exercises.json") }

    // MARK: Friction log & coach reports

    func loadFrictionLog() -> [FrictionEntry] { load([FrictionEntry].self, "friction-log.json") ?? [] }
    func appendFriction(_ entry: FrictionEntry) {
        var log = loadFrictionLog()
        log.append(entry)
        save(log, "friction-log.json")
    }
    func clearFrictionLog() { remove("friction-log.json") }
    func loadReports() -> [CoachReport] {
        files(prefix: "report-").compactMap { load(CoachReport.self, url: $0) }
    }
    func saveReport(_ report: CoachReport) { save(report, "report-\(report.id).json") }

    // MARK: Reminders

    func loadReminderSettings() -> ReminderSettings { load(ReminderSettings.self, "reminders.json") ?? .default }
    func saveReminderSettings(_ settings: ReminderSettings) { save(settings, "reminders.json") }

    // MARK: Coach memory

    func loadCoachMemory() -> CoachMemory { load(CoachMemory.self, "coach-memory.json") ?? .empty }
    func saveCoachMemory(_ memory: CoachMemory) { save(memory, "coach-memory.json") }

    // MARK: - Private helpers

    private func url(_ name: String) -> URL { rootURL.appendingPathComponent(name) }

    private func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        load(type, url: url(name))
    }

    private func load<T: Decodable>(_ type: T.Type, url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url(name), options: .atomic)
    }

    private func remove(_ name: String) {
        try? FileManager.default.removeItem(at: url(name))
    }

    private func files(prefix: String) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: nil)) ?? []
        return contents.filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "json" }
    }
}
