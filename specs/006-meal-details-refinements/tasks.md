---

description: "Task list for Meal Details Refinements — Clearance, Colour Consistency & Ingredient Thumbnails"
---

# Tasks: Meal Details Refinements

**Input**: Design documents from `/specs/006-meal-details-refinements/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/ui-contracts.md](./contracts/ui-contracts.md), [quickstart.md](./quickstart.md)

**Tests**: Unit tests are **REQUIRED** for the geometry and decoding work. Constitution Principle II
(NON-NEGOTIABLE) mandates them for logic that converts values — and this feature converts
coordinates twice (Gemini 0–1000 → unit space → pixels), which is where the bugs live.
**UI tests stay OFF** (Principle II) — do not author or run XCUITest.

**Organization**: Tasks are grouped by user story so each can be implemented, tested and shipped
independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1 / US2 / US3 from spec.md
- Exact file paths are in every task

## Path Conventions

Native iOS app, single SwiftUI target. Sources under `Kalorias/`, tests under `KaloriasTests/`.

⚠️ New sources under `Kalorias/` are auto-included (filesystem-synchronized group).
**`KaloriasTests/` is NOT** — each new test file must be registered in `project.pbxproj`
(PBXBuildFile + PBXFileReference + the group's `children` + the target's `Sources` phase) or it
silently never runs, and the only symptom is a test count that does not grow. Each new test file
below has its own registration task immediately after it.

---

## Phase 1: Setup

**Purpose**: Establish the green baseline this feature must not regress

- [X] T001 Capture the green baseline: `xcodebuild -project Kalorias.xcodeproj -scheme Kalorias -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test` — record the count (expected **122 tests, 0 failures**). If the simulator reports `FBSOpenApplicationServiceErrorDomain ... Busy`, boot it first: `xcrun simctl boot "iPhone 17 Pro Max" && xcrun simctl bootstatus "iPhone 17 Pro Max" -b`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Intentionally empty.** The three stories touch largely disjoint files and none blocks the
others: US1 is confined to `RootView` + `ProgressTabView`, US2 to `HistoryView` +
`MealDetailsView`, US3 to the analysis and history layers. `MealDetailsView` is the only shared
file (US2 and US3 both edit it), which is a sequencing concern rather than a prerequisite — noted
under Dependencies. No filler tasks have been invented to populate this phase.

---

## Phase 3: User Story 1 - Read the whole ingredient list without the bottom bar in the way (Priority: P1) 🎯 MVP

**Goal**: Content on every screen can scroll clear of the floating bottom bar, so the last ingredient is readable.

**Independent Test**: Open a meal with enough ingredients to require scrolling, scroll to the very bottom, and confirm the last ingredient row is fully visible and not overlapped by the bottom bar.

### Implementation for User Story 1

- [X] T002 [US1] Fix the root cause in `Kalorias/App/RootView.swift`: move `BottomBar` out of the `ZStack` and into `.safeAreaInset(edge: .bottom) { BottomBar(...) }`. A `ZStack` sibling is invisible to the safe-area system, which is why no scroll view in the app insets for the bar and why the details screen has nowhere left to scroll (research R1). Keep the bar's appearance identical — native Liquid Glass, translucent, floating, horizontally inset (FR-003); keep the `AppColor.surfacePrimary.ignoresSafeArea()` background and the camera `fullScreenCover` untouched
- [X] T003 [US1] Delete the manual `.padding(.bottom, 96)` from `Kalorias/Features/Progress/ProgressTabView.swift` (and its "Clear the floating bottom bar" comment). It was compensating for the same root cause; leaving it in would make the Progress tab **doubly** inset. Principle I forbids keeping a hack beside its real fix (depends on T002)
- [X] T004 [US1] Build and run the full suite (`xcodebuild ... test`); confirm zero warnings and still **122 tests, 0 failures** — this story changes layout only, so any test change is a red flag
- [ ] T005 [US1] Validate quickstart.md **V1** on **all three** scrollable screens: meal details (last ingredient fully visible), the History list (last row fully visible), and the Progress tab (bottom of the chart card visible and **not** doubly inset — a large empty gap above the bar means T003 was skipped). Confirm content still passes *behind* the translucent bar while scrolling

**Checkpoint**: The reported defect is fixed app-wide and independently shippable — this is the MVP

---

## Phase 4: User Story 2 - The calorie total is coloured the same as in the list (Priority: P2)

**Goal**: The large calorie figure on the details screen uses the same colour step as the row the user tapped.

**Independent Test**: Note a meal's calorie colour in the history list, tap into its details, and confirm the large figure uses that same colour — repeated for a low (green) and a high (red) meal in the same week.

### Implementation for User Story 2

- [X] T006 [US2] In `Kalorias/Features/History/HistoryView.swift`, hoist the week grouping so both the list **and** the `navigationDestination(for: MealEntry.self)` closure read the same `[MealWeekGroup<MealEntry>]`. In the destination, find the tapped entry's group and compute its step with `CalorieColorScale.step(for:lowest:highest:)`, then pass it to `MealDetailsView`. **Do not re-derive the week bounds independently** — FR-006 forbids it, because a second implementation of "which week and what are its bounds" is exactly how the two screens drift apart. Feature 004's grouping partitions every entry, so the "group not found" path is unreachable; handle it with a documented `.low` fallback rather than a force-unwrap. The list's rows, order, headers and colours MUST be unchanged (FR-020)
- [X] T007 [US2] Change `MealDetailsView`'s signature in `Kalorias/Features/History/MealDetailsView.swift` to `init(entry:colorStep:imageStore:)` and use `colorStep.color` (the mapping added in feature 005) for the large calorie figure, replacing `AppColor.brandPrimary`. Leave the header photo, date line and total label untouched. The number stays plain text so colour is never the sole carrier (FR-008) (depends on T006)
- [X] T008 [US2] Build and run the full suite (`xcodebuild ... test`); confirm zero warnings and 122 tests still passing
- [ ] T009 [US2] Validate quickstart.md **V2**: within one week, the lowest meal matches green, the highest matches red, and a middle meal matches its yellow/orange — an exact match each time. Also open a meal from a single-meal week and confirm green, matching the list

**Checkpoint**: Colour means the same thing on both screens

---

## Phase 5: User Story 3 - See what each ingredient is at a glance (Priority: P3)

**Goal**: Each ingredient row shows a crop of the meal's own photo taken from where that food was detected, with a placeholder when no region exists.

**Independent Test**: Analyze a new photo with several distinguishable foods, open its details, and confirm most rows show a crop of that food, with placeholders for any the model did not box — and that a meal saved before this feature shows placeholders throughout without breaking.

### Geometry (pure, no UIKit)

- [X] T010 [P] [US3] Create `Kalorias/Features/Analysis/FoodRegion.swift`: a `nonisolated struct FoodRegion: Codable, Hashable, Sendable` with proportional `x`, `y`, `width`, `height` in unit space (`0...1`, origin **top-left**), plus two **failable** initializers — `init?(clampingX:y:width:height:)` and `init?(geminiTop:left:bottom:right:)`. Clamp edges into `0...1` first (a box a few units past the edge is still useful), then return `nil` when the clamped width or height is not positive; that single gate makes an invalid `FoodRegion` unconstructible (FR-015). The Gemini initializer divides by **1000** and maps **top→`y`, left→`x`**. **No UIKit or CoreGraphics import** — proportional, not pixels, because `DiskImageStore` saves a downsized JPEG and a pixel region would mis-crop by the downscale ratio (research R5)
- [X] T011 [US3] Create `KaloriasTests/FoodRegionTests.swift` covering all 13 cases in quickstart.md §"FoodRegionTests". The load-bearing one: **`geminiTop: 100, left: 500, bottom: 300, right: 900` must give `y == 0.1`, `x == 0.5`, `height == 0.2`, `width == 0.4`** — that is the test that catches an x/y swap, and a swap otherwise produces a valid-looking crop of the wrong part of the photo with no error anywhere (research R3). Also cover: whole image `(0,0,1,1)` valid, out-of-range clamped, zero/negative width and height → `nil`, inverted edges → `nil`, and a `Codable` round-trip
- [X] T012 [US3] Register `FoodRegionTests.swift` in `Kalorias.xcodeproj/project.pbxproj` and verify with `plutil -lint Kalorias.xcodeproj/project.pbxproj`

### Analysis pipeline

- [X] T013 [US3] Add `region: FoodRegion?` to `FoodItem` in `Kalorias/Features/Analysis/CalorieAnalysis.swift`, defaulting to `nil` so every existing construction site compiles unchanged. **Exclude it from `==`**, for the same reason `id` is excluded — two foods with the same nutrition are the same food regardless of where they were spotted (depends on T010)
- [X] T014 [US3] In `Kalorias/Features/Analysis/GeminiCalorieService.swift`, extend `responseSchema` with an `OBJECT` `box` on `foods.items` having **named** `ymin`/`xmin`/`ymax`/`xmax` INTEGER properties, and extend the prompt to request them on Gemini's **0–1000 normalized** scale measured from the top and left edges. **`box` MUST NOT be added to `foods.items.required`** — that single omission is what implements FR-021, so a response with no boxes still validates and still saves a meal. Named edges are used instead of Gemini's native `box_2d` array because that array is `[ymin, xmin, ymax, xmax]` — y first — and reading it pair-swapped fails silently (research R3)
- [X] T015 [US3] In `Kalorias/Features/Analysis/GeminiCalorieService.swift`, add `box` to the `FoodPayload.Food` wire DTO as an optional nested struct and map it through `FoodRegion(geminiTop:left:bottom:right:)` in `parseOutcome`. A missing, incomplete or malformed `box` MUST yield `region == nil` for that food while **the rest of the meal still parses** (FR-015, FR-021) — never throw `invalidResponse` because a decorative box was bad. Existing name/calories/macros behaviour is unchanged (depends on T013, T014)
- [X] T016 [US3] Extend `KaloriasTests/CalorieAnalysisDecodingTests.swift` with the 6 cases in quickstart.md §"CalorieAnalysisDecodingTests": payload without `box` (today's shape) decodes with `region == nil`; `box` on every food maps with correct orientation; `box` on only some foods; `box` missing an edge → that food `nil` but the meal parses; `box` with wrong value types → same; `box` out of range → clamped. No pbxproj change needed — this file is already registered

### Persistence

- [X] T017 [US3] Add `region: FoodRegion?` to `StoredFood` in `Kalorias/Features/History/MealEntry.swift`, and carry it through `init(from: FoodItem)` and `asFoodItem`. **No SwiftData migration and no store version bump**: foods are persisted as JSON inside the existing `foodsData` column, so an added optional decodes as `nil` on every existing row — verified during planning (research R4). Do not touch `MealEntry`'s stored properties (depends on T010, T013)
- [X] T018 [US3] Confirm `Kalorias/Features/History/MealHistoryRepository.swift` needs no change: it already maps `analysis.items.map(StoredFood.init(from:))`, so regions flow through once T017 lands. Verify by reading, and only edit if the mapping drops the field
- [X] T019 [US3] Add persistence cases to `KaloriasTests/MealHistoryRepositoryTests.swift`: a meal whose foods have regions survives save → fetch with regions intact; a meal whose foods have **no** regions saves normally with `region == nil` (FR-021); and a `foodsData` blob written **without** a `region` key decodes with `region == nil` (FR-017)

### Cropping

- [X] T020 [P] [US3] Create `Kalorias/Features/History/FoodThumbnailCropper.swift`: a `nonisolated enum` with `crop(_:to:maxDimension:) -> UIImage?` and `crops(for:from:maxDimension:) -> [UUID: UIImage]`. Crop with **`UIGraphicsImageRenderer` + `draw(in:)`, never `cgImage?.cropping(to:)`** — `CGImage` has no notion of `UIImage.imageOrientation`, and the stored JPEG is not guaranteed `.up` because `DiskImageStore.downsized` returns the original untouched when it is already small enough (research R6). Compute geometry against `image.size` (the orientation-corrected logical size), not `cgImage.width/height`. Cap output at `maxDimension`, preserve the region's aspect ratio, return `nil` for a zero-sized source, and skip foods with `region == nil` in `crops(for:)`. No force-unwraps
- [X] T021 [US3] Create `KaloriasTests/FoodThumbnailCropperTests.swift` covering the 8 cases in quickstart.md §"FoodThumbnailCropperTests", building source images synthetically as `ImageStoreTests` already does. The load-bearing one: **a non-`.up` oriented source must crop the same visible region as an `.up` source** — the test that catches `cgImage.cropping`. Also cover aspect ratio preserved (no stretching), `maxDimension` respected, whole-image region, zero-sized source → `nil`, mixed foods yielding entries only for those with regions, an all-`nil` set yielding an empty dictionary, and keys matching food ids
- [X] T022 [US3] Register `FoodThumbnailCropperTests.swift` in `Kalorias.xcodeproj/project.pbxproj` and `plutil -lint` it

### Details screen

- [X] T023 [US3] In `Kalorias/Features/History/MealDetailsView.swift`, produce all crops in **one detached pass** when the photo finishes loading, into a `@State private var thumbnails: [UUID: UIImage]` keyed by `StoredFood.id`. One pass over the already-in-memory image, not a `.task` per row — a 15-ingredient meal would otherwise do 15 extra decodes on top of the load the screen already does (research R7). The screen MUST render before the crops arrive (FR-018) (depends on T020)
- [X] T024 [US3] In `Kalorias/Features/History/MealDetailsView.swift`'s `foodList`, add a fixed-size leading thumbnail to each ingredient row: the crop when present, otherwise the placeholder (`AppColor.surfaceElevated` with a `fork.knife` symbol in `textSecondary`, matching the header photo's existing fallback and `MealRowView`'s visual language). Rounded-rect clipped. **Fixed size, never flexible width**, so large Dynamic Type grows the row instead of squeezing the text (FR-012). Mark the image **decorative / hidden from assistive technology** (FR-022) — the name and calories are already announced, so labelling a generated crop would only add noise. Add the `mealDetails.food.thumbnail` accessibility identifier (depends on T023)
- [X] T025 [US3] While in that same `foodList`, replace the ad-hoc `.glassEffect(.regular, in: .rect(cornerRadius: 18))` at `Kalorias/Features/History/MealDetailsView.swift:100` with the shared `glassCard(...)` helper from feature 005 (pass `padding: 0` if the row already pads, so the change is visually neutral). Principle III requires glass through the shared helper; this line is already being edited, so keeping the duplication has no excuse. `AnalysisResultView.swift:125` is the last remaining site and stays out of scope
- [X] T026 [US3] Confirm **no new key is required** in `Kalorias/Resources/Localizable.xcstrings`: this story adds no visible copy, and the thumbnail is decorative so it needs no accessibility label. Do **not** add `mealDetails.food.noImage` — an unused catalog entry is dead code under Principle I. If implementation reveals a label is genuinely needed, add it with EN+ES and a comment
- [X] T027 [US3] Build and run the full suite (`xcodebuild ... test`); confirm zero warnings and that the count grew from 122 by the new `FoodRegion`, `FoodThumbnailCropper`, decoding and repository cases. A count still at 122 means T012 or T022 did not take effect
- [ ] T028 [US3] Validate quickstart.md **V3** (a meal saved before this feature shows placeholders on every row, fully readable, nothing blank or broken — the permanent state for old meals) and **V4** (a newly analyzed meal shows crops on most rows, placeholders mixed in for unboxed foods, the screen appears immediately, and no stretched or empty thumbnails)
- [ ] T029 [US3] Validate quickstart.md **V5** — the axis-order check. Analyze a photo with foods in **clearly asymmetric positions** (one top-left, one bottom-right); a symmetric plate would make an x/y swap look plausible. **Expect** the top-left food's thumbnail to show the top-left food. Swapped or rotated thumbnails mean the `ymin`/`xmin` mapping is reversed. Requires a Gemini API key in `Config/Secrets.xcconfig`

**Checkpoint**: All three stories independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T030 Clean build with zero warnings: `xcodebuild -project Kalorias.xcodeproj -scheme Kalorias -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath /tmp/kal-006 clean build`
- [X] T031 Run the full suite (`xcodebuild ... test`) and confirm all **122** prior tests still pass alongside the new ones — this feature changes no calorie or macro behaviour, so any regression in features 001–005 is a real defect
- [X] T032 [P] Confirm FR-021 by inspection of `Kalorias/Features/Analysis/GeminiCalorieService.swift`: `box` is absent from `foods.items.required`, and no code path throws or skips saving because a box is missing or malformed
- [X] T033 [P] Confirm FR-017 by inspection: `Kalorias/Features/History/MealEntry.swift` has no new **stored** property on `MealEntry`, no `VersionedSchema`/migration plan was added anywhere, and `region` is optional on `StoredFood`
- [X] T034 [P] Confirm no force-unwraps or `try!` were introduced in `FoodRegion.swift`, `FoodThumbnailCropper.swift`, `GeminiCalorieService.swift`, `HistoryView.swift` or `MealDetailsView.swift` (Principle I)
- [ ] T035 Validate quickstart.md **V6** (failure paths): analyzing with no network behaves exactly as before; opening an existing meal in airplane mode shows its thumbnails fine (crops come from the stored photo, FR-016); and a meal whose photo file is missing shows the header placeholder **and** row placeholders with no crash
- [ ] T036 Validate quickstart.md **V7**: both appearances (checking the `caution` yellow figure in **light** mode), both languages with no raw key strings, Larger Text growing rows rather than clipping, and VoiceOver announcing name/calories/macros per row **without** announcing the thumbnail
- [ ] T037 Validate quickstart.md **V8**: a meal with ≥ 15 ingredients opens in under 1 second and scrolls smoothly with no hitch as thumbnails appear. If it hitches, confirm crops are produced in one off-main pass rather than per row (research R7)
- [ ] T038 Walk the Definition of Done checklist at the end of quickstart.md and check off every box

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies
- **Foundational (Phase 2)**: empty — see the note in that phase
- **US1 (Phase 3)**: independent. Touches only `RootView` + `ProgressTabView`
- **US2 (Phase 4)**: independent. Touches `HistoryView` + `MealDetailsView`
- **US3 (Phase 5)**: independent of US1. Shares `MealDetailsView` with US2
- **Polish (Phase 6)**: depends on all desired stories

### User Story Dependencies

All three stories are genuinely independent — unusually so for this project, because each targets
a different layer. The only coupling is **file-level**: T007 (US2) and T023–T025 (US3) both edit
`MealDetailsView.swift`. Sequence US2 before US3 so the signature change lands before the
thumbnail work, or expect a merge conflict in that file.

**Ship US1 first regardless of the other two.** It is a one-file fix for a defect that hides data,
and it is the only story whose value does not depend on anything else landing.

### Within US3

Strict order: `FoodRegion` (T010) → `FoodItem` (T013) → Gemini schema (T014) → parsing (T015) →
`StoredFood` (T017) → cropper (T020) → details screen (T023–T025). Each layer consumes the one
above it. `GeminiCalorieService.swift` is edited by T014 and T015 sequentially;
`MealDetailsView.swift` by T023, T024 and T025 sequentially.

### Parallel Opportunities

- **US3**: T010 (`FoodRegion.swift`) and T020 (`FoodThumbnailCropper.swift`) are `[P]` — different
  files, and the cropper only needs `FoodRegion`'s type signature. T011 can be written alongside
  T013–T015 once T010 exists
- **Phase 6**: T032, T033 and T034 are `[P]` — read-only inspection passes
- **Across stories**: US1 and US2 could be done by different people simultaneously; US3 should wait
  for US2 only because of the shared file

---

## Parallel Example: User Story 3

```bash
# Two unrelated files — launch together:
Task: "Create Kalorias/Features/Analysis/FoodRegion.swift with clamping + Gemini initializers"
Task: "Create Kalorias/Features/History/FoodThumbnailCropper.swift with renderer-based cropping"

