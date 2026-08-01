---

description: "Task list for Fix Analysis Reliability, Ingredient Thumbnails & Bottom-Bar Clearance"
---

# Tasks: Fix Analysis Reliability, Ingredient Thumbnails & Bottom-Bar Clearance

**Input**: Design documents from `/specs/007-fix-scroll-and-boxes/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/ui-contracts.md](./contracts/ui-contracts.md), [quickstart.md](./quickstart.md)

**Tests**: Unit tests are **REQUIRED**. Constitution Principle II mandates that every bug fix ship a
regression test that fails before the fix and passes after, in the same change. Two defects, two
regression tests. **UI tests stay OFF** (Principle II).

**Organization**: Tasks are grouped by user story. This is a defect fix, so the phases are small and
the emphasis is on verification that can actually fail.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1 / US2 / US3 from spec.md
- Exact file paths are in every task

## Path Conventions

Sources under `Kalorias/`, tests under `KaloriasTests/`. New sources are auto-included; **new test
files need a `project.pbxproj` entry** (no new test file is expected here — the existing decoding
suite is extended).

---

## Phase 1: Setup

- [X] T001 Capture the green baseline: `xcodebuild -project Kalorias.xcodeproj -scheme Kalorias -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test` — expect **158 tests, 0 failures**. If the simulator reports `... Busy`, boot it first with `xcrun simctl boot "iPhone 17 Pro Max" && xcrun simctl bootstatus "iPhone 17 Pro Max" -b`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Intentionally empty.** US1 touches only the analysis service, US3 only layout; neither blocks the
other and they share no file. US2 requires no code at all (see Phase 4). No filler tasks were invented
to populate this phase.

---

## Phase 3: User Story 1 - Photo analysis works reliably again (Priority: P1) 🎯 MVP

**Goal**: The analysis stops failing. Making the per-food `box` optional caused the model to run away to `MAX_TOKENS` and return unparseable output, losing the meal entirely.

**Independent Test**: Analyze several photos including one busy plate. Every analysis that previously succeeded must succeed, save its meal with correct calories, and complete without a truncated or malformed reply.

### Implementation for User Story 1

- [X] T002 [US1] In `Kalorias/Features/Analysis/GeminiCalorieService.swift`, add `"box"` to the `foods.items` `"required"` list, changing it from `["name", "calories"]` to `["name", "calories", "box"]`. **Do not change `box`'s property shape** — the four integer edges stay exactly as they are. Measured effect (research R1): optional → `MAX_TOKENS` and ~65,000 characters of malformed digits, meal lost; required → clean reply with a box for every food. Add a comment recording *why* it must stay required, so a future reader does not "helpfully" relax it again
- [X] T003 [US1] In `Kalorias/Features/Analysis/GeminiCalorieService.swift`'s `generationConfig`, add a `maxOutputTokens` bound sized generously for a meal with dozens of foods but far below the model's default ceiling. Observed healthy replies were 256–388 characters, so this cannot truncate legitimate output; its purpose is to turn a runaway reply from "burn the whole budget then fail" into "fail fast and cheaply" (FR-003). A reply truncated by this bound is malformed and takes the existing error path, which saves nothing (FR-004)
- [X] T004 [US1] Make the request shape reachable from tests in `Kalorias/Features/Analysis/GeminiCalorieService.swift`: widen `responseSchema` from `private static` to internal, and expose the generation-config values the test needs. The file already sets this precedent — `extractModelJSON` and `parseOutcome` are internal and documented as "Exposed for unit testing"
- [X] T005 [US1] Add the schema regression tests to `KaloriasTests/CalorieAnalysisDecodingTests.swift`: assert `"box"` is present in `foods.items.required`; assert `box`'s property shape still declares the four required integer edges `ymin`/`xmin`/`ymax`/`xmax`; assert `maxOutputTokens` is set and above a sane floor. **This is the test that would have caught the outage** — parsing was never the broken part, so a parser-only test could not have detected it (depends on T002, T003, T004)
- [X] T006 [US1] Verify the existing leniency cases in `KaloriasTests/CalorieAnalysisDecodingTests.swift` still pass **as separate tests** from T005: a reply with no `box`, and one with a malformed `box`, must each still yield a fully parsed meal with `region == nil` for that food. T005 and T006 encode the two halves of FR-006 — demand the box in the request, tolerate its absence in the parser — and must stay independent so no future change can trade one for the other silently
- [X] T007 [US1] Build and run the full suite (`xcodebuild ... test`); confirm zero warnings, the 158 baseline tests still green, and the new schema assertions passing
- [X] T008 [US1] Validate quickstart.md **V2** with the real service: analyze **at least 5 varied food photos** including one busy plate. Expect every analysis to complete and save its meal with correct calories and macros, and **0** failures from a truncated or unreadable reply. Also analyze something with no food and confirm the existing "no food" outcome is unchanged. Requires the `GEMINI_API_KEY` already present in `Config/Secrets.xcconfig`

**Checkpoint**: The core-function regression is fixed — this is the MVP and the most urgent item

---

## Phase 4: User Story 2 - Ingredient thumbnails actually appear (Priority: P2)

**Goal**: Ingredient rows show crops of the user's photo instead of placeholders on every row.

**Independent Test**: Analyze a new photo with several distinct foods, open its details, and confirm each row shows a crop of that region rather than the placeholder.

> **No code changes in this phase.** The crop pipeline was verified working during planning — seeded
> regions produced correct per-quadrant crops through the real persistence and navigation path. It was
> starved of regions, not broken. Once US1 lands, rows populate on their own. These tasks are
> validation only; if either fails, the defect is in US1, not here.

- [ ] T009 [US2] Validate quickstart.md **V3** using a meal analyzed after US1: open its details from `Kalorias/Features/History/MealDetailsView.swift` and confirm most ingredient rows show a crop of the photo, any unlocalized food shows the placeholder mixed among cropped rows, and the screen appears immediately with thumbnails filling in shortly after (depends on Phase 3)
- [ ] T010 [US2] Validate quickstart.md **V4** — the axis check. Photograph foods in **clearly different corners** (one top-left, one bottom-right); a symmetric plate would make a transposed crop look plausible. Expect the top-left food's thumbnail to show the top-left food. Live replies during planning already returned regions matching the foods' real positions, so this confirms rather than investigates

**Checkpoint**: The visible half of the user's report is resolved

---

## Phase 5: User Story 3 - The bottom bar stops covering the ingredient list (Priority: P2)

**Goal**: Every scrolling screen can bring its final element fully clear of the floating bar.

**Independent Test**: Open a meal with enough ingredients to require scrolling, scroll to the very end **through the real navigation path**, and confirm the last row is fully readable above the bar.

### Verification harness first — it must reproduce the failure before anything is fixed

- [X] T011 [US3] Build a **temporary** verification harness (a throwaway file under `Kalorias/Features/History/` plus a hook in `Kalorias/App/RootView.swift`, both removed in T018) and confirm it **reproduces the failure on current code**: seed a meal with ~10 ingredients whose last one is distinctively named (e.g. `ULTIMO`) into the real store, reach `MealDetailsView` **through the real navigation path** (set `router.historyPath`, not by rendering the view directly — rendering it directly bypasses the `NavigationStack` whose inset-swallowing *is* the bug), drive a real scroll to the last row via a `scrollPosition(id:)` binding, and screenshot. **Expect the last row to be unreachable/obscured.** A harness that passes before the fix is not a valid harness and must be corrected before proceeding. Do **not** use content that fits on one screen, and do **not** use `.defaultScrollAnchor(.bottom)` — both were tried and proved incapable of detecting this bug (research R5)

### The fix

- [X] T012 [US3] Add the single shared clearance constant to `Kalorias/DesignSystem/BottomBar.swift` — e.g. `static let scrollClearance: CGFloat` — owned by the type whose height it describes. This value has already been duplicated once (feature 005 hardcoded `96` in the Progress tab; feature 006 deleted it and replaced it with an inset that did nothing), so **one** declaration is the requirement (Principle I)
- [X] T013 [US3] In `Kalorias/App/RootView.swift`, **remove** the `.safeAreaInset(edge: .bottom)` added by feature 006 and restore `BottomBar` as a floating overlay in the `ZStack`. Measured ineffective: the root content reports `safeAreaInsets.bottom = 148` but the pushed detail view reports `0` with a full-screen height, because `NavigationStack` consumes the inset (research R3). Removing it rather than leaving it under the real fix prevents any future non-`NavigationStack` screen being inset twice (FR-015) and satisfies Principle I's ban on keeping a hack beside its fix. Keep the bar's appearance, position and translucency identical, and leave the camera `fullScreenCover` and surface background untouched
- [X] T014 [P] [US3] Apply `.contentMargins(.bottom, BottomBar.scrollClearance, for: .scrollContent)` to the `ScrollView` in `Kalorias/Features/History/MealDetailsView.swift`
- [X] T015 [P] [US3] Apply the same clearance to the `List` in `Kalorias/Features/History/HistoryView.swift`, leaving the week sections, ordering, headers, row colours and empty state untouched (FR-016)
- [X] T016 [P] [US3] Apply the same clearance to the `ScrollView` in `Kalorias/Features/Progress/ProgressTabView.swift`. Confirm no leftover manual bottom padding remains in this file, or the tab will be inset twice (FR-015)

### Prove it, then clean up

- [X] T017 [US3] Re-run the T011 harness (`Kalorias/App/RootView.swift` hook) unchanged against the fixed code. **Expect the last row (`ULTIMO`) fully visible above the bar** — name, calorie figure and macro strip all readable. Same harness, same build procedure, opposite result: that is what makes this verification trustworthy (depends on T012–T016)
- [X] T018 [US3] Remove the temporary harness completely and verify no residue with a grep for the probe symbols across `Kalorias/` — no seeding code, no `scrollPosition` probe, no print statements. Nothing temporary may be committed
- [X] T019 [US3] Build and run the full suite (`xcodebuild ... test`); confirm zero warnings and 158 tests still green — this story is layout-only, so any test change is a red flag
- [ ] T020 [US3] Validate quickstart.md **V1** on all three screens by scrolling each to its end: meal details (last ingredient fully visible), History list (last row fully visible), Progress tab (last widget visible with **no** conspicuous empty gap above the bar). Confirm content still passes *behind* the translucent bar while scrolling and that the bar has not moved or become opaque. Repeat at the largest Dynamic Type size and in landscape

**Checkpoint**: All three stories resolved

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T021 Clean build with zero warnings: `xcodebuild -project Kalorias.xcodeproj -scheme Kalorias -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath /tmp/kal-007 clean build`
- [X] T022 Run the full suite (`xcodebuild ... test`): 158 baseline tests green plus the new schema assertions. This feature changes no nutrition behaviour, so any regression in features 001–006 is a real defect
- [X] T023 [P] Confirm exactly **one** clearance value exists: grep `Kalorias/` for stray bottom-padding magic numbers near the bar height and confirm all three call sites reference `BottomBar.scrollClearance`
- [X] T024 [P] Confirm no `safeAreaInset` for the bottom bar remains in `Kalorias/App/RootView.swift`, so only one clearance mechanism is in effect (FR-015)
- [X] T025 [P] Confirm no stored-data change: `Kalorias/Features/History/MealEntry.swift` has no new stored property, and no migration machinery was added anywhere (FR-017)
- [ ] T026 Validate quickstart.md **V5** (failure paths): a meal saved before regions existed shows placeholders on every row without crashing; a meal whose photo file is missing shows header **and** row placeholders; airplane mode opening an existing meal still shows thumbnails; airplane mode analysis gives the same clear error as before with no partial meal saved
- [ ] T027 Validate quickstart.md **V6**: both appearances (bar, rows, thumbnails and the coloured calorie figure legible) and both languages (no raw key strings; the analysis error reads sensibly in each)
- [ ] T028 Walk the Definition of Done checklist at the end of quickstart.md and check off every box

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies
- **Foundational (Phase 2)**: empty — see that phase
- **US1 (Phase 3)**: independent. Touches only `GeminiCalorieService.swift` and its test file
- **US2 (Phase 4)**: **depends on US1** and contains no code — validation only
- **US3 (Phase 5)**: independent of US1 and US2. Touches only layout files
- **Polish (Phase 6)**: depends on all desired stories

### User Story Dependencies

- **US1** is the MVP and must go first: it is a regression in the app's core function, and a failed
  analysis loses a calorie record.
- **US2** cannot be worked on — only observed. Without US1 there are no regions to crop.
- **US3** shares no file with US1, so it can proceed fully in parallel by a second person.

### Within US3, the order is the point

`T011 (harness reproduces the failure)` → `T012–T016 (fix)` → `T017 (same harness now passes)` →
`T018 (remove harness)`. Building the harness **after** the fix would repeat feature 006's mistake: a
verification that has never been seen to fail proves nothing.

`RootView.swift` (T013) and the three scroll containers (T014–T016) are separate files and can be
edited in parallel, but T017 needs all four done.

### Parallel Opportunities

- **US1 and US3 in parallel** — different files entirely, different people
- **T014, T015, T016** are `[P]` — three separate view files
- **T023, T024, T025** are `[P]` — read-only verification passes

---

## Parallel Example: User Story 3

```bash
# After T012 (the constant) and T011 (the failing harness), three separate files:
Task: "Apply contentMargins to the ScrollView in MealDetailsView.swift"
Task: "Apply contentMargins to the List in HistoryView.swift"
Task: "Apply contentMargins to the ScrollView in ProgressTabView.swift"

