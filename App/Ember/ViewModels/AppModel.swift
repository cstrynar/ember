import SwiftUI
import EmberCore

/// Shared `@MainActor` app state connecting SwiftUI views to `EmberCore` logic and the
/// on-disk `HealthStore`. One instance is injected via `environmentObject`.
@MainActor
final class AppModel: ObservableObject {

    // MARK: Published state
    @Published var profile: UserProfile?
    @Published private(set) var goalOverride: Macros?
    @Published private(set) var today: DayNutrition
    @Published private(set) var hydration: HydrationLog
    @Published private(set) var reminderSettings: ReminderSettings
    @Published private(set) var customFoods: [FoodItem]
    @Published private(set) var foodDatabase: FoodDatabase
    @Published private(set) var favoriteFoodIDs: [String]
    /// Recently-logged foods (newest first), derived from day history for quick-add.
    @Published private(set) var recents: [RecentFood] = []
    @Published private(set) var todayWorkout: Workout
    @Published private(set) var allWorkouts: [Workout]
    /// Recent Apple Health body-mass samples (empty when denied / no data / unavailable).
    @Published private(set) var healthWeights: [HealthWeightSample] = []
    /// Recent Apple Health workout summaries (empty when denied / no data / unavailable).
    @Published private(set) var healthWorkouts: [HealthWorkout] = []
    /// Recently-trained exercises (newest first), derived from workout history for quick-add.
    @Published private(set) var recentExercises: [RecentExercise] = []
    @Published private(set) var customExercises: [Exercise]
    @Published var coachModel: String = "claude-sonnet-4-6"
    @Published private(set) var hasAPIKey: Bool = false
    @Published private(set) var reports: [CoachReport] = []
    /// The coach's durable, cross-session memory of facts about the user.
    @Published private(set) var coachMemory: CoachMemory = .empty

    // MARK: Private
    private let store: HealthStore
    private let notifications = NotificationService()
    private let health: HealthAccess
    private let preloaded: FoodDatabase
    private(set) var dayKey: String
    private static let coachModelKey = "ember.coachModel"
    private static let lastReviewKey = "ember.lastReviewDate"
    /// Bounded recent window for Health fetches (history horizon the surfaces care about).
    private static let healthLookbackDays = 180

    init(store: HealthStore = FileHealthStore(), health: HealthAccess? = nil) {
        self.store = store
        self.health = health ?? HealthKitAccess()
        let key = DayKey.key(for: Date())
        self.dayKey = key
        self.profile = store.loadProfile()
        self.goalOverride = store.loadGoalOverride()
        self.today = store.loadDay(key) ?? DayNutrition(dayKey: key)
        self.hydration = store.loadHydration(key) ?? HydrationLog(dayKey: key)
        self.reminderSettings = store.loadReminderSettings()
        let custom = store.loadCustomFoods()
        self.customFoods = custom
        let preloadedDB = FoodDatabase.loadPreloaded()
        self.preloaded = preloadedDB
        self.foodDatabase = preloadedDB.merging(custom: custom)
        self.favoriteFoodIDs = store.loadFavoriteFoodIDs()
        self.recents = RecentFoods.from(store.allDays())
        self.todayWorkout = store.loadWorkout(key) ?? Workout(dayKey: key)
        self.allWorkouts = store.allWorkouts()
        self.recentExercises = RecentExercises.from(store.allWorkouts())
        self.customExercises = store.loadCustomExercises()
        self.coachModel = UserDefaults.standard.string(forKey: Self.coachModelKey) ?? "claude-sonnet-4-6"
        self.hasAPIKey = KeychainStore.read() != nil
        self.reports = store.loadReports().sorted { $0.createdAt > $1.createdAt }
        self.coachMemory = store.loadCoachMemory()
    }

    // MARK: Derived
    var hasProfile: Bool { profile != nil }

    /// Effective daily goal: explicit override, else profile-derived, else nil.
    var goal: Macros? {
        if let goalOverride { return goalOverride }
        if let profile { return MacroMath.recommendedGoal(profile: profile) }
        return nil
    }
    var consumed: Macros { today.consumed }
    var hydrationTargetML: Int { NutritionDefaults.hydrationTargetML }

