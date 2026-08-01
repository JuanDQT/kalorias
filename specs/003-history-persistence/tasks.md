---

description: "Task list for Meal History & Local Persistence"
---

# Tasks: Meal History & Local Persistence

**Input**: Design documents from `/specs/003-history-persistence/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md. Builds on features 001 (camera) and 002 (analysis).

**Tests**: Unit tests ARE included — the constitution (Principle II) mandates unit
tests for the title derivation, image store, and repository save/fetch logic.
**UI tests (XCUITest) are excluded** (off by default); accessibility identifiers
are still added so flows are UI-testable later.

**Organization**: Tasks grouped by user story. New files under `Kalorias/` are
picked up automatically (synchronized groups); new `KaloriasTests/` files are added
to the test target.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 / US2 / US3

---

## Phase 1: Setup (Shared Infrastructure)

- [x] T001 [P] Add the history localization keys (EN + ES) to `Kalorias/Resources/Localizable.xcstrings` (`history.title`, `history.empty.title`, `history.empty.message`, `history.kcalUnit`, `mealDetails.title`, `mealDetails.totalLabel`, `mealDetails.takenAt`; reuse the existing `analysis.macro.*` keys for macros)
- [x] T002 [P] Create the folder `Kalorias/Features/History/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Persistence model, image storage, and the write-side repository that every story depends on.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [x] T003 [P] Create the SwiftData model `MealEntry` (`@Model`: id, capturedAt, title, totalCalories, foods, imageFileName) and the `StoredFood` Codable value (with `init(from: FoodItem)`) in `Kalorias/Features/History/MealEntry.swift`
- [x] T004 [P] Create pure `MealTitle.make(from: [FoodItem]) -> String` (single ⇒ name, multiple ⇒ comma-joined ingredients) in `Kalorias/Features/History/MealTitle.swift`
- [x] T005 [P] Create `ImageStore` (protocol + disk impl): `save(_:id:) async throws -> String` (downsize ~1024px, JPEG-encode + write off-main to Application Support/MealImages), `loadImage(named:) -> UIImage?` (nil if missing), `delete(named:)` in `Kalorias/Features/History/ImageStore.swift`
- [x] T006 Create the `MealRecording` protocol (`record(image:analysis:date:) async`) and `MealHistoryRepository` (`@MainActor`, conforms to `MealRecording`): owns the `ModelContext` + `ImageStore`; `record(...)` writes the image, builds a `MealEntry` (title via `MealTitle`, total from analysis, `StoredFood` mapping) and inserts+saves; `entries()` fetches newest-first — in `Kalorias/Features/History/MealHistoryRepository.swift` (depends on T003–T005)
- [x] T007 Wire the SwiftData container in `Kalorias/KaloriasApp.swift` (`.modelContainer(for: MealEntry.self)`) and inject a `MealHistoryRepository` into the environment (depends on T003, T006)

**Checkpoint**: Persistence layer ready.

---

## Phase 3: User Story 1 - Every analyzed meal is saved automatically (Priority: P1) 🎯 MVP

**Goal**: Each successful analysis is persisted locally (photo + foods + total + date) and survives relaunch; failures/no-food save nothing.

**Independent Test**: Analyze a photo successfully, force-close and relaunch, and confirm the meal persisted; a no-food/error analysis creates no entry.

### Tests for User Story 1

- [x] T008 [P] [US1] `MealTitleTests` in `KaloriasTests/MealTitleTests.swift`: single food ⇒ its name; multiple ⇒ ingredient list (order preserved)
- [x] T009 [P] [US1] `ImageStoreTests` in `KaloriasTests/ImageStoreTests.swift`: save→load round-trip in a temp directory; missing file ⇒ nil
- [x] T010 [US1] `MealHistoryRepositoryTests` in `KaloriasTests/MealHistoryRepositoryTests.swift`: with an in-memory `ModelContainer`, `record(...)` inserts one entry with the right foods/total/title; a second `record` creates a distinct second entry (FR-004); `entries()` returns newest-first (FR-005)

### Implementation for User Story 1

- [x] T011 [US1] Add a `MealRecording?` recorder to `CalorieAnalysisStore` (`Kalorias/Features/Analysis/CalorieAnalysisStore.swift`) and call `record(image:analysis:date:)` exactly once when it reaches `.result` (never on `.noFood`/`.failed`, FR-003)
- [x] T012 [US1] In `Kalorias/Features/Camera/CameraCaptureView.swift`, read the `MealHistoryRepository` from the environment and pass it as the recorder when constructing `CalorieAnalysisStore`

**Checkpoint**: Successful analyses persist and survive relaunch.

---

## Phase 4: User Story 2 - Browse the meal history list (Priority: P2)

**Goal**: History tab shows saved meals newest-first (thumbnail | title + nutrition | date + total), with an empty state.

