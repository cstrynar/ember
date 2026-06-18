# HANDOFF — Stage 3 (full-height layout verification)

## Goal
Verify each of the four tab roots (Food, Train, Coach, Settings) fills the full safe-area
height, and fix the one container that does not.

## Conclusion (verified by reading the SwiftUI)
- **FoodView / TrainView / SettingsView** are each `NavigationStack { List { ... } }`. A
  `List` is intrinsically height-filling, so these are correct as-is — left UNCHANGED (no
  speculative frames added).
- **CoachView.chatBody** fills via a greedy `ScrollViewReader { ScrollView { ... } }` with
  the `inputBar` pinned below inside `VStack(spacing: 0)`. The OS lifts the input bar above
  the keyboard. UNCHANGED (no edits inside the `if app.hasAPIKey` path) to preserve keyboard
  / input-bar behavior.
- **The one defect: `CoachView.noKey`** — a `VStack(spacing: 12)` of intrinsic-height views
  (icon + two `Text`s), no `Spacer`, no `frame`, so it collapsed to content height instead
  of filling the safe area. FIXED by adding `.frame(maxWidth: .infinity, maxHeight: .infinity)`
  to that VStack; default VStack alignment centers the content, reading as a normal empty
  state. No restyle.

## Files touched
- App/Ember/Views/CoachView.swift  (1-line frame on `noKey` VStack only)
- CLAUDE.md  (Stage 3 current-state bullet)
- HANDOFF.md (this file)

## Commits (on `pipeline/ember-v1-polish`)
- 3189e28 CoachView: no-key empty state fills full safe-area height
- (+ CLAUDE.md/HANDOFF refresh commit)

## Notes for reviewer
- Code diff touches only CoachView.swift; no model/view-model/store/coach-loop changes.
- Pushed/presented (non-tab-root) screens were out of scope per the plan.

## Commands run
None buildable — Swift toolchain absent on host (per project notes). Compile-unverified;
structure confirmed by reading the views.

## Known issues / next step
- Stage complete. Next is reviewer / verify phase; on-device build/run is Stage 8.
- WORKSPACE IS THE WORKTREE: `runs/20260618-0204-ember-v1-polish/worktree`. Edit/commit there.
