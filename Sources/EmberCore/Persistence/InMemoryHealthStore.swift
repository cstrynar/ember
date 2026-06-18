import Foundation

/// In-memory `HealthStore` for tests and SwiftUI previews.
public final class InMemoryHealthStore: HealthStore {
    private var profile: UserProfile?
    private var goalOverride: Macros?
    private var days: [String: DayNutrition] = [:]
    private var hydration: [String: HydrationLog] = [:]
    private var customFoods: [FoodItem] = []
    private var favoriteFoodIDs: [String] = []
    private var workouts: [String: Workout] = [:]
    private var customExercises: [Exercise] = []
    private var friction: [FrictionEntry] = []
    private var reports: [String: CoachReport] = [:]
    private var reminderSettings: ReminderSettings?
    private var coachMemory: CoachMemory?

    public init() {}

    public func loadProfile() -> UserProfile? { profile }
    public func saveProfile(_ profile: UserProfile) { self.profile = profile }

    public func loadGoalOverride() -> Macros? { goalOverride }
    public func saveGoalOverride(_ goal: Macros?) { goalOverride = goal }

    public func loadDay(_ dayKey: String) -> DayNutrition? { days[dayKey] }
    public func saveDay(_ day: DayNutrition) { days[day.dayKey] = day }
    public func allDays() -> [DayNutrition] { Array(days.values) }

    public func loadHydration(_ dayKey: String) -> HydrationLog? { hydration[dayKey] }
    public func saveHydration(_ log: HydrationLog) { hydration[log.dayKey] = log }

    public func loadCustomFoods() -> [FoodItem] { customFoods }
    public func saveCustomFoods(_ foods: [FoodItem]) { customFoods = foods }

    public func loadFavoriteFoodIDs() -> [String] { favoriteFoodIDs }
    public func saveFavoriteFoodIDs(_ ids: [String]) { favoriteFoodIDs = ids }

    public func loadWorkout(_ dayKey: String) -> Workout? { workouts[dayKey] }
    public func saveWorkout(_ workout: Workout) { workouts[workout.dayKey] = workout }
    public func allWorkouts() -> [Workout] { Array(workouts.values) }

    public func loadCustomExercises() -> [Exercise] { customExercises }
    public func saveCustomExercises(_ exercises: [Exercise]) { customExercises = exercises }

    public func loadFrictionLog() -> [FrictionEntry] { friction }
    public func appendFriction(_ entry: FrictionEntry) { friction.append(entry) }
    public func clearFrictionLog() { friction = [] }
    public func loadReports() -> [CoachReport] { Array(reports.values) }
    public func saveReport(_ report: CoachReport) { reports[report.id] = report }

    public func loadReminderSettings() -> ReminderSettings { reminderSettings ?? .default }
    public func saveReminderSettings(_ settings: ReminderSettings) { reminderSettings = settings }

    public func loadCoachMemory() -> CoachMemory { coachMemory ?? .empty }
    public func saveCoachMemory(_ memory: CoachMemory) { coachMemory = memory }
}
