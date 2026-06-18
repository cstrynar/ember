# Ember — Personal Health Coach — Build Plan (v1)

> Status: **implemented (P0–P6).** All phases below are built on this branch and the
> decisions in §11 are locked. `EmberCore` is unit-tested; the SwiftUI app is pending its
> first Mac compile. This doc is kept as the design record — edit it as the app evolves.

## 0. Design posture, honestly

Ember is a **local-first, bring-your-own-key** health coach. The defining constraints:

| Concern | Decision |
| --- | --- |
| AI surface | A chat coach powered by the Claude API |
| Network | Outbound HTTPS to `api.anthropic.com` only (chat + web search) |
| Accounts | None — an Anthropic **API key** lives in the Keychain |

What this buys, and what it deliberately preserves:

- **Local-first data.** All health data stays in on-device JSON files. Only the
  text of a chat turn plus the specific data the coach looks up is sent to the API.
  No third-party backend, no analytics, no telemetry, no sync.
- **The two-layer architecture**: pure testable `EmberCore` + thin side-effectful App.
  This is the single most important thing to preserve, because it's what lets your
  friend extend the app with `swift test` and no Xcode.

**Out of scope by decision:** anything clinical. The only safety text is a single,
plain "general fitness info — not medical advice" line in the coach's system prompt
and Settings.

## 1. Locked decisions (from our Q&A)

1. **Agent runtime: in-app, direct Claude API.** The literal Anthropic Agent SDK
   (Node/Python) can't run on iOS, so we implement the agent loop in Swift against
   the Messages API. Same behavior (tool use, web search), no server. The seam is
   designed so the friend can later add a real Agent-SDK companion script if wanted.
2. **API key: each user brings their own**, entered in Settings, stored in the iOS
   Keychain. Nothing hardcoded, no shared bill, no proxy.
3. **Workouts v1: log + progress charts.** Track exercises/sets/reps/weight, view
   history and simple progress. Recommendations come from the coach on request, not
   a built-in progression engine.

## 2. Target architecture

```
EmberCore (Swift package — pure, no UIKit, no network, fully `swift test`-able)
├─ Models/      profile, macro goal, food, food entry, hydration, workout, exercise…
├─ Logic/       MacroMath, NutritionLogic, FoodDatabase, WorkoutProgress, reminders
├─ Persistence/ store protocols + in-memory impls (for tests)
└─ Resources/   preloaded-foods.json (bundled)

App/Ember (SwiftUI + side effects)
├─ Persistence/ FileHealthStore (JSON in ApplicationSupport/Ember/)
├─ Services/    NotificationService, AnthropicClient, CoachAgent, KeychainStore
├─ ViewModels/  one per tab
└─ Views/       Coach, Food, Train, Settings
```

**Principle:** anything that can be a pure function lives in `EmberCore` with tests.
The App layer only does I/O — disk, notifications, network, Keychain, UI. The agent's
*tools* are thin App wrappers over `EmberCore` logic, so the brains stay testable.

## 3. Data model (EmberCore)

New `Codable, Equatable` types, following the existing style (plain structs, explicit
inits, no surprises):

- **`UserProfile`** — sex, age, heightCm, weightKg, activityLevel (sedentary…athlete),
  goal (`lose | maintain | gain`), dietary prefs (e.g. `highProtein`, `lowCarb`,
  `vegetarian` — a small enum set, free-text notes for the coach).
- **`MacroGoal`** — kcal, proteinG, carbG, fatG. Derived from profile but overridable.
- **`FoodItem`** — id, name, servingDescription, per-serving kcal/protein/carb/fat,
  `source: preloaded | custom`.
- **`FoodEntry`** — dayKey, timestamp, foodID *or* inline macros, servings, meal
  (`breakfast | lunch | dinner | snack`).
- **`DayNutrition`** — aggregates a day's entries; computes consumed vs goal, remaining.
- **`HydrationEntry` / `DayHydration`** — simple ml/cups counter with a daily target.
- **`Exercise`** — id, name, category (`strength | cardio | mobility`), primary muscle.
- **`WorkoutSet`** — reps, weightKg, optional RPE.
- **`WorkoutExercise`** — exerciseID + `[WorkoutSet]`.
- **`Workout`** — dayKey, `[WorkoutExercise]`, notes.

## 4. Core logic (EmberCore, all unit-tested)

- **`MacroMath`** — Mifflin–St Jeor BMR → × activity factor → TDEE → goal adjustment
  (−/+ kcal) → macro split honoring dietary prefs. Deterministic, citations in
  comments, tested against hand-computed values. This is the heart of "set specific
  macro goals."
- **`NutritionLogic`** — aggregate entries → `DayNutrition`; remaining macros; simple
  "what to eat next" gap (e.g. "~40g protein left") that the coach can phrase warmly.
- **`FoodDatabase`** — load bundled JSON, prefix/fuzzy search by name, merge custom
  foods, dedupe. Powers low-friction lookup.
- **`WorkoutProgress`** — per-exercise history series, estimated 1RM (Epley), total
  volume per session, simple progress series for charts.
- **Reminders (generalize the existing scheduler).** Today's scheduler is per-checklist-item,
  future-only, non-repeating. We extend it to support **recurring daily** meal and
  hydration reminders (`UNCalendarNotificationTrigger(repeats: true)`), still driven
  by a pure `EmberCore` function producing `[ScheduledReminder]`, still vetted against
  the no-nag copy rules.

## 5. The coach agent (App layer)

- **`AnthropicClient`** — small async Messages API client behind a protocol (so the
  agent loop is testable with a mock). Supports the tool-use loop and the server-side
  `web_search` tool. Streaming is optional for v1 (see open decisions).
