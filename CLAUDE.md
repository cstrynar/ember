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
  `Services/{NotificationService,KeychainStore,AnthropicClient,AnthropicImage,CoachTools,CoachAgent}.swift`.
  `AnthropicImage.swift` (UIKit) builds the vision image content block + downscales/JPEG-encodes
  a `UIImage` to base64 (`VisionImage`); `AnthropicClient.sendVision` posts photo+text via the
  shared `post` path.
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
- Mid-pivot from a prior self-care app. Done: P0–P5 (teardown, nutrition core, nutrition UI,
  workouts, coach agent, friction log + weekly review via Coach Notes). v1-polish roadmap is
  an 8-stage pass (see `runs/20260618-0204-ember-v1-polish/ROADMAP.md`).
- **Photo-macros roadmap (4 stages, `runs/20260618-1514-ember-photo-macros/`):** add
  "estimate macros from a food photo" via Claude vision. Stage 1 = client image plumbing
  (done, below); Stage 2 = pure-`EmberCore` response parser + fixtures (done, below);
  Stage 3 = capture/UI + log via `AppModel`/`FoodEntry`; Stage 4 = on-device verify.
- **Photo-macros Stage 1 (image content-block plumbing) done:** new
  `App/Ember/Services/AnthropicImage.swift` — `VisionImage { base64; mediaType }`, a pure
  `imageContentBlock(_:)` emitting `{"type":"image","source":{"type":"base64",
  "media_type":...,"data":...}}` over the existing `[String: Any]` block shape, and
  `encodeForVision(_ image: UIImage) -> VisionImage?` (first UIKit import) that downscales the
  longest edge to ≤ 1568 px, JPEG-encodes from quality 0.7 stepping down toward 0.3 if over a
  ~4.5 MB budget, base64s, and reports `media_type: image/jpeg`. `AnthropicClient` gains an
  additive `sendVision(systemPrompt:userText:image:model:)` (default `claude-sonnet-4-6`, no
  tools) that posts one user message `content:[imageBlock, textBlock]`; `send`'s HTTP/decode
  body was factored into a behavior-preserving private `post(body:)` shared by both paths (same
  endpoint, headers, `max_tokens` 1500, `CoachError` map, `AnthropicResponse` decode). The
  `CoachBackend` protocol, `CoachAgent`, `ChatStore`, `send`'s signature, and `project.yml` are
  untouched; `EmberCore` untouched; no new network egress. `sendVision` has no caller yet (the
  Stage-3 seam) and returns raw `assistantText`.