    // MARK: Lifecycle
    /// Call on launch and when returning to the foreground: roll the day over if midnight
    /// passed, request notification permission, and (re)schedule reminders.
    func onForeground() {
        let key = DayKey.key(for: Date())
        if key != dayKey {
            dayKey = key
            today = store.loadDay(key) ?? DayNutrition(dayKey: key)
            hydration = store.loadHydration(key) ?? HydrationLog(dayKey: key)
            todayWorkout = store.loadWorkout(key) ?? Workout(dayKey: key)
        }
        allWorkouts = store.allWorkouts()
        refreshRecents()
        refreshRecentExercises()
        notifications.requestPermissionIfNeeded()
        notifications.sync(reminderSettings)
        refreshHealthData()
    }

    // MARK: Profile & goals
    func saveProfile(_ profile: UserProfile) {
        self.profile = profile
        store.saveProfile(profile)
    }

    /// Set or clear an explicit macro-goal override (`nil` reverts to the recommendation).
    func setGoalOverride(_ macros: Macros?) {
        goalOverride = macros
        store.saveGoalOverride(macros)
    }

    // MARK: Food logging
    @discardableResult
    func log(_ item: FoodItem, servings: Double, meal: Meal) -> UUID {
        let entry = FoodEntry(food: item, dayKey: dayKey, servings: servings, meal: meal)
        appendEntry(entry)
        return entry.id
    }

    /// One-tap log: a single serving against the meal suggested for the current time.
    /// Returns the new entry's id so the UI can offer an Undo.
    @discardableResult
    func quickLog(_ item: FoodItem) -> UUID {
        log(item, servings: 1, meal: Meal.suggestedForNow())
    }

    /// One-tap re-log of a recent food at its *prior* servings + meal (not reset to 1).
    /// Returns the new entry's id so the UI can offer an Undo.
    @discardableResult
    func reLog(_ recent: RecentFood) -> UUID {
        log(foodItem(for: recent), servings: recent.lastServings, meal: recent.lastMeal)
    }

    func logManual(name: String, macros: Macros, servings: Double, meal: Meal, saveToLibrary: Bool) {
        appendEntry(FoodEntry(dayKey: dayKey, name: name, servings: servings,
                              macrosPerServing: macros, meal: meal))
        if saveToLibrary {
            let id = "custom_" + UUID().uuidString.prefix(8).lowercased()
            addCustomFood(FoodItem(id: id, name: name, servingDescription: "1 serving",
                                   macrosPerServing: macros, source: .custom))
        }
    }

    private func appendEntry(_ entry: FoodEntry) {
        today = today.appending(entry)
        store.saveDay(today)
        refreshRecents()
    }

    func removeEntry(_ id: UUID) {
        today = today.removing(id: id)
        store.saveDay(today)
        refreshRecents()
    }

    private func refreshRecents() { recents = RecentFoods.from(store.allDays()) }

    // MARK: Custom foods
    func addCustomFood(_ food: FoodItem) {
        customFoods.append(food)
        store.saveCustomFoods(customFoods)
        foodDatabase = preloaded.merging(custom: customFoods)
    }

    // MARK: Quick-add (favorites + recents)

    /// All foods, alphabetical — for browsing the database (so it's obvious it's preloaded).
    var allFoods: [FoodItem] { foodDatabase.items.sorted { $0.name < $1.name } }

    /// Favorited foods, in the order they were pinned. (Ids no longer in the DB are skipped.)
    var favoriteFoods: [FoodItem] { favoriteFoodIDs.compactMap { foodDatabase.item(id: $0) } }

    func isFavorite(_ id: String) -> Bool { favoriteFoodIDs.contains(id) }

    func setFavorite(_ item: FoodItem, _ on: Bool) {
        if on {
            guard !favoriteFoodIDs.contains(item.id) else { return }
            favoriteFoodIDs.append(item.id)
        } else {
            favoriteFoodIDs.removeAll { $0 == item.id }
        }
        store.saveFavoriteFoodIDs(favoriteFoodIDs)
    }

