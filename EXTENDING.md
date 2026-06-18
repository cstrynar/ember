# Extending Ember

A short guide for picking this up and making it yours. Ember is a personal health
coach for iOS: nutrition (macros), workouts, and an AI coach. It's deliberately small
and the seams are clean — extend it without fighting the architecture.

## The one big idea

Two layers:

- **`EmberCore`** (Swift package, `Sources/EmberCore`) — pure, deterministic domain
  logic and models. No UIKit, no SwiftUI, no network. **Everything here is unit-tested
  and runs with `swift test` — no Xcode, no Mac required.** Put logic here.
- **`App/Ember`** (SwiftUI) — UI and the side-effecting world: disk, notifications,
  the Anthropic network client, Keychain. Thin wrappers over `EmberCore`.

Rule of thumb: if it can be a pure function, it belongs in `EmberCore` with a test.
The coach's tools, the view models, and the views are all thin shells over that core.
In particular, a coach *tool* is just an App-layer wrapper: it parses input and calls an
`AppModel` (or `EmberCore`) method — it holds no logic of its own.

## Run it

```bash
# Logic tests — fast, no Xcode:
swift test

# Build the app (macOS + Xcode 15+):
brew install xcodegen
cd App && xcodegen generate && open Ember.xcodeproj
# Set your team under Signing & Capabilities, then Archive → Distribute → TestFlight.
```

`App/Ember.xcodeproj` is git-ignored — always regenerate it from `App/project.yml`.
New Swift files under `App/Ember/` are picked up automatically (the target globs the
folder); you only edit `project.yml` for new resources, settings, or dependencies.

## Where things live

```
Sources/EmberCore/
  Models/        Macros, UserProfile, FoodItem, FoodEntry, DayNutrition, HydrationLog,
                 Exercise, Workout/LoggedSet, DailyReminder/ReminderSettings,
                 FrictionEntry, CoachReport, CoachMemory/CoachMemoryItem
  Logic/         MacroMath, FoodDatabase, WorkoutProgress,
                 RecentFoods, RecentExercises
  Persistence/   HealthStore (protocol) + InMemoryHealthStore (tests/previews)
                 — profile/goal, nutrition, hydration, workouts, custom foods/exercises,
                 favorites, friction log, coach reports, reminders, coach memory
  Resources/     preloaded-foods.json
  Util/          DayKey
App/Ember/
  ViewModels/    AppModel (shared @MainActor state), ChatStore (owns the coach conversation)
  Persistence/   FileHealthStore (local JSON in Application Support)
  Services/      NotificationService, KeychainStore, AnthropicClient, CoachTools, CoachAgent,
                 HealthService (HealthAccess seam — read-only Apple Health)
  Views/         RootView + Food / Train / Coach / Settings screens and components
Tools/           gen_foods.py (regenerates the food DB)
```

## Common changes

**Add or edit foods.** Edit the `FOODS` table in `Tools/gen_foods.py` and run
`python3 Tools/gen_foods.py` to regenerate `Sources/EmberCore/Resources/preloaded-foods.json`.
The on-disk schema is flat (`id, name, serving, kcal, protein, carb, fat`).

**Add exercises.** Append to `ExerciseCatalog.default` in `Sources/EmberCore/Models/Exercise.swift`.
Users can already add custom exercises at log time; this just seeds the picker.

**Make logging easier with use (recents / quick-add).** The "gets-easier-the-more-you-use-it"
surfaces are built from one pure pattern, mirrored for food and workouts:

- Food: `RecentFoods.from(_ days:)` (`Sources/EmberCore/Logic/RecentFoods.swift`) folds the
  stored history into `[RecentFood]`, each snapshotting `lastServings`/`lastMeal`.
  `AppModel.recents` / `quickAddItems()` expose them; the `FoodView` strip and `QuickAddView`
  Favorites/Recent rows one-tap re-log via `AppModel.reLog(_:)`.
- Workouts (the mirror): `RecentExercises.from(_ workouts:)`
  (`Sources/EmberCore/Logic/RecentExercises.swift`) → `[RecentExercise]`, each snapshotting
  `lastReps`/`lastWeightKg`. `AppModel.recentExercises` feeds the `TrainView` quick-add strip
  and the `AddSetView` "Recent" section; one-tap re-log via `AppModel.reLogSet(_:)`.

The convention to copy: derive any "recent/frequent" list as a **pure `EmberCore` function over
stored history** (`HealthStore.allDays()` / `allWorkouts()`), refresh it in the `AppModel`
persist hooks, and keep the re-log snapshot *on the value type* so a re-log needs no
re-derivation. `logSet`/`reLogSet`/`reLog` return the new entry/set `UUID` so a surface can
offer an Undo.

**Change the macro math.** All of it is in `Sources/EmberCore/Logic/MacroMath.swift` —
the deficit/surplus, the calorie floor, protein-per-kg, and the carb/fat split are
named constants. Update the tests in `Tests/EmberCoreTests/MacroMathTests.swift` to match.

**Add a profile field.** The `goalWeightKg: Double?` field is the precedent: add an
**optional** stored property with a `nil` default to `UserProfile` and let `Codable` stay
synthesized (no custom `CodingKeys`) so an existing `profile.json` written before the field
still decodes. Surface it as a low-friction `ProfileView` row that never gates `Save`
(empty/invalid input just maps to `nil`). If it's coaching context, read it in
`CoachAgent.systemPrompt` and `CoachTools.getToday()` *only when set*. Boundary that kept this
clean: a field that feeds `MacroMath` is a macro-model change (test-and-design it); pure
coaching context like a target weight does **not** touch `MacroMath`.