- **Photo-macros Stage 2 (pure vision-response parser) done:** new
  `Sources/EmberCore/Logic/PhotoMacroParser.swift` — pure, `Foundation`-only. Public types:
  `EstimatedFoodItem { name; serving; macros: Macros }` (+ `asFoodItem(id:source:)` mapping
  `macros → macrosPerServing`, `serving → servingDescription` — the Stage-3 seam),
  `EstimateUncertainty` (`low/medium/high/unknown`, `init(rawString:)` → `.unknown` fallback),
  `PhotoMacroResult { items; assumptions; uncertainty }`, `PhotoMacroParseError`
  (`.notJSON/.malformed/.noItems`), and `PhotoMacroEstimate` (`.success/.failure`).
  `PhotoMacroParser.parse(_ assistantText:) -> PhotoMacroEstimate` (enum namespace, mirrors
  `MacroMath`) extracts the first balanced `{…}` object via a string-literal-aware brace scan
  (handles prose / ```json fences), decodes a private alias-tolerant `Decodable` DTO
  (`WireItem`/`WireResponse`: `kcal`, `protein`/`carb`/`carbs`/`fat`, `note`/`notes` aliases;
  missing macros → 0), drops nameless items, clamps macros `>= 0`, and returns a typed
  failure (never throws/crashes). Fixture-covered by `Tests/EmberCoreTests/PhotoMacroParserTests.swift`
  (inline `"""…"""` JSON: multi-item w/ prose+fence, single-item w/ aliases, malformed/garbage,
  uncertainty fallback, `asFoodItem`). Two new files; no App/`Package.swift`/`project.yml`
  change; no caller yet (Stage 3 feeds `assistantText` in).
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
- **Coach keyboard-dismiss fix done** (`runs/20260618-2003-coach-keyboard-dismiss`):
  `CoachView` got a `@FocusState private var inputFocused` bound to the input `TextField`
  (`.focused($inputFocused)`), `.scrollDismissesKeyboard(.interactively)` on the conversation
  `ScrollView`, and a keyboard accessory `.toolbar { ToolbarItemGroup(placement: .keyboard) {
  Spacer(); Button("Done") { inputFocused = false } } }` on `chatBody` — so the keyboard no
  longer traps the user over the bottom tab bar. All iOS-16-safe; `CoachView.swift`-only; send/
  thinking/error/auto-scroll/clear-conversation untouched.
- **HealthKit Stage 1 (auth plumbing) done** (`runs/20260618-1508-ember-healthkit`): first of
  a 4-stage HealthKit roadmap. Reads NO Health data yet (stage 2) and adds NO coach tool
  (stage 3). `App/project.yml` declares the `com.apple.developer.healthkit` entitlement (generated
  to git-ignored `Ember/Ember.entitlements`) + `NSHealthShareUsageDescription` (read-only; no
  write/update entitlement or string). New `App/Ember/Services/HealthService.swift` is the **only**
  HealthKit importer: `HealthAccess` protocol (no HealthKit types in its signature) + real
  `HealthKitAccess` (requests read auth for the six v1 types — workouts, body mass, active energy,
  step count, resting HR, sleep — via `HKHealthStore.requestAuthorization(toShare: [], read:)`,
  swallowing all errors to a no-op) + `NoopHealthAccess` (previews / non-iOS). `AppModel` injects it
  (`init(... health: HealthAccess = HealthKitAccess())`) and exposes `isHealthDataAvailable` +
  fire-and-forget `requestHealthAccess()`; NOT auto-invoked from init/onForeground. `SettingsView`
  gains a `Section("Apple Health")` "Connect Apple Health" button (gated on `isHealthDataAvailable`)
  that calls it. No-op-on-deny guarantee: granting/denying/no-data never blocks or errors any manual
  flow. EmberCore imports no HealthKit; `swift test` stays green. No new network egress.
- **HealthKit Stage 2 (primary-with-fallback for weight + workouts) done** (`runs/20260618-1508-ember-healthkit`):
  Apple Health becomes the **primary** source for body weight + workouts, with manual entry as a
  byte-for-byte fallback. Pure EmberCore: new `Sources/EmberCore/Models/HealthSamples.swift`
  (`HealthWeightSample { date; weightKg }`, `HealthWorkout { id; dayKey; date; kind; durationMin;
  activeEnergyKcal? }` — additive summary, NOT synthetic sets) + `Sources/EmberCore/Logic/HealthMerge.swift`
  (`enum HealthMerge.currentWeightKg(health:manual:)` = most-recent Health body mass else manual;
  `mergedWorkouts(manual:health:) -> MergedWorkoutHistory { manual; health }` = manual passed through
  unchanged + Health deduped-by-`id`, newest-first), unit-tested in `Tests/EmberCoreTests/HealthMergeTests.swift`.
  App: `HealthAccess` gains two read methods returning EmberCore value types (no HealthKit in signature) —
  `recentBodyMass(daysBack:completion:)`/`recentWorkouts(daysBack:completion:)`; `HealthKitAccess` maps them
  via `HKSampleQuery` (`.bodyMass`→kg, `HKWorkout`→summary, `uuid`→id, `DayKey.key(for:startDate)`→dayKey,
  errors/empty→`[]`), `NoopHealthAccess`→`[]`. `AppModel` caches `healthWeights`/`healthWorkouts`
  (`@Published private(set)`), `refreshHealthData()` (180-day window) called from `onForeground()` + after
  `requestHealthAccess`, and exposes `currentWeightKg`/`workoutHistory`. Coach-context weight prefers Health
  (`CoachAgent.systemPrompt` + `CoachTools.getToday`'s profile `weight_kg` use `currentWeightKg ?? profile.weightKg`,
  + a `weight_source` hint). `TrainView` gains a read-only `Section("From Apple Health")`
  (`HealthWorkoutRow`) when `workoutHistory.health` is non-empty. Invariants: manual logging + `MacroMath`
  BMR/TDEE/goal untouched (Health never feeds macros); food/macros/hydration untouched; `WorkoutProgress` +
  its tests byte-for-byte unchanged (charts read only manual `[Workout]`); EmberCore imports no HealthKit;
  no new coach tool (that's Stage 3); no new network egress.
- **Coach×Health Stage 1 (`get_health_data` tool) done** (`runs/20260619-0052-ember-coach-health`):
  the Coach's first Apple Health read tool, over the SIX already-authorized streams (active energy,
  steps, resting HR, sleep — four new readers — + weight + Apple Health workouts, already cached).
  Pure EmberCore: `Sources/EmberCore/Models/HealthMetrics.swift` (`HealthQuantitySample { date;
  value }` — `value` unit is metric-per-caller: kcal/steps/bpm/asleep-min) +
  `Sources/EmberCore/Logic/HealthSummary.swift` (`enum HealthSummary` mirroring `HealthMerge`:
  `dailyTotals(_:) -> [DailyTotal]` group-by-`DayKey` sum, newest-day-first; `latestAndAverage(_:)
  -> LatestAndAverage`; `averageDailyTotal(_:) -> Double?`), unit-tested in
  `Tests/EmberCoreTests/HealthSummaryTests.swift`. App: `HealthAccess` gains four completion
  readers returning `[HealthQuantitySample]` (no HealthKit in signature) —
  `recentActiveEnergy`/`recentSteps`/`recentRestingHeartRate`/`recentSleep`; `HealthKitAccess`
  maps via a shared `quantitySamples(identifier:unit:)` (`HKSampleQuery`) + a sleep reader that
  keeps only `allAsleepValues` segments as per-segment minutes; `#else`/`NoopHealthAccess` → `[]`.
  `AppModel` adds four `@MainActor async recent*Samples(daysBack:)` wrappers (continuation-bridged,
  `health` stays private, NO new caches / no `refreshHealthData` change) + exposes
  `healthLookbackDays` (non-private static, the tool's clamp ceiling). `CoachTools` adds the
  `get_health_data` definition (optional `days`, default 7, max 180), an `async run(name:input:)`
  overload (handles `get_health_data`, delegates all else to the unchanged sync `run`), and a
  `getHealthData` handler → compact JSON (workouts count+recent, weight latest+trend, active
  energy today+avg, steps today+avg, resting HR latest+avg, sleep last-night+avg-per-night,
  `window_days`); `!isHealthDataAvailable` OR all six empty → one `noHealthDataMessage` (no
  fabricated numbers). `CoachAgent.run` now `await`s the dispatch; `systemPrompt` gains one
  get_health_data hint line. `get_recent_workouts` (manual only) untouched; `readTypes`/
  `project.yml`/`NSHealthShareUsageDescription` untouched (Stage 2). EmberCore imports no HealthKit;
  no new network egress. Stage 2 = the six NEW streams + `readTypes` widening.
- **Photo-macros UI Stage 1 (entry point + estimate seam) done** (`runs/20260618-1700-ember-photo-macros-ui`):
  wires the capture entry point + `AppModel.estimateMacros` async seam on top of the already-shipped
  plumbing (`AnthropicImage` encode/block, `AnthropicClient.sendVision`, pure `PhotoMacroParser`).
  `App/project.yml` adds `NSCameraUsageDescription` (camera path only; `PhotosPicker` needs no
  `NSPhotoLibraryUsageDescription`). `AppModel` gains `import UIKit`, two prompt constants
  (`photoEstimateSystemPrompt`/`photoEstimateUserText` eliciting the parser's JSON contract), the
  `@MainActor async estimateMacros(from:systemPrompt:userText:) -> PhotoMacroOutcome` seam (key guard
  `.noKey` → `encodeForVision` `.encodeFailed` → `sendVision` throw → `.requestFailed` →
  `PhotoMacroParser.parse` `.success`/`.parseFailed`; builds `AnthropicClient(apiKey:)` like
  `generateWeeklyReview`), and the App-layer enum `PhotoMacroOutcome`
  (`success/noKey/encodeFailed/parseFailed/requestFailed`). New `App/Ember/Views/CameraPicker.swift`
  (second App-layer UIKit import) is a minimal `UIViewControllerRepresentable` over
  `UIImagePickerController` (`.camera`) returning `.originalImage`. New
  `App/Ember/Views/PhotoEstimateView.swift` is the idle→loading→review→failure phase machine: idle
  shows a library `PhotosPicker` + a camera button gated on `isSourceTypeAvailable(.camera)` (no-key
  state mirrors `CoachView.noKey`), review renders parsed items **read-only** (name/serving/
  `P/C/F · kcal`) + assumptions/uncertainty, failure shows a message + "Try another photo".
  `QuickAddView` adds an "Estimate from photo" `NavigationLink` next to "Add a custom food".
  Review was read-only this stage (Stage 2 makes it editable/loggable). EmberCore/tests untouched.
- **Photo-macros UI Stage 2 (editable, confirm-to-log review) done** (`runs/20260618-1700-ember-photo-macros-ui`):
  turns `PhotoEstimateView`'s review phase into a fully editable, user-confirmed list. New private
  App-layer `EditableEstimateRow` (an `Identifiable` `UUID` mirror of `EstimatedFoodItem`:
  `name`/`serving` + four macro `String`s + `servings: Double`; `macros`/`contribution =
  macros.scaled(by: servings)`/`hasName`), seeded from the parsed result in `estimate(_:)`. The
  `review` body renders `ForEach($rows)` editable rows (name + serving + four decimal-pad macro
  fields via a copied `ManualFoodView` `macroField`, + a per-item `0.5…20` `Stepper`) with
  `.onDelete` swipe-to-delete; a `Notes` section (assumptions + a "Confidence" row —
  `uncertaintyLabel(.unknown)` now returns "Unknown" so all four states show); a segmented `Meal`
  picker (one meal for the plate, seeded `Meal.suggestedForNow()`); a "This adds" live
  `MacroSummaryView(consumed: liveTotal, goal: nil)` (`liveTotal = rows.reduce(.zero){ $0 +
  $1.contribution }`); and a `Log N item(s)` button (`canConfirm` = non-empty AND every row named)
  beside "Try another photo". `confirm()` logs each row via the EXISTING
  `app.logManual(name:macros:servings:meal:saveToLibrary:false)` path — same `FoodEntry` as manual
  entry, no parallel logging — then `onDone()` (dismiss). New `onDone: () -> Void = {}` seam threaded
  from `QuickAddView` (`PhotoEstimateView(onDone: { dismiss() })`). App-layer SwiftUI only, iOS-16-safe;
  `idle`/`loading`/`failure`, `PhotosPicker`/`CameraPicker`, no-key state, and `AppModel.estimateMacros`
  unchanged; EmberCore/tests/`project.yml`/`Package.swift` untouched; only network egress is the
  existing `sendVision` call (no new call sites).
- **Photo-macros UI Stage 3 (on-device verification gate) — CURRENT STATE** (`runs/20260618-1700-ember-photo-macros-ui`):
  final human verification gate for the capture → estimate → editable-review → confirm-log loop
  (camera + library). **No app code** — stages 1–2 shipped the whole feature. Deliverable is a
  single process checklist, `runs/20260618-1700-ember-photo-macros-ui/TEST-PASS.md` (kept in the
  run dir, NOT the shippable tree — same convention as the per-stage `PLAN-*.md` and the v1-polish
  `TEST-PASS.md`), walking Nimmy on a Mac + **physical iPhone** (camera + a real photo library
  need a device, not the simulator) through `swift test` (Step A — EmberCore untouched, names
  `PhotoMacroParserTests`) → `cd App && xcodegen generate` + Xcode device build/launch (Step B —
  first-compile caveat; `NSCameraUsageDescription`-in-`Info.plist` sub-check) → six per-criterion
  manual scripts (Step C) with all UI strings quoted verbatim against the shipped source
  (`PhotoEstimateView`'s "Estimate macros from a photo"/"Choose a photo"/"Take a photo"/
  "Estimating…"/"Estimated items"/"Confidence"/"Log N item(s)"/"Try another photo" + the no-key
  "Add your Anthropic API key"/"In Settings → Coach…" copy + the four failure messages;
  `QuickAddView`'s "Estimate from photo" entry; `FoodView`'s per-meal `Section(meal.title)`;
  `project.yml`'s `NSCameraUsageDescription` text): C.1 camera+library both reach an estimate,
  C.2 editable review (assumptions/uncertainty/all fields/swipe-delete/live "This adds" total),
  C.3 confirm logs via the existing `logManual` path into the Food tab's per-meal section while
  backing out logs nothing, C.4 camera gating + the `NSCameraUsageDescription` prompt (graceful
  library-only on a simulator), C.5 no-key state AND a blank-photo failure both surface clear
  non-crashing messages, C.6 the single Consolidated-revise-list instruction. Batched revise
  fixes land *after* this gate; the git-history squash (PLAN.md §12) is the only manual step left
  after that. Checklist-only — no `Sources/`/`Tests/`/`App/`/`Package.swift`/`project.yml` change.
- Swift toolchain not installed on this host — `swift build`/`swift test` are NOT run here;
  all Swift is written carefully but compile-unverified until a macOS/Linux Swift 5.9+ host.
- Git history will be collapsed into a clean initial commit before handoff (see PLAN.md §12).
