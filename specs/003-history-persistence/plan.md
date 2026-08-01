# Implementation Plan: Meal History & Local Persistence

**Branch**: `003-history-persistence` | **Date**: 2026-07-24 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/003-history-persistence/spec.md`

## Summary

Persist every successful analysis (feature 002) locally and surface it in the
History tab (a placeholder since feature 001): a newest-first list of meals —
thumbnail, title (dish or ingredients), nutrition data, date, and total calories —
that drills into a details screen.

Technical approach (native, per constitution): **SwiftData** stores the meal
metadata (`@Model MealEntry`); the captured photo is written as a downsized JPEG
**file on disk** (referenced by name) so the store stays light and the list scrolls
at 60fps. A testable `MealHistoryRepository` owns writes, image IO, and the
pure title-derivation logic; the analysis store records a meal on success through a
`MealRecording` boundary. The list reads reactively via SwiftData `@Query`;
navigation to details is driven by the `Router` (NavigationStack). Native Liquid
Glass rows/cards, `AppColor` tokens (macro colors), EN+ES copy. No network.

## Technical Context

**Language/Version**: Swift 6 (strict concurrency `complete`, default MainActor isolation).

**Primary Dependencies**: SwiftData (`@Model`, `ModelContainer`, `@Query`),
SwiftUI, Observation, Foundation `FileManager` (image files), UIKit (`UIImage`
downsizing). Reuses feature 002's `CalorieAnalysis`/`FoodItem`. No third-party deps.

**Storage**: SwiftData store for meal metadata (date, foods, total, title, image
filename) + JPEG files under Application Support for the photos. Both on-device.

**Testing**: XCTest in `KaloriasTests` using an **in-memory** `ModelContainer`;
pure unit tests for title derivation and analysis→entry mapping; repository
save/fetch (newest-first) tests; image-store round-trip. UI tests OFF by default.

**Target Platform**: iOS 26.5+.

**Project Type**: Native iOS app (single SwiftUI target, filesystem-synchronized groups).

**Performance Goals**: History list visible < 1s and 60fps with ≥ 1,000 entries
(SC-002); saving/image IO never blocks the main thread (FR-012).

**Constraints**: photos NOT stored as DB blobs (files on disk, downsized); image
encode/write off the main thread; all copy EN+ES; native Liquid Glass + `AppColor`
tokens; correct light/dark; data never leaves the device (FR-015).

**Scale/Scope**: 1 `@Model` + 1 repository + reuse of feature 002 models; 3 screens
(list, row, details) + empty state; wiring the save into the analysis success path.

## Constitution Check

*GATE: evaluated against Kalorias Constitution v1.1.0. Re-checked after Phase 1.*

| Principle | Gate | Status |
|-----------|------|--------|
| I. Code Quality | Title derivation, analysis→entry mapping, and totals in testable types, not views; no force-unwrap. | ✅ `MealHistoryRepository` + pure `MealTitle`. |
| II. Testing (NON-NEG) | Unit tests: title derivation, mapping, repository save/fetch (in-memory container), image round-trip. UI tests off. | ✅ see contracts/data-model. |
| III. UX Consistency | HIG list; native Liquid Glass rows; `AppColor` (macro tokens); empty state; Dynamic Type/VoiceOver/a11y ids; tap→details via Router. Delete out of scope (no destructive action here). | ✅ `HistoryView`/`MealRowView`/`MealDetailsView`. |
| IV. Performance | Image encode/write off-main; no blobs in DB; list 60fps @ 1k entries. | ✅ file-backed images + `@Query`. |
| V. Architecture (NON-NEG) | Swift 6 strict; MV + Stores; SwiftData is the persistence store; writes behind `MealHistoryRepository`; navigation via Router. | ✅ reads via `@Query` (SwiftData's reactive read path), writes/logic in repository. |
| VI. Localization & Appearance (NON-NEG) | EN+ES; dark mode; tokens. | ✅ new keys in `Localizable.xcstrings`. |
| Tech Constraints | SwiftData is an explicitly-allowed native framework; on-device only, no network. | ✅ |

**Result**: All gates pass. No violations → Complexity Tracking empty.

## Project Structure

### Documentation (this feature)

```text
specs/003-history-persistence/
├── plan.md
├── research.md              # Phase 0
├── data-model.md            # Phase 1
├── quickstart.md            # Phase 1
├── contracts/
│   └── ui-contracts.md      # repository/store intents, screen states, a11y ids, l10n keys
├── checklists/requirements.md
└── tasks.md                 # /speckit-tasks (not created here)
```

### Source Code (repository root)

```text
Kalorias/
├── App/
│   ├── Router.swift                       # MODIFIED: history navigation path + openMeal intent
│   └── KaloriasApp.swift                  # MODIFIED: .modelContainer(...) + inject repository
├── Features/
│   ├── Camera/
│   │   └── CameraCaptureView.swift        # MODIFIED: pass the MealRecording recorder to the analysis store
│   ├── Analysis/
│   │   └── CalorieAnalysisStore.swift     # MODIFIED: record a meal on success via MealRecording
│   └── History/                           # NEW (replaces the placeholder)
│       ├── MealEntry.swift                 # @Model + StoredFood (Codable) value
│       ├── MealTitle.swift                 # pure title derivation (dish vs ingredients)
│       ├── ImageStore.swift                # downsize + write/read JPEG files on disk
│       ├── MealRecording.swift             # protocol boundary called on analysis success
│       ├── MealHistoryRepository.swift     # @MainActor: record()/fetch; owns ModelContext + ImageStore
│       ├── HistoryView.swift               # NavigationStack: list + empty state (@Query, newest-first)
│       ├── MealRowView.swift               # row: thumbnail | title+nutrition | date+total
│       └── MealDetailsView.swift           # details screen (larger photo + full breakdown)
├── App/RootView.swift                      # MODIFIED: History tab shows HistoryView
└── Resources/Localizable.xcstrings         # MODIFIED: history strings (EN+ES)

KaloriasTests/                              # add
├── MealTitleTests.swift
├── MealHistoryRepositoryTests.swift        # in-memory ModelContainer
└── ImageStoreTests.swift
```

**Structure Decision**: A new `Features/History/` module holds the SwiftData model,
the write-side repository (with the pure title logic and image IO), and the three
screens; feature 002's `CalorieAnalysis`/`FoodItem` are reused for the saved data.
Writes go through `MealHistoryRepository` (testable with an in-memory container);
reads use SwiftData `@Query` for reactive lists. The analysis store gains a
`MealRecording` dependency so a successful result is persisted automatically,
keeping the camera/analysis code unaware of SwiftData.

## Complexity Tracking

> No constitution violations. Section intentionally empty.