# Then T013 (RootView: remove the inset) → T017 (re-run harness) → T018 (remove harness)
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1 — baseline 158 tests
2. Phase 3 US1 — two edits to the schema/config, one access widening, two regression tests
3. **STOP and VALIDATE**: V2 on ≥ 5 real photos, **0** failed analyses
4. Shippable: the core-function regression is gone, and thumbnails start appearing as a side effect

US1 is both the smallest and the most urgent piece — the schema change itself is one array element.

### Incremental Delivery

1. Setup → baseline
2. + US1 → analysis reliable again → validate → **MVP**
3. + US2 → observe thumbnails appear (no code) → validate
4. + US3 → clearance, verified by a harness proven able to fail → validate
5. Phase 6 → warnings, failure paths, appearance, language

### Notes

- Commit after each task or logical group — **manually**; the constitution forbids automated tooling
  from running `git commit`/`git push` or offering to
- Do **not** author or run UI tests (Principle II)
- **No stored-data change, no migration, no new colour token, no new localization key expected**
- The two tasks that keep this fix honest are **T011** (the harness must fail first) and **T013**
  (delete the ineffective inset rather than layer the real fix on top of it). Skipping either repeats
  a mistake already made in this codebase
- **T005 and T006 must stay separate tests.** Together they encode FR-006: ask firmly, fail softly.
  Feature 006 collapsed the two and caused an outage