- **`CoachAgent`** — owns the system prompt (coach persona: warm, non-clinical, no
  guilt; explicit "not medical advice"), the tool registry, and the loop:
  call API → run any `tool_use` locally → append `tool_result` → repeat → final text.
- **Tools exposed to the coach (v1 minimal set):**
  - `get_profile_and_goals()`
  - `search_food_database(query)`
  - `log_food(name|foodID, servings, meal)` ← chat-based logging = the lowest-friction path
  - `get_nutrition_summary(date | range)`
  - `get_workouts(range)` / `log_workout(...)`
  - `get_reminders()` / `set_reminder(type, time)` / `remove_reminder(type)` ← the
    "skill to edit the reminder schedule"
  - `web_search(query)` (Anthropic server tool — fitness/health lookups)
  - `append_friction_log(note)`
- **Context discipline:** the coach is given a compact summary (profile, today's
  numbers, recent workouts), not the whole history, to keep tokens — and cost — low.
- **Non-streaming with a "thinking…" indicator.** v1 waits for the full reply, but the
  chat shows an animated thinking state while the request (including any tool calls and
  web search) is in flight, so it never looks frozen or broken.
- **`KeychainStore`** — read/write the API key. Settings has a field to paste it.
  Missing key → Coach tab shows a friendly "add your key to chat" state; **every other
  tab works fully offline.**

## 6. Friction log + weekly review

- The coach appends to `friction-log.jsonl` (timestamp, context, note) whenever it or
  the user hits something clunky.
- **Weekly review (in-app, advisory).** Track `lastReviewDate` in UserDefaults; on
  foreground, if > 7 days, offer to run it. The coach is invoked with a *maintenance*
  prompt: read the friction log + a usage summary, then produce a short report —
  "what new info would be useful to gather, what could change" — saved to
  `reports/weekly-YYYY-MM-DD.md` and shown in a **Coach Notes** view.
- The report is **advisory** (it proposes changes for you/your friend to implement in
  code); the coach *can* directly adjust reminder times via its tool. This is the exact
  seam where the friend could later drop in a real Agent-SDK script for deeper,
  repo-aware maintenance.

## 7. Navigation

Replace the current Today/Log tabs with:

- **Coach** — the chat agent.
- **Food** — today's macros vs goal (rings/bars), quick-add (search → servings → log),
  recent/frequent items, hydration counter.
- **Train** — log a workout; history + progress charts (Swift Charts).
- **Settings** — profile & goals onboarding, API key, reminder times, Coach Notes,
  and the one-line non-medical disclaimer.

Quick-add and chat-logging both write the same `FoodEntry`, so "save a new item for
lookup" is just: log something not in the DB → offer to save it as a custom `FoodItem`.

## 8. Preloaded food database

Bundle `preloaded-foods.json` with ~150 common foods (name, serving, kcal/P/C/F),
hand-curated to keep size and licensing simple. Custom foods saved to
`custom-foods.json`, merged at search time. (USDA-scale DB and barcode scanning are
explicitly **out of scope for v1** — noted as a future seam.)

## 9. Phasing (each phase keeps `swift test` green and the app buildable)

- **P0 — Scaffolding.** Stand up the reusable bones: `DayKey`, the JSON store pattern,
  `NotificationService`, the app shell, icon, `project.yml`. Set up CLAUDE.md/README.
  Info.plist needs no ATS exception (HTTPS to Anthropic) and basic Keychain needs no
  entitlement.
- **P1 — Nutrition core (EmberCore).** Models + `MacroMath` + `NutritionLogic` +
  `FoodDatabase` + tests + bundled food JSON.
- **P2 — Nutrition UI.** Profile/goal onboarding, Food tab, quick-add, hydration,
  meal/water recurring reminders.
- **P3 — Workouts.** Models + `WorkoutProgress` + Train tab + charts.
- **P4 — Coach.** `AnthropicClient` + `CoachAgent` + tools + Keychain + Settings +
  Coach tab + web search.
- **P5 — Friction log + weekly review + Coach Notes.**
- **P6 — Polish & handoff.** `EXTENDING.md` for the friend, all tests green, then the
  Mac step: `swift test` → `xcodegen generate` → Archive → TestFlight.

## 10. Testing & risks

- **EmberCore stays fully unit-tested** — macro math against known values, progression,
  food search, nutrition aggregation, reminder scheduling. The network/agent layer is
  thin and sits behind a protocol so the loop is testable with a mocked client.
- **No Swift toolchain on this Ubuntu host** — everything Swift remains compile-unverified
  until the Mac. Keeping logic in tested `EmberCore` makes the Mac step mostly "does it
  compile," not "does it work."
- **Key hygiene** — API key never logged, never committed, redacted from any agent context.
- **Cost** — every chat turn and the weekly review spend tokens; lean context keeps it cheap.
- **Scope** — minimal on purpose. Clean seams > feature completeness, because the friend
  forks this next.

## 11. Locked decisions

1. **Scope is purely a health coach** — reminder/notification plumbing drives meals &
   hydration; nothing clinical. A full restart of any module is fine where it's cleaner
   than adapting.
2. **Food DB:** ~150 curated common foods for v1; barcode/USDA later.
3. **Name stays "Ember."**
4. **Weekly review:** in-app advisory report, shipping in this update.
5. **Chat:** non-streaming, with a "thinking…" indicator so it never looks broken.

## 12. Git history

History is collapsed into a clean initial commit (orphan root) before handoff, so the
repo ships with a single, tidy starting point. This is a **destructive, force-pushed**
rewrite — it happens once at the very end, with explicit confirmation before the
force-push. Until then, work stays local and nothing is pushed.
