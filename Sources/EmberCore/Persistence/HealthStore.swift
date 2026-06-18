import Foundation

/// Persistence boundary for all of Ember's data. Value-in / value-out.
///
/// Implementations choose the storage mechanism (the app uses local JSON files; tests use
/// an in-memory store). Thread safety is the implementation's responsibility; the app
/// drives this from the main actor.
public protocol HealthStore: AnyObject {

    // MARK: Profile & goals
    func loadProfile() -> UserProfile?
    func saveProfile(_ profile: UserProfile)
    /// An explicit macro-goal override; `nil` means "use the profile-derived recommendation".
    func loadGoalOverride() -> Macros?
    func saveGoalOverride(_ goal: Macros?)

    // MARK: Nutrition (per day)
    func loadDay(_ dayKey: String) -> DayNutrition?
    func saveDay(_ day: DayNutrition)
    /// All stored days, in no guaranteed order (for history and the coach).
    func allDays() -> [DayNutrition]

    // MARK: Hydration (per day)
    func loadHydration(_ dayKey: String) -> HydrationLog?
    func saveHydration(_ log: HydrationLog)

    // MARK: Custom foods
    func loadCustomFoods() -> [FoodItem]
    func saveCustomFoods(_ foods: [FoodItem])

    // MARK: Favorite foods
    /// Ordered ids of foods the user pinned for quick-add (insertion order = display order).
    func loadFavoriteFoodIDs() -> [String]
    func saveFavoriteFoodIDs(_ ids: [String])

    // MARK: Workouts (per day)
    func loadWorkout(_ dayKey: String) -> Workout?
    func saveWorkout(_ workout: Workout)
    /// All stored workouts, in no guaranteed order (for progress charts and the coach).
    func allWorkouts() -> [Workout]

    // MARK: Custom exercises
    func loadCustomExercises() -> [Exercise]
    func saveCustomExercises(_ exercises: [Exercise])

    // MARK: Friction log & coach reports
    func loadFrictionLog() -> [FrictionEntry]
    func appendFriction(_ entry: FrictionEntry)
    func clearFrictionLog()
    func loadReports() -> [CoachReport]
    func saveReport(_ report: CoachReport)

    // MARK: Reminders
    /// Returns `ReminderSettings.default` when nothing has been saved yet.
    func loadReminderSettings() -> ReminderSettings
    func saveReminderSettings(_ settings: ReminderSettings)

    // MARK: Coach memory
    /// The coach's durable, cross-session facts about the user.
    /// Returns `CoachMemory.empty` when nothing has been saved yet (mirrors `loadReminderSettings`).
    func loadCoachMemory() -> CoachMemory
    func saveCoachMemory(_ memory: CoachMemory)
}
