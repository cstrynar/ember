# Ember

A personal health coach for iOS — nutrition (weight/macros), workouts, and an
AI coach that can see your data, search the web for fitness info, and adjust your
reminders. Single-user, sideloaded via TestFlight — not an App Store product.

> **Status: v1 feature-complete, pending first compile on a Mac.** All phases in
> [`PLAN.md`](PLAN.md) are implemented. The `EmberCore` logic is unit-tested
> (`swift test`); the SwiftUI app was written on Linux and hasn't been built in Xcode
> yet — run `swift test` first, then expect a few small fixes on the first compile.
> To build on it, see [`EXTENDING.md`](EXTENDING.md).

## What it does (v1 goals)

- **Nutrition.** Set a goal (lose / maintain / gain) plus dietary preferences; Ember
  computes specific macro targets. Low-friction food logging against a preloaded food
  database, with custom items you can save for reuse. Meal and hydration reminders.
- **Workouts.** Log exercises / sets / reps / weight; see history and progress charts.
- **Coach.** A chat agent (Claude) with tools to read your nutrition & workout data,
  search the web for health/fitness info, and edit your reminder schedule. It keeps a
  friction log and, once a week, compiles a short report on what would make it more
  useful.

## Privacy & data

Local-first. All health data is stored in plain JSON on the device
(`ApplicationSupport/Ember/`). The only thing that leaves the device is what you send
the coach: your chat message plus the specific data it looks up, sent directly to the
Anthropic API. No third-party backend, no analytics, no telemetry, no accounts.

The coach requires your **own Anthropic API key**, entered in Settings and stored in
the iOS Keychain. Every other part of the app works fully offline. The coach provides
general fitness information, **not medical advice**.

## Architecture

Two layers, on purpose — so the logic is testable without Xcode:

- **`EmberCore`** (Swift package) — pure, deterministic domain logic and models
  (macro math, nutrition aggregation, food search, workout progress). No UIKit, no
  network. Fully covered by `swift test`.
- **`App/Ember`** (SwiftUI) — UI plus the side-effecting services: persistence,
  notifications, the Anthropic client + coach agent, Keychain.

```
Package.swift              # EmberCore Swift Package (library + XCTests)
Sources/EmberCore/         # pure logic + models (see PLAN.md for the module map)
Tests/EmberCoreTests/      # XCTest suite — runs via `swift test`
App/
  project.yml              # XcodeGen spec — generates Ember.xcodeproj
  Ember/                   # SwiftUI app (Coach / Food / Train / Settings)
```

## Develop

Run the core logic tests — no Xcode, no device needed:

```bash
swift test
```

Generate and open the app project (macOS + Xcode 15+):

```bash
brew install xcodegen
cd App && xcodegen generate && open Ember.xcodeproj
```

The `.xcodeproj` is git-ignored; always regenerate it from `App/project.yml`.
Bundle id is `com.nimmynurner.ember`; enable "automatically manage signing" with a
paid Apple Developer account, then Archive → Distribute → TestFlight.
