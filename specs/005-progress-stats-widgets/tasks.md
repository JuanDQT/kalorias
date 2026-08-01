---

description: "Task list for Progress Tab — Weekly Summary & 7-Day Calorie Chart"
---

# Tasks: Progress Tab — Weekly Summary & 7-Day Calorie Chart

**Input**: Design documents from `/specs/005-progress-stats-widgets/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/ui-contracts.md](./contracts/ui-contracts.md), [quickstart.md](./quickstart.md)

**Tests**: Unit tests are **REQUIRED**, not optional. Constitution Principle II
(NON-NEGOTIABLE) mandates them for any logic that computes, aggregates or converts values —
and this feature is almost entirely arithmetic, so the tests *are* the deliverable.
**UI tests stay OFF** (Principle II) — do not author or run XCUITest.

**Organization**: Tasks are grouped by user story so each can be implemented, tested and
shipped independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1 / US2 / US3 from spec.md
- Exact file paths are in every task

## Path Conventions

Native iOS app, single SwiftUI target. Sources under `Kalorias/`, tests under `KaloriasTests/`.

⚠️ **New sources under `Kalorias/` are auto-included** (filesystem-synchronized group).
**`KaloriasTests/` is NOT** — each new test file must be registered in `project.pbxproj`
(PBXBuildFile + PBXFileReference + the group's `children` + the target's `Sources` phase) or
it silently never runs, and the only symptom is a test count that does not grow. This cost a
debugging cycle in feature 004, so each test file below has its own registration task
immediately after it, keeping the build green at every checkpoint.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish the green baseline, and de-risk the one new framework before anything is built on it

- [X] T001 Capture the green baseline: `xcodebuild -project Kalorias.xcodeproj -scheme Kalorias -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test` — record the count (expected **79 tests, 0 failures**) so any later regression is unambiguously caused by this feature. If the simulator reports `FBSOpenApplicationServiceErrorDomain ... Busy`, boot it first with `xcrun simctl boot "iPhone 17 Pro Max" && xcrun simctl bootstatus "iPhone 17 Pro Max" -b`
- [X] T002 De-risk Swift Charts before building a widget on it: add a temporary `import Charts` plus a trivial `Chart { BarMark(x: .value("d", 1), y: .value("v", 2)) }` in a scratch `#Preview` inside `Kalorias/Features/Progress/ProgressPlaceholderView.swift` (which T008 deletes anyway) and confirm it compiles for the iOS 26.5 target, then remove it. `Charts.framework` ships in the SDK so no linking step should be needed — this task exists to prove that before US2 depends on it

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The per-day tallies (needed by **both** widgets — the chart plots them and the weekly summary derives its logged-day count and highest day from them), the shared glass surface, and the tab shell.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T003 [P] Create `Kalorias/DesignSystem/GlassCard.swift` — a shared surface wrapping Apple's **native** `.glassEffect(.regular, in: .rect(cornerRadius:))` so both widget cards and every future card go through one place, as Principle III requires ("never by hand-rolling an imitation", and drawn "through the project's shared helpers rather than by scattering `.glassEffect(...)` ad hoc per screen"). Either a `ViewModifier` + `View` extension or a container view is acceptable; it must expose the corner radius and take its colors from `AppColor`. Do **not** hand-roll blurs/gradients
- [X] T004 [P] Create `Kalorias/Features/Progress/ProgressStatistics.swift` with `DailyTally` (`day`, `totalCalories`, `mealCount`, and `hasLog` **derived from `mealCount > 0`**), plus `static func dailyTallies(from:calendar:endingOn:dayCount:)`, `averageOfLoggedDays(_:)` and `loggedBounds(_:)`. All `nonisolated`, generic over feature 004's existing `WeekGroupable` — **no SwiftUI import**. Emit a tally for **every** day in the window including unlogged ones, oldest first; bucket by `calendar.startOfDay`; use `calendar.date(byAdding: .day,)` for window edges, never fixed-second arithmetic. `averageOfLoggedDays` and `loggedBounds` return `Int?` / optional tuple so "no logged days" is never a `0`
- [X] T005 Create `KaloriasTests/DailyTallyTests.swift` covering all 13 cases in quickstart.md §"DailyTallyTests". The one that matters most: **a logged meal totalling 0 kcal must give `hasLog == true`** — that is the test that catches deriving `hasLog` from `totalCalories` instead of `mealCount`. Also cover the 7-day window boundaries (a meal 8 days ago excluded, a meal at 23:59 of the first window day included) and a non-UTC time zone bucketing by local day. Inject every `Calendar` and `endingOn`; never read `.current` or `Date()`
- [X] T006 Register `DailyTallyTests.swift` in `Kalorias.xcodeproj/project.pbxproj` (PBXBuildFile + PBXFileReference + the `KaloriasTests` group `children` + the target's `Sources` phase), then confirm with `plutil -lint Kalorias.xcodeproj/project.pbxproj`
- [X] T007 Create `Kalorias/Features/Progress/ProgressTabView.swift` — the tab root. **Name it `ProgressTabView`, never `ProgressView`**: that name is a SwiftUI built-in and would shadow the spinner type inside the module (research R1). It holds one `@Query(sort: \MealEntry.capturedAt, order: .reverse)`, reads `Calendar.current` and `Date()` **once here and nowhere else** (the pure functions take them as parameters), and lays out slots for the two widgets. Carry over the `screen.progress` accessibility identifier from the placeholder so existing selectors keep working
- [X] T008 Wire it up: in `Kalorias/App/RootView.swift` change `case .progress:` to render `ProgressTabView()`, and **delete** `Kalorias/Features/Progress/ProgressPlaceholderView.swift` (no dead code — Principle I). The Router is not touched; this feature adds no navigation
- [X] T009 Build and run the full suite (`xcodebuild ... test`); confirm zero warnings and that the count grew from 79 to **79 + the DailyTally cases**. A count still at 79 means T006 did not take effect

**Checkpoint**: Per-day tallies are tested, the glass surface exists, and the Progress tab renders a live shell — user stories can now begin

---

## Phase 3: User Story 1 - See this week at a glance, compared to last week (Priority: P1) 🎯 MVP

**Goal**: A weekly summary card showing total logged kcal, average per logged day, meal count and the highest day, with an elapsed-aligned comparison against the previous week.

**Independent Test**: With meals logged across the current and previous week, open the Progress tab and confirm the four figures are correct and the comparison shows the right direction and percentage; then with only current-week data, confirm no comparison appears.

### Implementation for User Story 1

- [X] T010 [US1] Add `ChangeDirection` (`.up`/`.down`/`.unchanged`), `PeriodChange` (`direction` + non-negative `percent`) and `static func change(current:baseline:) -> PeriodChange?` to `Kalorias/Features/Progress/ProgressStatistics.swift`. **`baseline <= 0` MUST return `nil`** — `(current - 0) / 0` is undefined and would surface as `+∞` or a `"nan%"` on screen (FR-006). Equal values return `.unchanged`, not `.up` with `0%` (FR-007). Direction is an enum rather than a signed number specifically so the view cannot convey it by color alone
- [X] T011 [P] [US1] Create `KaloriasTests/PeriodChangeTests.swift` covering all 8 cases in quickstart.md §"PeriodChangeTests": zero baseline → `nil`, negative baseline → `nil`, both zero → `nil`, equal → `.unchanged`, up 1120 vs 1000 → `.up`/12, down 880 vs 1000 → `.down`/12, a huge ratio without overflow, and `percent >= 0` always
- [X] T012 [US1] Register `PeriodChangeTests.swift` in `Kalorias.xcodeproj/project.pbxproj` and `plutil -lint` it
- [X] T013 [US1] Add `WeekSummary` and `static func weekSummary(from:calendar:now:)` to `Kalorias/Features/Progress/ProgressStatistics.swift`. Compute `weekStart` from `calendar.dateInterval(of: .weekOfYear, for: now)` (region-aware, FR-002), `elapsedDays = dateComponents([.day], from: weekStart, to: startOfDay(now)).day + 1` clamped to `1...7`, and the previous week's baseline as **`prevStart ..< prevStart + elapsedDays` days** where `prevStart = weekStart - 7 days` via `date(byAdding: .day,)`. `averagePerLoggedDay` is `Int?` (`nil` when no logged days — never a `0` or a divide-by-zero); `highestDay` resolves ties to the **most recent** day (FR-008); both changes come from `change(current:baseline:)` so a zero baseline suppresses them. No force-unwraps — document each optional fallback (Principle I)
- [X] T014 [US1] Create `KaloriasTests/WeekSummaryTests.swift` covering all 15 cases in quickstart.md §"WeekSummaryTests". The two that carry the feature: (a) **partial week vs a previous week loaded only on days 5–7 → `totalChange == nil`**, not a large false decline; (b) **elapsed-aligned baseline** — previous week's first 3 days total 1000 and the current 3 days total 1120 → `.up`/12%, proving the baseline is 1000 rather than the previous week's full total. Also cover Monday-first vs Sunday-first `weekStart`, `elapsedDays` of 1 and 7, the highest-day tie resolving to the most recent day repeatably, empty input, and the **Madrid DST fall-back week (26 Oct 2026)** where window edges must stay at 00:00
- [X] T015 [US1] Register `WeekSummaryTests.swift` in `Kalorias.xcodeproj/project.pbxproj` and `plutil -lint` it
- [X] T016 [P] [US1] Add the weekly-card keys to `Kalorias/Resources/Localizable.xcstrings` with EN + ES and translator comments, per contracts/ui-contracts.md §4: `progress.title`, `progress.week.title`, `progress.week.total`, `progress.week.average`, `progress.week.meals`, `progress.week.highest`, `progress.change.up`, `progress.change.down`, `progress.change.unchanged`, `progress.unavailable`. Every label must say *logged* / *registradas* — no key may describe a figure as the user's intake or consumption (FR-021)
- [X] T017 [US1] Create `Kalorias/Features/Progress/WeekSummaryCard.swift` rendering a `WeekSummary` and **computing nothing**. Use `GlassCard` from T003. Show direction as an SF Symbol arrow **plus** the percentage text so color is never the sole carrier (FR-028); render a `nil` change as **no indicator at all** — not a dash, not `0%` (FR-006); omit or explicitly mark unavailable any `nil` figure rather than showing `0` (FR-020). State the period the card covers (FR-022). Add the `progress.week.*` accessibility identifiers from contracts §3. Format percentages and numbers through locale-aware formatting, not string concatenation
- [X] T018 [US1] Wire `WeekSummaryCard` into `Kalorias/Features/Progress/ProgressTabView.swift`, passing the `WeekSummary` built once per body evaluation
- [ ] T019 [US1] Validate quickstart.md **V1** (four figures correct, arrow+text indicator, period stated, arithmetic cross-checked against the History tab for the same week) and **V2** — the elapsed-alignment check: mid-week with a full previous week logged, the comparison must **not** show a large false decline. If the total always drops early in the week and recovers by Sunday, the alignment is broken

**Checkpoint**: The weekly summary works and is independently shippable — this is the MVP

---

## Phase 4: User Story 2 - See the last 7 days as a chart (Priority: P2)

**Goal**: A 7-day bar chart of logged calories with an average indicator, where unlogged days read as labelled gaps rather than zeros, and bars use the History tab's color scale.

**Independent Test**: With meals on some of the last 7 days and none on others, open the Progress tab and confirm one slot per day, unlogged days rendered distinctly rather than as zero, the average reflecting only logged days, and colors ascending green → red with the day totals.

### Implementation for User Story 2

- [X] T020 [P] [US2] Add the chart keys to `Kalorias/Resources/Localizable.xcstrings` with EN + ES and comments: `progress.chart.title` (`Last 7 days` / `Últimos 7 días`), `progress.chart.average`, `progress.chart.noData`
- [X] T021 [US2] Create `Kalorias/Features/Progress/DailyCaloriesChart.swift` using Swift Charts, rendering `[DailyTally]` and **computing nothing**. A `BarMark` for **logged days only**; **no mark at all for unlogged days**, with `chartXScale(domain:)` pinned to all 7 days so an unlogged day is a *labelled empty slot* — never a zero-height or ghost bar, which would read as a small value and is precisely what FR-012 exists to prevent (research R5). A `RuleMark` for the average across logged days (FR-014). Colors come from `CalorieColorScale.step(for:lowest:highest:)` (feature 004, reused unchanged) fed with `loggedBounds`, mapped to `AppColor` — `.low → success`, `.moderate → caution`, `.high → warning`, `.veryHigh → danger`. Wrap in `GlassCard`; state the period covered (FR-022); add the `progress.chart` identifier
- [X] T022 [US2] Expose per-day values to assistive technology in `DailyCaloriesChart.swift` so meaning is never carried by bar height and color alone — each day announces its total, and **unlogged days explicitly announce "no data"** using `progress.chart.noData` (FR-028)
- [X] T023 [US2] Wire `DailyCaloriesChart` into `Kalorias/Features/Progress/ProgressTabView.swift`, passing the `[DailyTally]` built once per body evaluation alongside the average and bounds
- [ ] T024 [US2] Validate quickstart.md **V3**: exactly 7 labelled slots ending today; unlogged days as labelled gaps, not zero bars; the average line unmoved by adding an unlogged day; lowest logged day green and highest red with no higher bar cooler than a lower one; and the chart's period visibly different from the weekly card's

**Checkpoint**: Both widgets work — grouped stats plus the 7-day pattern

---

## Phase 5: User Story 3 - Trustworthy empty and sparse states (Priority: P3)

**Goal**: With no data or very little, the tab explains itself instead of showing misleading zeros or a broken-looking chart.

**Independent Test**: On a fresh install open the Progress tab and confirm a clear empty state with no figures or chart; then log one meal and confirm both widgets render with no misleading zeros or broken comparisons.

### Implementation for User Story 3

- [X] T025 [P] [US3] Add the empty/sparse keys to `Kalorias/Resources/Localizable.xcstrings` with EN + ES and comments: `progress.empty.title`, `progress.empty.message`, `progress.week.noData` (`Nothing logged this week` / `Nada registrado esta semana`)
- [X] T026 [US3] Add the whole-tab empty state to `Kalorias/Features/Progress/ProgressTabView.swift`: when the `@Query` returns **no entries at all**, show a `ContentUnavailableView` and render **neither widget** — no card frames, no empty chart, no zeros (FR-018). Add the `progress.empty` identifier
- [X] T027 [US3] Handle the distinct "data exists but nothing this week" state in `Kalorias/Features/Progress/WeekSummaryCard.swift`: when `summary.hasData == false`, show the `progress.week.noData` message instead of a grid of zeros (FR-019), with the `progress.week.noData` identifier. Note this is a **different** state from T026 — the chart still renders its 7 slots here
- [X] T028 [US3] Audit every figure in `WeekSummaryCard.swift` and `DailyCaloriesChart.swift` for FR-020: confirm no `nil` value renders as a bare `0`, and that anything unavailable is either omitted or explicitly marked. Pay attention to `averagePerLoggedDay` and `highestDay`, both of which are optional
- [ ] T029 [US3] Validate quickstart.md **V4**: fresh install shows the explanatory empty state with no widget frames and no zeros; one logged meal renders both widgets with no comparison; data only in earlier weeks shows "nothing logged this week"; and no figure anywhere shows `0` where the truth is "unknown"

**Checkpoint**: All three stories independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T030 Build with zero warnings under Swift 6 strict concurrency: `xcodebuild -project Kalorias.xcodeproj -scheme Kalorias -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath /tmp/kal-005 clean build`. Any concurrency warning on the new `nonisolated` types is a failure, not a nit (Principle I)
- [X] T031 Run the full suite (`xcodebuild ... test`): the three new suites green **and** all **79** prior tests still passing. This feature writes nothing, so any feature 001–004 regression is a real defect
- [X] T032 [P] Confirm determinism: grep `Kalorias/Features/Progress/ProgressStatistics.swift` and the three new test files for `Calendar.current`, `Locale.current`, `TimeZone.current` and `Date()` — excluding comments, the only permitted occurrences are in `ProgressTabView.swift` at the view boundary (Principle II)
- [X] T033 [P] Confirm FR-026 (no writes): verify `Kalorias/Features/History/MealEntry.swift`, `MealHistoryRepository.swift`, `MealWeekGrouping.swift`, `CalorieColorScale.swift`, `HistoryView.swift` and `Kalorias/App/Router.swift` are unmodified, and that nothing in `Features/Progress/` calls `insert`, `delete` or `save`
- [X] T034 Audit `Kalorias/Resources/Localizable.xcstrings`: all 16 new keys present with `en` + `es` and translator comments, no raw key strings reachable on screen, and **every figure labelled *logged* / *registradas*** — no copy claiming actual intake or consumption (FR-021, FR-024)
- [ ] T035 Validate quickstart.md **V5**: both appearances (checking the `caution` yellow in **light** mode, the worst case for contrast), both languages, Larger Text wrapping rather than clipping, and VoiceOver reaching every day's value including "no data" days with change direction announced in words
- [ ] T036 Validate quickstart.md **V6**: with ≥ 1,000 saved meals across 52+ weeks the widgets appear in under 1 second with no stutter switching tabs. If not, the intended fix is a `@Query` predicate limited to the last ~14 days (research R8) — not restructuring the aggregation
- [ ] T037 Walk the Definition of Done checklist at the end of quickstart.md and check off every box

### Optional cleanup (maintainer's call — NOT required for this feature)

- [ ] T038 [P] Migrate the two pre-existing ad-hoc glass call sites to the shared helper: `.glassEffect(.regular, in: .rect(cornerRadius: 18))` at `Kalorias/Features/Analysis/AnalysisResultView.swift:125` and `Kalorias/Features/History/MealDetailsView.swift:100` → `GlassCard`. This brings the repo into compliance with Principle III's shared-helper clause, which those two sites currently violate. **Deliberately left optional**: it edits files this feature has no other reason to touch, so it is the maintainer's decision rather than something folded in silently. Verify both screens render identically afterwards

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies
- **Foundational (Phase 2)**: depends on Setup — **BLOCKS all user stories**
- **US1 (Phase 3)**: depends on Phase 2 (needs `DailyTally` for logged-day count and highest day, and `GlassCard`)
- **US2 (Phase 4)**: depends on Phase 2 (plots `DailyTally`; needs `loggedBounds`, `GlassCard`, and T002's Charts check)
- **US3 (Phase 5)**: depends on Phase 2; its `WeekSummaryCard` task (T027) also depends on US1 having created that file
- **Polish (Phase 6)**: depends on all desired stories. T038 is optional and independent

### User Story Dependencies

- **US1 (P1)**: independent once Phase 2 is done — the MVP
- **US2 (P2)**: independent of US1. Different files (`DailyCaloriesChart.swift`) — only overlaps in `ProgressTabView.swift` wiring
- **US3 (P3)**: **not** fully independent — T027 edits `WeekSummaryCard.swift`, which US1 creates. T026 (whole-tab empty state) is independent. Sequence US3 after US1

`ProgressStatistics.swift` is edited by T004 (foundational), T010 and T013 (US1) — those three
are strictly sequential. `ProgressTabView.swift` is edited by T007, T018, T023 and T026, also
sequential.

### Within Each User Story

- Pure types before the views that render them
- Each test file immediately followed by its `project.pbxproj` registration
- Localization keys before the view that references them
- Story validated before starting the next priority

### Parallel Opportunities

- **Phase 2**: T003 (`GlassCard`) and T004 (`ProgressStatistics`) are `[P]` — unrelated files
- **Phase 3**: T011 `[P]` (its own test file) and T016 `[P]` (the catalog) can run alongside the `ProgressStatistics` edits
- **Phase 4**: T020 `[P]` (catalog) alongside T021
- **Phase 5**: T025 `[P]` (catalog)
- **Phase 6**: T032 and T033 are `[P]` read-only verification passes; T038 is independent

---

## Parallel Example: Phase 2 Foundational

```bash
# Two unrelated files — launch together:
Task: "Create Kalorias/DesignSystem/GlassCard.swift shared native Liquid Glass surface"
Task: "Create Kalorias/Features/Progress/ProgressStatistics.swift with DailyTally + dailyTallies + averageOfLoggedDays + loggedBounds"

# Then sequentially:
# T005 DailyTallyTests → T006 pbxproj registration → T007 ProgressTabView → T008 RootView wiring → T009 verify
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1 Setup — baseline + Charts de-risk
2. Phase 2 Foundational — **blocks everything**
3. Phase 3 US1 — the weekly summary card
4. **STOP and VALIDATE**: quickstart V1 **and especially V2** (the elapsed-alignment rule)
5. Shippable: the tab answers "am I up or down versus last week?", which is the question users open it to ask

### Incremental Delivery

1. Setup + Foundational → tallies tested, glass surface exists, tab shell live
2. + US1 → weekly summary → validate → **MVP**
3. + US2 → 7-day chart → validate
4. + US3 → trustworthy empty and sparse states → validate
5. Phase 6 Polish → warnings, performance, accessibility, wording audit

### Notes

- `[P]` = different files, no dependency on an incomplete task
- Commit after each task or logical group — **manually**. The constitution forbids automated tooling from running `git commit`/`git push` or from offering to
- Stop at any checkpoint to validate a story independently
- Do **not** author or run UI tests (Principle II)
- **No new color token** in this feature — `success`/`caution`/`warning`/`danger` are reused, so unlike feature 004 the constitution's token table is not touched
- T002 and T038 are the two tasks that exist for reasons outside the happy path: one de-risks a new framework, the other offers to fix a pre-existing violation

---

## Validation status recorded during implementation

Screenshots were taken on the simulator by **temporarily** substituting fixture data in
`ProgressTabView` (reverted immediately — no throwaway code was committed, verified by grep).
That covered the parts of V1/V3/V4/V5 that are about rendering:

| Check | Status | Evidence |
|---|---|---|
| Empty state: explanatory copy, **no** widget frames, no zeros (FR-018) | ✅ verified | fresh-install screenshot, ES locale |
| Card layout: total, average, meal count, highest day; neutral arrow+text badge | ✅ verified | populated screenshot |
| Chart: 7 labelled slots, unlogged days as **labelled gaps** not zero bars (FR-012) | ✅ verified | `mar`/`jue` empty with labels intact |
| All four colour steps, ascending green → yellow → orange → red (FR-015/016) | ✅ verified | 400/700 green, 1200 yellow, 1800 orange, 2400 red |
| Both appearances legible (FR-025) | ✅ verified | light + dark screenshots |
| Spanish localization, no raw keys on screen | ✅ verified | both screenshots |
| **V2 mid-week alignment, observed live** | ⚠️ not verified | needs a Wed/Thu run; the rule is covered by `testTotalChangeUsesOnlyTheAlignedPortionOfThePreviousWeek` |
| V5 VoiceOver + Larger Text | ⚠️ not verified | needs a device/accessibility session |
| V6 performance at 1,000+ meals | ⚠️ not verified | needs seeded data |

### Defect found and fixed by looking at the screen

The first populated screenshot showed the three secondary stats misaligned: the
"Media por día registrado" label wrapped to two lines and pushed its value below the
neighbouring columns' values. `WeekSummaryCard` now puts the **value above the label**, so
values align regardless of label height and labels stay unclipped at large Dynamic Type
sizes. No unit test would have caught this.

### Observation on the `caution` token

Light mode renders it as a dark mustard (`#B8860B`) rather than a yellow, and it sits closer
to `warning` orange than ideal. That value was chosen in feature 004 for **text** contrast on
`surfacePrimary`; here it is a **bar fill**, where a brighter yellow would read better. Dark
mode (`#F2D24B`) reads as a clear yellow. Changing it is a design-system decision affecting
History too, so it was left alone.
