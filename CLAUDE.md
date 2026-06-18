# Ember

## Purpose
Personal health-coach iOS app for a single user, sideloaded via TestFlight (not the App
Store). Three pillars: (1) nutrition — goal-driven macro targets, low-friction food
logging against a preloaded + custom food database, meal/hydration reminders;
(2) workouts — log exercises/sets/reps/weight, history + progress charts; (3) an AI
coach (Claude) with tools to read the user's data, web-search fitness info, and edit the
reminder schedule, plus a friction log and a weekly self-review report.

**Local-first, bring-your-own-key.** All health data is plain JSON on device
(`ApplicationSupport/Ember/`). The only network egress is the coach calling the Anthropic
API directly with the user's own key (stored in Keychain). No backend, no accounts, no
analytics. The coach gives general fitness info, not medical advice.

**The build is phased — `PLAN.md` is the source of truth** for design and phase order.

## Architecture map
- `Package.swift` — EmberCore library + EmberCoreTests; tools-version 5.9, iOS 16 / macOS 13.
- `Sources/EmberCore/` — pure, deterministic, network-free domain logic. Everything that
  *can* be a pure function lives here and is unit-tested. Models: `Macros`, `UserProfile`,
  `FoodItem`, `FoodEntry`, `DayNutrition`, `HydrationLog`, `DailyReminder`/`ReminderSettings`.
  Workouts: `Exercise`/`ExerciseCatalog`, `LoggedSet`/`Workout`, `WorkoutProgress` (Epley 1RM,
  volume, history). Logic: `MacroMath`, `FoodDatabase` (+ bundled `Resources/preloaded-foods.json`).
  Review: `FrictionEntry`, `CoachReport`. Coach memory: `CoachMemory`/`CoachMemoryItem` (durable
  facts + pure `adding`/`updating`/`removing`/`capped`/`promptLines`). Persistence: `HealthStore`
  protocol + `InMemoryHealthStore` (profile/goal, nutrition, hydration, workouts, custom
  foods/exercises, friction log, coach reports, reminders, coach memory). Util: `DayKey`.
- `App/Ember/` — SwiftUI + side effects. `EmberApp.swift` (@main, scenePhase rollover),
  `ViewModels/{AppModel,ChatStore}.swift`, `Persistence/FileHealthStore.swift`,
  `Services/{NotificationService,KeychainStore,AnthropicClient,CoachTools,CoachAgent}.swift`.
  Views: `RootView`, `FoodView`, `QuickAddView`, `ProfileView`, `SettingsView`,
  `ReminderSettingsView`, `TrainView`, `ProgressViews`, `CoachView`, `CoachSettingsView`,
  shared `Components`/`Formatting`.
- Coach loop: `ChatStore` → `CoachAgent.run` (tool-use loop over `CoachBackend`) → `CoachTools`
  (thin `@MainActor` wrappers over `AppModel`/`EmberCore`) + server-side `web_search`. Key in
  Keychain, model in UserDefaults (default `claude-sonnet-4-6`). The App target has no unit
  tests — `CoachBackend` is a protocol so the loop is mockable if a test target is added later.
- `App/project.yml` — XcodeGen spec; generates `App/Ember.xcodeproj` (git-ignored).
- `App/Ember/Assets.xcassets/AppIcon.appiconset/` — warm-orange flame icon (1024², no alpha);
  regenerate with `App/gen_icon.py` (Pillow, local, no network).

## Commands
```bash
# Run all EmberCore unit tests (no Xcode needed)
swift test

# Generate Xcode project from spec (macOS + XcodeGen required)
cd App && xcodegen generate && open Ember.xcodeproj
```

## Conventions & decisions
- Keep brains in `EmberCore` (pure, tested); the App layer only does I/O — disk, network,
  notifications, Keychain, UI. The coach's *tools* are thin App wrappers over EmberCore.
- `EmberCore` has zero networking/AI imports; the agent loop lives in the App layer only.
- Models are plain `Codable, Equatable` structs with explicit inits (match existing style).
- Persistence is local JSON in `ApplicationSupport/Ember/`, keyed by `DayKey` where daily.
- API key: user-supplied, Keychain-stored, never logged/committed/sent anywhere but the
  Anthropic API. App is fully usable offline; only the Coach tab needs the key.
- Chat is non-streaming with a "thinking…" indicator (v1).
- `App/Ember.xcodeproj` is git-ignored; always regenerate via `xcodegen generate`.
- Bundle id: `com.nimmynurner.ember`.

## Known issues / current state
- v1 core complete: P0–P5 (scaffolding, nutrition core, nutrition UI, workouts, coach agent,
  friction log + weekly review via Coach Notes). v1-polish roadmap is an 8-stage pass
  (see `runs/20260618-0204-ember-v1-polish/ROADMAP.md`).
- **Stage 1 (food one-tap re-log) done:** `RecentFood` snapshots `lastServings`/`lastMeal`;
  `AppModel.reLog`/`recent(forID:)`/`QuickAddEntry`; FoodView strip + QuickAddView
  Favorites/Recent rows one-tap re-log at prior servings+meal; LogFoodView prefills via
  `initialServings`/`initialMeal`; Edit affordance uses iOS-16-safe `.sheet(item:)`.
