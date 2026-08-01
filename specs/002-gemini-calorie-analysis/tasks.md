---

description: "Task list for Photo Calorie Analysis"
---

# Tasks: Photo Calorie Analysis

**Input**: Design documents from `/specs/002-gemini-calorie-analysis/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md. Builds on feature 001 (camera capture / Send button).

**Tests**: Unit tests ARE included — the constitution (Principle II) mandates unit
tests for the calorie math, response decoding, and the store state machine.
**UI tests (XCUITest) are excluded** (off by default); accessibility identifiers
are still added so flows are UI-testable later.

**Organization**: Tasks grouped by user story. The app target uses filesystem-
synchronized Xcode groups, so new files under `Kalorias/` are picked up
automatically; new files under `KaloriasTests/` are added to the test target.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 / US2 / US3

---

## Phase 1: Setup (Shared Infrastructure)

- [x] T001 Create `Config/Secrets.example.xcconfig` (committed, `GEMINI_API_KEY = ` + `GEMINI_MODEL = gemini-2.5-flash` placeholders) and `Config/Secrets.xcconfig` (real values); add `Config/Secrets.xcconfig` to `.gitignore`
- [x] T002 Set `Config/Secrets.xcconfig` as the base configuration for the `Kalorias` target (Debug + Release) and expose `GEMINI_API_KEY` / `GEMINI_MODEL` to the app's Info.plist as `GeminiAPIKey` / `GeminiModel` (build-setting driven; if the generated Info.plist does not propagate custom keys, add a checked-in Info.plist entry referencing `$(GEMINI_API_KEY)`)
- [x] T003 [P] Add the analysis localization keys (EN + ES) to `Kalorias/Resources/Localizable.xcstrings` (`analysis.analyzing`, `analysis.totalLabel`, `analysis.kcalUnit`, `analysis.done`, `analysis.cancel`, `analysis.retry`, `analysis.retake`, `analysis.noFood`, `analysis.error.noConnection`, `analysis.error.timeout`, `analysis.error.service`, `analysis.error.invalidResponse`, `analysis.macro.protein`, `analysis.macro.carbs`, `analysis.macro.fat`)
- [x] T004 [P] Create the folders `Kalorias/Features/Analysis/` and `Kalorias/Support/`
- [x] T005 [P] Create `Kalorias/Support/AppSecrets.swift` reading `GeminiAPIKey` / `GeminiModel` from `Bundle.main` (nil-safe, no force-unwrap)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Domain types and the aggregation + service boundary that every story depends on.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [x] T006 [P] Create the domain models `FoodItem`, `CalorieAnalysis`, `AnalysisOutcome` (`Sendable`, `nonisolated`) in `Kalorias/Features/Analysis/CalorieAnalysis.swift`
- [x] T007 [P] Create the `AnalysisError` enum (`noConnection`, `timeout`, `serviceError`, `invalidResponse`) in `Kalorias/Features/Analysis/AnalysisError.swift`
- [x] T008 [P] Create the `CalorieAnalyzing` protocol (`Sendable`, `func analyze(imageData: Data) async throws -> AnalysisOutcome`) in `Kalorias/Features/Analysis/CalorieAnalyzing.swift`
- [x] T009 Create `CalorieAggregator` (pure: `total(of:)` = Σ calories; `make(from:)` → `.noFood` when empty else `.success`) in `Kalorias/Features/Analysis/CalorieAggregator.swift` (depends on T006)

**Checkpoint**: Domain + boundary ready.

---

## Phase 3: User Story 1 - See the calorie total (Priority: P1) 🎯 MVP

**Goal**: Tap Send → loading → prominent total kcal (= sum of detected foods) → Done returns to main.

**Independent Test**: Capture a plate, tap Send, see a loading state then a single clearly-labeled total that equals the summed foods; Done returns to the main screen.

### Tests for User Story 1

- [x] T010 [P] [US1] `CalorieAggregatorTests` in `KaloriasTests/CalorieAggregatorTests.swift`: total = Σ items; single item; empty ⇒ `.noFood`
- [x] T011 [P] [US1] `CalorieAnalysisDecodingTests` in `KaloriasTests/CalorieAnalysisDecodingTests.swift`: decode the success + no-food fixtures from `contracts/gemini-response.schema.md` (including optional macros); malformed / negative-calorie / missing-required payloads ⇒ `AnalysisError.invalidResponse`
- [x] T012 [US1] `CalorieAnalysisStoreTests` in `KaloriasTests/CalorieAnalysisStoreTests.swift`: with a mock `CalorieAnalyzing`, `start()` goes `analyzing → result`; a second `start()` while analyzing does not launch a concurrent analysis (single-flight, FR-014); `cancel()` ends the flow

### Implementation for User Story 1

- [x] T013 [US1] Create `GeminiCalorieService` (`Sendable`) in `Kalorias/Features/Analysis/GeminiCalorieService.swift`: build the `generateContent` request (inline image + prompt + `responseMimeType`/`responseSchema` per `contracts/gemini-response.schema.md`), `URLSession` POST off-main, decode wire DTOs, map via `CalorieAggregator`, and map failures to `AnalysisError` (depends on T006–T009)
- [x] T014 [US1] Create `CalorieAnalysisStore` (`@MainActor @Observable`) in `Kalorias/Features/Analysis/CalorieAnalysisStore.swift`: `state` (`analyzing`/`result`/`noFood`/`failed`), `start()`/`retry()`/`cancel()` running the injected analyzer in a cancelable `Task`, single-flight (depends on T008)
- [x] T015 [US1] Create `AnalysisResultView` in `Kalorias/Features/Analysis/AnalysisResultView.swift` for the `analyzing` and `result` states: photo thumbnail + spinner + Cancel; prominent total kcal + Done; native Liquid Glass surfaces, `AppColor` tokens, localized copy, a11y ids `analysis.screen`/`analysis.loading`/`analysis.cancelButton`/`analysis.total`/`analysis.doneButton`
- [x] T016 [US1] Modify `Kalorias/Features/Camera/CameraCaptureView.swift` so **Send** stops the session, builds `CalorieAnalysisStore(imageData:, analyzer: GeminiCalorieService(...))` from the captured image, and presents `AnalysisResultView`; Done/Cancel dismiss the whole camera flow via `Router.dismissCamera()`

**Checkpoint**: Happy-path photo → total works end-to-end.

---

## Phase 4: User Story 2 - See what foods were detected (Priority: P2)

**Goal**: Show the itemized breakdown (name, kcal, and macros when available) that sums to the total.

**Independent Test**: With a multi-food photo, the result lists each food with its kcal (and macros), and the items sum to the displayed total.

### Implementation for User Story 2

- [x] T017 [US2] Extend `AnalysisResultView` (`Kalorias/Features/Analysis/AnalysisResultView.swift`) with an itemized food list under the total: each row shows name + kcal, and protein/carbs/fat when present using `AppColor.macroProtein/macroCarbs/macroFat`; a11y id `analysis.foodList` (item macro decoding is already covered by T011)

**Checkpoint**: Total + trustworthy breakdown shown together.

---

## Phase 5: User Story 3 - Recover from failures (Priority: P3)

**Goal**: Clear, specific messages + Retry/Cancel for every failure; "no food" is distinct from 0 kcal; never show a fabricated number.

**Independent Test**: Trigger no-connection, timeout, service/invalid response, and no-food; confirm each shows the right message and actions, and Retry re-analyzes the same photo.

### Tests for User Story 3

- [x] T018 [US3] Extend `KaloriasTests/CalorieAnalysisStoreTests.swift`: mock analyzer throwing each `AnalysisError` ⇒ `failed`; mock returning `.noFood` ⇒ `noFood`; `retry()` returns to `analyzing` and re-runs with the same image
- [x] T019 [P] [US3] `CalorieAnalysisErrorMappingTests` in `KaloriasTests/CalorieAnalysisErrorMappingTests.swift`: `URLError.notConnectedToInternet`/`.networkConnectionLost` ⇒ `noConnection`; `.timedOut` ⇒ `timeout`; non-2xx/API error ⇒ `serviceError`; decode failure ⇒ `invalidResponse`

### Implementation for User Story 3

- [x] T020 [US3] Extend `AnalysisResultView` (`Kalorias/Features/Analysis/AnalysisResultView.swift`) with the `noFood` state (message + Retake + Cancel, a11y ids `analysis.noFoodMessage`/`analysis.retakeButton`) and the `failed` state (specific localized message + Retry + Cancel, a11y ids `analysis.errorMessage`/`analysis.retryButton`); no calorie number is shown in either
- [x] T021 [US3] Configure a request timeout in `GeminiCalorieService` and wire Retry → `store.retry()`, Cancel/Retake → `store.cancel()` + `Router.dismissCamera()` in `AnalysisResultView` / `CameraCaptureView`

**Checkpoint**: All failure paths handled; core loop is robust.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [~] T022 [P] Verify `AnalysisResultView` (all states) renders correctly in light and dark (Principle VI)
- [x] T023 [P] Verify Dynamic Type + VoiceOver labels and that a11y identifiers match `contracts/ui-contracts.md`
- [x] T024 Confirm the build succeeds with zero warnings under Swift 6 strict concurrency
- [x] T025 Confirm EN + ES values exist for every analysis key in `Kalorias/Resources/Localizable.xcstrings`
- [x] T026 Confirm `Config/Secrets.xcconfig` is git-ignored and no API key is committed anywhere
- [~] T027 Run the `quickstart.md` validation — unit suites on Simulator; the live Gemini happy path + failure paths on a physical device

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies.
- **Foundational (Phase 2)**: after Setup — BLOCKS all stories.
- **US1 (Phase 3)**: after Foundational (MVP).
- **US2 (Phase 4)**: after US1 (extends its result view).
- **US3 (Phase 5)**: after US1 (extends its store + result view); independently testable via the failure paths.
- **Polish (Phase 6)**: after the desired stories.

### Within Each User Story

- Write the unit test tasks first, watch them fail, then implement.
- Models/aggregator/protocol (Foundational) before service/store; store before view; view before camera wiring.

### Parallel Opportunities

- Setup: T003, T004, T005 in parallel.
- Foundational: T006, T007, T008 in parallel (T009 after T006).
- US1 tests: T010, T011 in parallel (T012 shares the store test file with US3, so sequential with T018).
- US3: T019 in parallel with T018/T020 (different file).
- Polish: T022, T023 in parallel.

---

## Parallel Example: Foundational

```bash
# Different files, no interdependencies:
Task: "Create domain models in Kalorias/Features/Analysis/CalorieAnalysis.swift"
Task: "Create AnalysisError in Kalorias/Features/Analysis/AnalysisError.swift"
Task: "Create CalorieAnalyzing protocol in Kalorias/Features/Analysis/CalorieAnalyzing.swift"
```

---

## Implementation Strategy

### MVP First (User Story 1)

1. Setup → 2. Foundational → 3. US1 → **STOP & VALIDATE** the photo → total loop
   on a device. Demoable core value.

### Incremental Delivery

1. Setup + Foundational → boundary ready.
2. US1 → total shown → demo (MVP).
3. US2 → breakdown → demo.
4. US3 → robust failure handling → demo.
5. Polish → constitution gates green.

---

## Notes

- [P] = different files, no dependencies.
- UI tests are intentionally absent (Principle II); a11y ids added for a future pass.
- The API key never enters the repo (`Config/Secrets.xcconfig` git-ignored).
- No persistence here; saving results to Progress/History is a later feature.
- Commits remain a manual human action per the constitution.