    func toggleFavorite(_ item: FoodItem) { setFavorite(item, !isFavorite(item.id)) }

    /// A recent food as a loggable `FoodItem`: the live DB item when its id still resolves,
    /// otherwise an inline item rebuilt from the logged snapshot.
    func foodItem(for recent: RecentFood) -> FoodItem {
        if let id = recent.foodID, let item = foodDatabase.item(id: id) { return item }
        return FoodItem(id: recent.id, name: recent.name, servingDescription: "1 serving",
                        macrosPerServing: recent.macrosPerServing, source: .custom)
    }

    /// The recent snapshot for a food id, if it has ever been logged (for one-tap re-log).
    func recent(forID id: String) -> RecentFood? { recents.first { $0.id == id } }

    /// Foods for the quick-add strip: favorites first, then recents not already pinned.
    /// Each entry carries the prior servings/meal snapshot when the food has history, so a
    /// chip tap re-logs at that snapshot; a never-logged favorite carries `nil` (1 serving).
    func quickAddItems(limit: Int = 12) -> [QuickAddEntry] {
        var entries: [QuickAddEntry] = favoriteFoods.map {
            QuickAddEntry(item: $0, recent: recent(forID: $0.id))
        }
        var seen = Set(entries.map(\.id))
        for recent in recents {
            let item = foodItem(for: recent)
            guard seen.insert(item.id).inserted else { continue }
            entries.append(QuickAddEntry(item: item, recent: recent))
        }
        return Array(entries.prefix(limit))
    }

    // MARK: Hydration
    func addWater(_ ml: Int) {
        hydration = hydration.adding(ml)
        store.saveHydration(hydration)
    }

    // MARK: Reminders
    func updateReminders(_ settings: ReminderSettings) {
        reminderSettings = settings
        store.saveReminderSettings(settings)
        notifications.sync(settings)
    }

    // MARK: Apple Health

    /// Whether Health data is available on this device (false on iPad / hosts without Health).
    var isHealthDataAvailable: Bool { health.isHealthDataAvailable }

    /// Requests read authorization for Ember's Health types. Fire-and-forget by default; the
    /// `completion` Bool means "the request flow finished", not "granted" (HealthKit hides
    /// read-grant status). Invoked only from an explicit Settings tap — never on launch.
    /// Refreshes the Health caches once the flow finishes, so a fresh grant populates data
    /// without a relaunch.
    func requestHealthAccess(completion: ((Bool) -> Void)? = nil) {
        health.requestAuthorization { [weak self] ok in
            self?.refreshHealthData()
            completion?(ok)
        }
    }

    /// Fetches recent Health weight + workouts into the caches. On-demand only (no observers);
    /// failures / denial / no-data all leave the caches `[]` so every helper falls back to manual.
    private func refreshHealthData() {
        health.recentBodyMass(daysBack: Self.healthLookbackDays) { [weak self] samples in
            self?.healthWeights = samples
        }
        health.recentWorkouts(daysBack: Self.healthLookbackDays) { [weak self] workouts in
            self?.healthWorkouts = workouts
        }
    }

    /// The user's current weight: most-recent Health body mass when present, else manual profile.
    var currentWeightKg: Double? {
        HealthMerge.currentWeightKg(health: healthWeights, manual: profile?.weightKg)
    }

    /// Manual workouts (for the per-exercise charts) plus a deduped Health workout summary.
    var workoutHistory: MergedWorkoutHistory {
        HealthMerge.mergedWorkouts(manual: allWorkouts, health: healthWorkouts)
    }

    // MARK: Coach (API key & model)

    func currentAPIKey() -> String? { KeychainStore.read() }