---

## Validation record

### US1 — analysis reliability: fixed and proven

**The regression test genuinely fails without the fix.** With `"box"` removed from the schema's
`required` list, `testSchemaRequiresBoxForEveryFood` fails; restored, it passes. Principle II's
"fails before, passes after" is satisfied by demonstration, not assertion.

**Live service, 4 distinct images, 0 failures:**

| Image | `finishReason` | Reply length | Foods | With box |
|---|---|---|---|---|
| plate A | `STOP` | 400 | 3 | **3/3** |
| plate B | `STOP` | 33 | 0 | n/a — clean "no food" outcome |
| plate C | `STOP` | 36 | 0 | n/a — clean "no food" outcome |
| plate D | `STOP` | 272 | 2 | **2/2** |

No `MAX_TOKENS`, no unparseable reply. Where food was detected, **every** food carried a box —
against 0/3 before the fix, where the reply was 65,000 characters of garbage.

### US3 — clearance: the harness failed first, then passed

Same harness, same build procedure, opposite results — which is the only reason to trust it:

| | Result |
|---|---|
| **Before the fix** | `ULTIMO` entirely behind the bar, bleeding through the glass; `Fila 9` was the last readable row |
| **After the fix** | `ULTIMO` fully visible — name, 777 kcal and all three macros readable, clear space above the bar |

Progress tab checked separately for FR-015: content sits naturally, **no** artificial gap, so nothing
is inset twice.

### Not verified

| Item | Why |
|---|---|
| T009/T010 (US2 thumbnails on a real photo) | Needs a real camera capture on device. The crop pipeline and the axis mapping were both verified during planning, and US1 now supplies the regions, so this is expected to pass — but it has not been observed end-to-end with a real photo |
| T020 History-list scroll to the last row | `simctl` cannot scroll a `List`; the mechanism is identical to the details screen, which was proven |
| T020 Dynamic Type / landscape | needs manual interaction |
| T026 / T027 (failure paths, appearance, language) | need manual interaction |
| T028 | depends on the above |

### Note on the clearance value

`BottomBar.scrollClearance = 112` covers the 64pt camera button, the bar's 10pt vertical padding, its
8pt bottom offset, and the home-indicator area a scroll view extends under. It was verified visually
rather than derived, because the pushed view reports a bottom safe-area inset of 0 and so must account
for the home indicator itself. If the bar's design changes, this is the one place to update.