# Then strictly sequentially, each layer feeding the next:
# T013 FoodItem → T014 schema → T015 parsing → T017 StoredFood → T023 crop pass → T024 rows
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1 Setup — baseline 122 tests
2. Phase 3 US1 — two file edits (`RootView`, `ProgressTabView`)
3. **STOP and VALIDATE**: quickstart V1 on all three scrollable screens
4. Shippable: the reported defect is fixed app-wide, and nothing else had to change

This is an unusually cheap MVP — the whole of US1 is a container-level layout change plus deleting
a hack — so there is little reason not to ship it on its own first.

### Incremental Delivery

1. Setup → baseline recorded
2. + US1 → bottom-bar clearance → validate → **MVP**
3. + US2 → colour consistency → validate
4. + US3 → ingredient thumbnails → validate (this is the bulk of the work: 20 of 38 tasks)
5. Phase 6 Polish → warnings, failure paths, accessibility, performance

### Notes

- `[P]` = different files, no dependency on an incomplete task
- Commit after each task or logical group — **manually**. The constitution forbids automated tooling
  from running `git commit`/`git push` or from offering to
- Do **not** author or run UI tests (Principle II)
- **No new colour token** and **no localization key** in this feature — the constitution's token
  table and the string catalog are both untouched
- Two tasks exist to keep a defect fix honest rather than doubled: **T003** (delete the padding hack)
  and **T025** (drop the ad-hoc glass call). Skipping either leaves the codebase worse than a clean
  fix would