    func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainStore.save(trimmed)
        hasAPIKey = true
    }

    func clearAPIKey() {
        KeychainStore.delete()
        hasAPIKey = false
    }

    func setCoachModel(_ model: String) {
        coachModel = model
        UserDefaults.standard.set(model, forKey: Self.coachModelKey)
    }

    // MARK: Friction & weekly review

    func logFriction(context: String, note: String) {
        store.appendFriction(FrictionEntry(context: context, note: note))
    }

    // MARK: Coach memory

    /// Caps, persists, and republishes the coach's durable memory.
    func updateCoachMemory(_ memory: CoachMemory) {
        let capped = memory.capped()
        coachMemory = capped
        store.saveCoachMemory(capped)
    }

    @discardableResult
    func rememberFact(category: String = "general", text: String) -> CoachMemory {
        updateCoachMemory(coachMemory.adding(category: category, text: text))
        return coachMemory
    }

    @discardableResult
    func updateFact(id: UUID, category: String? = nil, text: String? = nil) -> CoachMemory {
        updateCoachMemory(coachMemory.updating(id: id, category: category, text: text))
        return coachMemory
    }

    @discardableResult
    func removeFact(id: UUID) -> CoachMemory {
        updateCoachMemory(coachMemory.removing(id: id))
        return coachMemory
    }

    private var lastReviewDate: Date? {
        get { UserDefaults.standard.object(forKey: Self.lastReviewKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastReviewKey) }
    }

    /// True when a key is set and it's been ≥7 days since the last review (or there's some
    /// history and no review has ever run).
    var isWeeklyReviewDue: Bool {
        guard hasAPIKey else { return false }
        guard let last = lastReviewDate else {
            return !store.allDays().isEmpty || !store.allWorkouts().isEmpty
        }
        return Date().timeIntervalSince(last) >= 7 * 24 * 3600
    }

    @discardableResult
    func generateWeeklyReview() async throws -> CoachReport {
        guard let key = currentAPIKey(), !key.isEmpty else {
            throw CoachError.http(401, "No API key set.")
        }
        let backend = AnthropicClient(apiKey: key)
        let response = try await backend.send(
            systemPrompt: Self.reviewSystemPrompt,
            messages: [["role": "user", "content": weeklyReviewInput()]],
            tools: [],
            model: coachModel)
        let body = response.assistantText.isEmpty ? "_(The review came back empty.)_" : response.assistantText
        let report = CoachReport(id: dayKey, markdown: body)
        store.saveReport(report)
        reports = store.loadReports().sorted { $0.createdAt > $1.createdAt }
        store.clearFrictionLog()
        lastReviewDate = Date()
        return report
    }

    private static let reviewSystemPrompt =
        "You are Ember's maintenance reviewer. You read a week of the user's health-app usage "
        + "and a friction log, then write a short, practical markdown report for the developer/user: "
        + "what went well, what felt clunky and how to fix it, what new data would be worth gathering, "
        + "and concrete suggested changes. Be concise and specific."

    private func weeklyReviewInput() -> String {
        let friction = store.loadFrictionLog()
        let frictionText = friction.isEmpty
            ? "(no friction notes this week)"
            : friction.map { "- [\($0.context)] \($0.note)" }.joined(separator: "\n")
        let days = store.allDays()
        let workouts = store.allWorkouts()
        var lines = [
            "Weekly maintenance review. Today: \(dayKey).",
            "Days with food logged: \(days.count). Workouts recorded: \(workouts.count).",
        ]
        if let p = profile, let g = goal {
            lines.append("Goal: \(p.goal.rawValue); daily target ~\(Int(g.calories.rounded())) kcal.")
        }
        lines.append("Friction log since last review:\n\(frictionText)")
        lines.append("""
        Write a brief markdown report (under ~200 words) with these sections:
        **Highlights**, **Friction & fixes**, **What to track next**, **Suggested changes**.
        """)
        return lines.joined(separator: "\n\n")
    }

    // MARK: Workouts

    /// All exercises available when logging: built-in catalog plus the user's custom ones.
    var exerciseCatalog: [Exercise] {
        var byID: [String: Exercise] = [:]
        for e in ExerciseCatalog.default { byID[e.id] = e }
        for e in customExercises { byID[e.id] = e }
        return byID.values.sorted { $0.name < $1.name }
    }

    /// Today's sets grouped by exercise, in the order each exercise first appeared.
    var todayExerciseGroups: [ExerciseGroup] {
        var order: [String] = []
        var byID: [String: ExerciseGroup] = [:]
        for set in todayWorkout.sets {
            if byID[set.exerciseID] == nil {
                order.append(set.exerciseID)
                byID[set.exerciseID] = ExerciseGroup(id: set.exerciseID, name: set.exerciseName, sets: [])
            }
            byID[set.exerciseID]?.sets.append(set)
        }
        return order.compactMap { byID[$0] }
    }

    var todayVolume: Double { WorkoutProgress.volume(of: todayWorkout.sets) }

    /// Build (but don't yet save) a custom exercise from a free-text name.
    func makeCustomExercise(named name: String) -> Exercise {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return Exercise(id: "custom_" + ExerciseCatalog.slug(trimmed), name: trimmed, category: .strength)
    }

    /// The most recent set logged for an exercise (for pre-filling).
    func lastSet(forExerciseID id: String) -> LoggedSet? {
        for workout in allWorkouts.sorted(by: { $0.date > $1.date }) {
            if let last = workout.sets(for: id).last { return last }
        }
        return nil
    }

    /// The recent snapshot for an exercise id, if it has ever been trained (for one-tap re-log).
    func recentExercise(forID id: String) -> RecentExercise? {
        recentExercises.first { $0.id == id }
    }

    /// Resolve a `RecentExercise` to a loggable `Exercise`: the catalog item when its id still
    /// resolves, otherwise an inline exercise rebuilt from the snapshot (custom/strength).
    func exercise(for recent: RecentExercise) -> Exercise {
        exerciseCatalog.first { $0.id == recent.exerciseID }
            ?? Exercise(id: recent.exerciseID, name: recent.name, category: .strength)
    }

    /// One-tap re-log of a recent exercise's last set (its snapshot reps + weight).
    /// Returns the new set's id so a one-tap surface can offer Undo (mirrors `reLog`).
    @discardableResult
    func reLogSet(_ recent: RecentExercise) -> UUID {
        logSet(exercise: exercise(for: recent), reps: recent.lastReps, weightKg: recent.lastWeightKg)
    }

    /// Logs a set for today's workout and returns the new `LoggedSet.id` (for Undo). Existing
    /// callers that ignore the result compile unchanged via `@discardableResult`.
    @discardableResult
    func logSet(exercise: Exercise, reps: Int, weightKg: Double) -> UUID {
        if !exerciseCatalog.contains(where: { $0.id == exercise.id }) {
            addCustomExercise(exercise)
        }
        var workout = todayWorkout
        let set = LoggedSet(exerciseID: exercise.id, exerciseName: exercise.name,
                            reps: reps, weightKg: weightKg)
        workout.sets.append(set)
        todayWorkout = workout
        persistWorkout()
        return set.id
    }

    func removeSet(_ id: UUID) {
        var workout = todayWorkout
        workout.sets.removeAll { $0.id == id }
        todayWorkout = workout
        persistWorkout()
    }

    func addCustomExercise(_ exercise: Exercise) {
        guard !customExercises.contains(where: { $0.id == exercise.id }) else { return }
        customExercises.append(exercise)
        store.saveCustomExercises(customExercises)
    }

    private func persistWorkout() {
        store.saveWorkout(todayWorkout)
        allWorkouts = store.allWorkouts()
        refreshRecentExercises()
    }

    private func refreshRecentExercises() {
        recentExercises = RecentExercises.from(store.allWorkouts())
    }
}

/// Today's sets for a single exercise (display helper).
struct ExerciseGroup: Identifiable {
    let id: String
    let name: String
    var sets: [LoggedSet]
}

/// A quick-add strip entry: a loggable `FoodItem` plus its prior log snapshot when one
/// exists (`nil` for a favorited-but-never-logged food, which logs 1 serving / suggested).
struct QuickAddEntry: Identifiable {
    let item: FoodItem
    let recent: RecentFood?
    var id: String { item.id }
}