- **Stage 2 (workout one-tap re-log) done:** `RecentExercises`/`RecentExercise`
  (`Sources/EmberCore/Logic/RecentExercises.swift`) snapshot the newest workout's last set;
  `AppModel.recentExercises`/`recentExercise(forID:)`/`exercise(for:)`/`reLogSet`; `AddSetView`
  "Recent" section one-tap re-logs (Edit swipe → `SetEntryView` via iOS-16-safe `.sheet(item:)`);
  `SetEntryView` prefills via `initialReps`/`initialWeightKg`. Food-parity pass: Train-root
  "Quick add" chip strip (reuses `QuickAddChip`, now a `detail` string) one-tap re-logs from
  the tab root; `logSet`/`reLogSet` are `@discardableResult -> UUID` so both surfaces (strip
  chip + `AddSetView` Recent row, via an `onReLog` callback) show the same `UndoToast`/
  `.safeAreaInset` banner as food.
- **Stage 3 (full-height layout) done:** FoodView / TrainView / SettingsView are
  `NavigationStack { List }` (a List is height-filling — no change needed); `CoachView.chatBody`
  fills via a greedy `ScrollView` with the input bar pinned below in `VStack(spacing: 0)` (no
  change, keyboard behavior preserved). The only fix was `CoachView.noKey`, an unconstrained
  `VStack` that collapsed below full height; it now uses `.frame(maxWidth: .infinity,
  maxHeight: .infinity)` so the no-key empty state fills the safe area.
- **Stage 4 (durable coach memory) done:** `CoachMemory`/`CoachMemoryItem`
  (`Sources/EmberCore/Models/CoachMemory.swift`) are pure `Codable, Equatable` durable facts;
  `HealthStore.loadCoachMemory`/`saveCoachMemory` (default `.empty`) backed by
  `coach-memory.json` (file) + in-memory. `AppModel.coachMemory` (loaded in init) +
  `updateCoachMemory`/`rememberFact`/`updateFact`/`removeFact` (cap → persist → republish).
  `CoachTools` adds a `remember` tool (action add/update/remove) and exposes `coach_memory`
  (items with ids) in `get_today`; `CoachAgent.systemPrompt` folds saved memory in via
  `promptLines()` when non-empty, so it's present on every `ChatStore` send and survives a
  cleared conversation. No new network egress.
- **Stage 5 (clear-conversation control) done:** `ChatStore.reset()` flushes the in-memory
  conversation — `messages`, `private apiMessages`, `isThinking`, `errorText`, `draft` — leaving
  `apiMessages` private (view never touches it). `CoachView` adds a `.primaryAction` trash button
  (`accessibilityLabel("Clear conversation")`, gated on `app.hasAPIKey`, disabled when nothing to
  clear or while thinking) → iOS-16-safe `confirmationDialog` → `chat.reset()`. Durable
  `CoachMemory` is untouched and re-folds on the next send. No persistence/network change.
- **Stage 6 (optional profile fields) done:** reviewed `UserProfile`/`MacroMath` and added
  exactly one optional field — `goalWeightKg: Double?` (target body weight, kg). Coaching
  context only: it does NOT feed `MacroMath` (all BMR/TDEE/goal/macro math byte-for-byte
  unchanged). `nil` default + synthesized `Codable` so pre-Stage-6 `profile.json` still decodes
  (`HealthStoreTests.testProfileDecodesWithoutGoalWeightKey` guards this). Surfaced as one
  optional `ProfileView` "Target weight (kg)" row (prefills, round-trips, never gates `Save`),
  and folded into `CoachAgent.systemPrompt` + `CoachTools.getToday` (`goal_weight_kg`) only when
  set. Body-fat % and tunable deficit/surplus were considered and rejected as scope-padding /
  macro-model rewrites. No new tools, files, or network egress.
- **Stage 7 (docs) done:** `EXTENDING.md` refreshed to document the stage 1–6 extension seams
  (recents/quick-add for food + workouts, durable `CoachMemory` + the `remember` tool,
  `ChatStore.reset()`, the `goalWeightKg` profile precedent, the two-layer convention).
  Docs-only — no source/test/`project.yml` change.
- **Stage 8 (on-device test pass) — CURRENT STATE:** final human verification gate (no app
  code). Deliverable is a process checklist, `runs/20260618-0204-ember-v1-polish/TEST-PASS.md`
  (kept in the run dir, NOT the shippable tree — same convention as the per-stage `PLAN-*.md`),
  walking Nimmy on a Mac through `swift test` → `xcodegen generate` + Xcode build/launch → a
  per-feature manual script for each stage 1–6 deliverable (UI labels verified against source:
  Food/Train `Section("Quick add")` strips + `UndoToast`/`UndoSetToast`; `AddSetView`
  `Section("Recent")`; the `.primaryAction` "Clear conversation" trash + "Clear this
  conversation?" dialog; the `ProfileView` "Target weight" (kg) row), then pooling **all**
  findings into one consolidated revise list. The batched revise fixes land *after* this gate;
  the git-history squash (PLAN.md §12) is the only manual step left after that.
- Swift toolchain not installed on this host — `swift build`/`swift test` are NOT run here;
  all Swift is written carefully but compile-unverified until a macOS/Linux Swift 5.9+ host.
- Git history will be collapsed into a clean initial commit before handoff (see PLAN.md §12).