**Give the coach a new ability.** Add a tool in `App/Ember/Services/CoachTools.swift`:
one entry in `definitions()` (name + description + JSON input schema) and one `case` in
`run(name:input:)` that calls an `AppModel` method. Tools return a `String` the model
reads back. Keep tools thin — real logic goes in `AppModel`/`EmberCore`. The `remember`
tool is the worked example of a **stateful** tool: it's one `definitions()` entry plus one
`run(name:input:)` case that calls an `AppModel` method, and the coach reads the current
state back through `get_today`.

**Give the coach a durable memory.** `CoachMemory`/`CoachMemoryItem`
(`Sources/EmberCore/Models/CoachMemory.swift`) is the pure, durable fact list — value-type
helpers `adding`/`updating`/`removing`/`capped(to:)`/`promptLines()`/`isEmpty`/`empty`.
It persists as `coach-memory.json` via `HealthStore.loadCoachMemory()` /
`saveCoachMemory(_:)` (default `.empty`, implemented in **both** `FileHealthStore` and
`InMemoryHealthStore`). `AppModel.coachMemory` plus `rememberFact` / `updateFact` /
`removeFact` apply the pure helpers, persist, and republish. The coach *writes* it through
the `remember` tool (`action`: add / update / remove) and *reads* current item ids back via
`get_today`'s `coach_memory`. `CoachAgent.systemPrompt(app:)` folds it into the prompt via
`promptLines()` when non-empty — so saved facts survive a cleared conversation and new
sessions. To store a new *kind* of durable state, follow this shape: a pure `EmberCore` type,
a `HealthStore` load/save pair, `AppModel` wrappers, and (optionally) a coach tool to edit it.

**Reset the coach conversation.** `ChatStore.reset()` is the single source of truth for
flushing a conversation — it clears the visible `messages`, the private `apiMessages`
history, and the transient `isThinking` / `errorText` / `draft`. `CoachView` exposes it via
a `.primaryAction` trash button behind a confirmation dialog (gated on `app.hasAPIKey`).
Gotcha for anyone extending the chat surface: **clearing the conversation does not clear the
durable `CoachMemory`** — saved facts re-fold into the system prompt on the next send.

**Add a screen or tab.** Add a SwiftUI view under `App/Ember/Views/` and wire it into
`RootView`. Read/observe shared state via `@EnvironmentObject var model: AppModel`. When
presenting a sheet, re-inject the model (`.environmentObject(model)`) to be safe.

**Persist something new.** Add the method to the `HealthStore` protocol, then implement
it in **both** `FileHealthStore` (App) and `InMemoryHealthStore` (EmberCore). Storage is
plain JSON keyed by `DayKey` where it's per-day.

**Change reminders.** Defaults live in `ReminderSettings.default`. Scheduling is in
`NotificationService.sync` (repeating daily local notifications). The coach can edit
times via the `set_reminder` tool.

**Read from Apple Health.** `App/Ember/Services/HealthService.swift` is the only HealthKit
importer: a `HealthAccess` protocol (no HealthKit types in its signature) with a real
`HealthKitAccess` and a `NoopHealthAccess` (previews / non-iOS). `AppModel` injects it
(`init(... health:)`) and exposes `isHealthDataAvailable` + `requestHealthAccess()`; the
Settings "Apple Health" control requests read authorization. This is the injection seam to
extend when adding Health *reads* (prefer-Health-else-manual) — add read methods to
`HealthAccess` and a query body to `HealthKitAccess`, keeping EmberCore HealthKit-free.
The read methods return EmberCore value types (`HealthWeightSample`/`HealthWorkout` in
`Sources/EmberCore/Models/HealthSamples.swift`), and the pure prefer-Health-else-manual
decision lives in `HealthMerge` (`Sources/EmberCore/Logic/HealthMerge.swift`):
`currentWeightKg(health:manual:)` (most-recent Health body mass else manual) and
`mergedWorkouts(manual:health:) -> MergedWorkoutHistory` (manual passed through unchanged for
the per-exercise charts, plus a deduped, newest-first Health summary). `AppModel.refreshHealthData()`
caches the samples (`healthWeights`/`healthWorkouts`) on foreground / after grant; `currentWeightKg`
and `workoutHistory` surface the merged result. Health never feeds `MacroMath`.

## Privacy model (please keep)

All health data is local JSON in `ApplicationSupport/Ember/`. The only network egress is
the coach calling the Anthropic API directly with the user's **own** key (Keychain). No
backend, no analytics, no accounts. The coach gives general fitness info, not medical
advice. Durable coach memory is no exception — it's just another on-device JSON file
(`coach-memory.json`), with no new egress beyond the system prompt the coach already sees.
If you add features, keep data on-device unless the user explicitly opts in.

## Good first extensions

- A small UI to view/edit coach memory (the `CoachMemory` store + `AppModel` wrappers are
  already there — this is just a screen over them).
- Favoriting exercises, to extend the `RecentExercises` quick-add surface (food already has
  favorites; workouts only have recents).
- Streaming chat responses (the client is non-streaming today).
- Barcode scanning → a food lookup (would add a data source / network — gate it).
- A bigger / sourced food database (the current ~140 are hand-curated approximations).
- Built-in progression suggestions in workouts (today the coach does this on request).
- Editable macro-goal override UI (the model + store already support an override).

## A note on the current state

The `EmberCore` logic is unit-tested, but the SwiftUI app has not yet been compiled on a
Mac (it was written on Linux). Run `swift test` first, then build in Xcode and expect to
fix a few small things on the first compile.