- The two tasks most likely to hide a silent bug are **T011** (x/y swap in the region test) and
  **T021** (orientation in the crop test). Both failure modes produce plausible-looking output, so
  the tests are the only thing standing between them and shipping

---

## Validation status recorded during implementation

Screenshots were taken on the simulator using a **throwaway harness** (a fake `ImageStoring`
returning a 3x3 coloured-quadrant image, sample foods with known regions, and `RootView`
temporarily rendering `MealDetailsView` directly). All of it was reverted and verified gone by
grep — nothing throwaway was committed.

| Check | Status | Evidence |
|---|---|---|
| Region -> crop mapping is not x/y swapped | ✅ verified end-to-end | `r(0,0)`→red, `r(1,0)`→green, `r(2,0)`→blue, `r(1,1)`→purple, `r(0,1)`→orange, `r(1,2)`→brown — every thumbnail matched its expected quadrant |
| Thumbnails render, with placeholder mixed in | ✅ verified | "Aceite de oliva (sin región)" showed the fork-knife placeholder beside cropped rows |
| Calorie figure uses the passed-in colour step | ✅ verified | `.veryHigh` rendered red, replacing brandPrimary |
| Ingredient rows use the shared glass helper | ✅ verified | rows render identically to before, via `glassCard(padding: 16)` |
| **FR-002** — content that fits is never overlapped | ✅ verified | 3-food meal: last row ends cleanly above the bar |
| Content passes *behind* the translucent bar (FR-003) | ✅ verified | mid-scroll screenshot shows a row through the glass |
| **FR-001** — scrolled to the end, last row clears the bar | ⚠️ inferred, not gesture-tested | the inset is proven applied (FR-002 above); `simctl` cannot perform scroll gestures |
| V5 live box quality from Gemini | ⚠️ not verified | needs an API key and a real asymmetric photo |
| V7 VoiceOver / Larger Text | ⚠️ not verified | needs an accessibility session |
| V8 performance at 15+ ingredients | ⚠️ not verified | needs a real meal that large |

### A false alarm worth recording

An intermediate screenshot appeared to show the last row *still* behind the bar after the fix,
which read as "the safe-area inset is not propagating into the NavigationStack". It was wrong: the
test used `.defaultScrollAnchor(.bottom)`, which aligns the content's bottom edge with the
container's bottom edge and therefore bypasses the very inset being tested. Re-testing with content
that fits without scrolling showed the inset working correctly. **The measuring tool was broken,
not the fix.** The `safeAreaInset` was moved from `content` to the whole `ZStack` during that
investigation; both placements behave identically, and the `ZStack` placement was kept as the more
explicit of the two.

### Swift 6 isolation note

`Self.thumbnailMaxDimension` could not be read inside the `Task.detached` closure — a static
property on a `View` is MainActor-isolated under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. It is
now captured into a local first, alongside `entry.foods`, so the detached closure touches nothing
isolated.