**Independent Test**: With saved meals, the History tab lists them newest-first with the specified layout; with none, the empty state shows.

### Implementation for User Story 2

- [x] T013 [US2] Add history navigation to `Kalorias/App/Router.swift`: a `historyPath` for a `NavigationStack` and an `openMeal(_:)` intent (used by rows to drill into details)
- [x] T014 [P] [US2] Create `MealRowView` in `Kalorias/Features/History/MealRowView.swift`: thumbnail (left, via `ImageStore`, placeholder if missing), title + nutrition data (center), date + total calories (right); `AppColor` tokens (macro colors), a11y ids `history.row`/`history.row.title`/`history.row.total`/`history.row.date`
- [x] T015 [US2] Create `HistoryView` in `Kalorias/Features/History/HistoryView.swift`: a `NavigationStack(path:)` bound to the Router with a `@Query(sort: \.capturedAt, order: .reverse)` list of `MealRowView`, and a clear empty state (a11y ids `history.list`/`history.empty`)
- [x] T016 [US2] Update `Kalorias/App/RootView.swift` so the History tab shows `HistoryView` instead of `HistoryPlaceholderView`

**Checkpoint**: The list displays saved meals and an empty state.

---

## Phase 5: User Story 3 - Open a meal's details (Priority: P3)

**Goal**: Tapping a row opens a details screen (larger photo, full breakdown, total, date).

**Independent Test**: Tap a meal → a new screen shows the larger photo, per-food breakdown with macros, total, and date; back returns to the list.

### Implementation for User Story 3

- [x] T017 [US3] Create `MealDetailsView` in `Kalorias/Features/History/MealDetailsView.swift`: larger photo (via `ImageStore`), itemized foods (name + calories + macros), total calories, and date/time; `AppColor` tokens + native Liquid Glass; a11y ids `mealDetails.screen`/`mealDetails.total`/`mealDetails.foodList`
- [x] T018 [US3] In `Kalorias/Features/History/HistoryView.swift`, make rows tappable (call `Router.openMeal`) and add `navigationDestination(for:)` presenting `MealDetailsView` for the selected entry (FR-009/FR-010)

**Checkpoint**: Meals drill into full details and back.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [~] T019 [P] Verify the history list and details render correctly in light and dark (Principle VI)
- [x] T020 [P] Verify Dynamic Type + VoiceOver labels and that a11y identifiers match `contracts/ui-contracts.md`
- [x] T021 Confirm the build succeeds with zero warnings under Swift 6 strict concurrency
- [x] T022 Confirm EN + ES values exist for every history key in `Kalorias/Resources/Localizable.xcstrings`
- [~] T023 Run the `quickstart.md` validation — unit suites on Simulator; the capture→analyze→save→browse→details flow on a physical device (offline check included)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies.
- **Foundational (Phase 2)**: after Setup — BLOCKS all stories.
- **US1 (Phase 3)**: after Foundational (MVP — the save).
- **US2 (Phase 4)**: after Foundational; independently testable (can seed entries) but naturally follows US1.
- **US3 (Phase 5)**: after US2 (extends `HistoryView` with the destination + tap).
- **Polish (Phase 6)**: after the desired stories.

### Within Each User Story

- Write the unit test tasks first, watch them fail, then implement.
- Model/aggregation/image (Foundational) before repository; repository before the recorder wiring; list before details navigation.

### Parallel Opportunities

- Setup: T001, T002 in parallel.
- Foundational: T003, T004, T005 in parallel (T006 after them, T007 after T006).
- US1 tests: T008, T009 in parallel (T010 after the repository exists).
- US2: T014 in parallel with T013 (different files).
- Polish: T019, T020 in parallel.

---

## Parallel Example: Foundational

```bash
# Different files, no interdependencies:
Task: "Create MealEntry @Model in Kalorias/Features/History/MealEntry.swift"
Task: "Create MealTitle in Kalorias/Features/History/MealTitle.swift"
Task: "Create ImageStore in Kalorias/Features/History/ImageStore.swift"
```

---

## Implementation Strategy

### MVP First (User Story 1)

1. Setup → 2. Foundational → 3. US1 → **STOP & VALIDATE** that a successful
   analysis persists and survives relaunch (even before the list UI exists — verify
   via the repository/tests). The durable save is the MVP.

### Incremental Delivery

1. Setup + Foundational → persistence ready.
2. US1 → auto-save → validate persistence (MVP).
3. US2 → history list → demo.
4. US3 → details screen → demo.
5. Polish → constitution gates green.

---

## Notes

- [P] = different files, no dependencies.
- UI tests are intentionally absent (Principle II); a11y ids added for a future pass.
- Photos are stored as downsized files on disk, not DB blobs (FR-012/SC-002).
- Data stays on-device; no network in this feature (FR-011/FR-015).
- Delete/edit is out of scope; commits remain a manual human action per the constitution.
