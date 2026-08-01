---

description: "Task list for History Weekly Grouping & Calorie Color Scale"
---

# Tasks: History Weekly Grouping & Calorie Color Scale

**Input**: Design documents from `/specs/004-history-week-grouping/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/ui-contracts.md](./contracts/ui-contracts.md), [quickstart.md](./quickstart.md)

**Tests**: Unit tests are **REQUIRED** here — not optional. Constitution Principle II
(NON-NEGOTIABLE) mandates unit tests for any logic that computes, aggregates, or
converts values, covering the normal case, the zero/empty case, and at least one
boundary case. All three new types qualify. **UI tests stay OFF** (Principle II) —
do not author or run XCUITest.

**Organization**: Tasks are grouped by user story so each can be implemented,
tested, and shipped independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: US1 / US2 / US3 from spec.md
- Exact file paths are included in every task

## Path Conventions

Native iOS app, single SwiftUI target. Sources under `Kalorias/`, tests under
`KaloriasTests/`.

**Correction made during implementation**: only `Kalorias/` is a
filesystem-synchronized group. `KaloriasTests/` uses explicit file references, so
**new test files DO require a `project.pbxproj` edit** (new source files under
`Kalorias/` genuinely do not). The three new test files were registered there.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish the green baseline this feature must not regress

- [X] T001 Run the full suite to capture a green baseline: `xcodebuild -project Kalorias.xcodeproj -scheme Kalorias -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test` — record which suites pass so a later failure is unambiguously caused by this feature
- [ ] T002 Confirm the current History tab renders (flat list + empty state) in both light and dark and in EN + ES, so the "before" state is known before restructuring `Kalorias/Features/History/HistoryView.swift`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The date-composition type and the row display seam. Both are shared by
more than one story — `MealDateFormatting.weekRange` serves US1's range headers
(FR-005) and `MealDateFormatting.rowTimestamp` serves US2 (FR-010), while
`MealRowDisplay` is the seam US2 and US3 each populate one field of.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T003 [P] Add the four date-pattern keys to `Kalorias/Resources/Localizable.xcstrings` with EN + ES values **and a translator comment on each documenting what every positional argument means**: `history.week.range` (`%1$@ - %2$@`), `history.week.dayMonth` (`%1$@ %2$@` = day, full month), `history.week.dayMonthYear` (`%1$@ %2$@ %3$@` = day, full month, year), `history.date.rowFormat` (`%1$@ %2$@ %3$@, %4$@` = weekday-with-period, day, abbreviated month, time). Positional specifiers are mandatory — bare `%@` would block a language from reordering
- [X] T004 Create `Kalorias/Features/History/MealDateFormatting.swift`: a `nonisolated struct` with `init(locale:calendar:timeZone:)`, `rowTimestamp(for:) -> String`, and `weekRange(start:end:referenceYear:) -> String`. Build strings from `shortWeekdaySymbols` / `shortMonthSymbols` / `standaloneMonthSymbols` capitalized with `capitalized(with: locale)` on the **first letter only**, and get the time from a `DateFormatter` using `setLocalizedDateFormatFromTemplate("jmm")` — the `j` skeleton is what honors the device's 12/24-hour setting. Cache the formatters as instance properties so one instance serves a whole grouping pass (research R6). Never hardcode a `dateFormat` pattern (Principle VI)
- [X] T005 [P] Create `KaloriasTests/MealDateFormattingTests.swift` covering all 10 cases in quickstart.md §"MealDateFormattingTests": `es_ES` → `"Vie. 25 Jul, 16:40"`, `en_US` 12-hour, `en_GB` 24-hour (proves `jmm` not `HH`), capitalization in both languages, explicit time zone, `weekRange` same-year / older-year / New-Year-straddling, and determinism. Every test injects its own `Locale`, `Calendar`, `TimeZone` — a test that reads `.current` will pass locally and fail in CI (Principle II)
- [X] T006 Introduce `MealRowDisplay` (fields: `entry`, `formattedDate`, `colorStep`) and change `MealRowView`'s signature from `(entry:imageStore:)` to `(display:imageStore:)` in `Kalorias/Features/History/MealRowView.swift`, updating `Kalorias/Features/History/HistoryView.swift` to construct it from the existing flat list. **Behavior-preserving refactor**: keep the current `.dateTime.day().month().hour().minute()` output and the fixed `AppColor.brandPrimary` calorie color for now — US2 and US3 replace them
- [X] T007 Rebuild and re-run the suite; confirm zero warnings and the same passing set as T001. The screen must look **identical** to T002 at this point

**Checkpoint**: Date composition is tested and available, and rows read from a display value — user stories can now begin

---

## Phase 3: User Story 1 - Meals grouped by week with meaningful headers (Priority: P1) 🎯 MVP

**Goal**: Break the flat History list into calendar-week sections headed by "Semana actual", "Semana anterior", or a `1 Febrero - 7 Febrero` range, newest week first, with no header for an empty week.

**Independent Test**: With meals saved across this week, last week, and at least one older week, open the History tab and confirm three headers appear in that order with the correct labels, each followed only by the meals belonging to that week.

### Implementation for User Story 1

- [X] T008 [P] [US1] Create `Kalorias/Features/History/MealWeekGrouping.swift` with the `WeekGroupable` protocol (`capturedAt`, `totalCalories`), `MealWeekGroup<Item>` (`id`/`weekStart`/`weekEnd`/`label`/`items`/`lowestCalories`/`highestCalories`), `WeekHeaderLabel` (`.currentWeek` / `.previousWeek` / `.dateRange(start:end:)`), and `static func groups(from:calendar:now:)`. **No SwiftUI import** — this file returns domain enums, never a `Color`. Bucket on `calendar.dateInterval(of: .weekOfYear, for:)?.start`; set `weekEnd = weekStart + 6 days` (the interval's own `end` is exclusive and would render an off-by-one header); sort groups by `weekStart` descending. Handle the optional `dateInterval` with a documented `startOfDay` fallback — **no force-unwrap** (Principle I)
- [X] T009 [P] [US1] Add a `WeekGroupable` conformance for `MealEntry` in `Kalorias/Features/History/MealEntry.swift`. Conformance only — **no stored property, no schema change, no migration** (FR-018); `capturedAt` and `totalCalories` already exist
- [X] T010 [P] [US1] Create `KaloriasTests/MealWeekGroupingTests.swift` covering all 13 cases in quickstart.md §"MealWeekGroupingTests", including the two that catch the likeliest bugs: a **Monday-first vs Sunday-first** calendar splitting the same Sun/Mon instant pair differently (FR-002), and `weekEnd` being the week's **last day** rather than the exclusive interval end (FR-005). Also assert the partition property (Σ items == input count, no duplicate ids) and that a gap week produces no empty group. Use fixture structs conforming to `WeekGroupable` — **not** `MealEntry` — so no `ModelContainer` is needed
- [X] T011 [P] [US1] Add `history.week.current` (`This week` / `Semana actual`) and `history.week.previous` (`Last week` / `Semana anterior`) to `Kalorias/Resources/Localizable.xcstrings` with both EN and ES values
- [X] T012 [US1] Create `Kalorias/Features/History/WeekSectionHeaderView.swift` mapping a `WeekHeaderLabel` to localized text: `.currentWeek`/`.previousWeek` to their keys, `.dateRange` through `MealDateFormatting.weekRange(start:end:referenceYear:)` with the current year as reference. Style it as a plain section header using `AppColor` tokens; **no `.lineLimit(1)` and no fixed height** so large Dynamic Type sizes wrap instead of clipping (FR-019) (depends on T003–T004, T008)
- [X] T013 [US1] Restructure `Kalorias/Features/History/HistoryView.swift` from `List(entries)` to `List { ForEach(groups) { group in Section { rows } header: { WeekSectionHeaderView(label: group.label) } } }`, deriving `groups` as a computed property from the `@Query` results via `MealWeekGrouping.groups(from:calendar:now:)` with `Calendar.current` and `Date()` read **only here**, at the view boundary. Construct one `MealDateFormatting` per grouping pass and reuse it for every row (research R6). Keep `.listStyle(.plain)`, the `Button` + `.buttonStyle(.plain)` wrapper, `.listRowBackground(Color.clear)`, `.navigationTitle`, `.navigationDestination`, `router.openMeal(entry)`, and the empty-state branch **unchanged** (depends on T008, T012)
- [X] T014 [US1] Add the `history.week.header` accessibility identifier to the header text in `Kalorias/Features/History/WeekSectionHeaderView.swift` and confirm the existing ids (`history.list`, `history.empty`, `history.row`, `history.row.title`, `history.row.date`, `history.row.total`) still resolve after the restructure
- [ ] T015 [US1] Validate quickstart.md **V1** (three headers in order; only that week's meals under each; newest-first within a section; no header for an empty week; empty history shows the existing empty state with **no** headers) and **V2** (switch Region to United States → weeks run Sunday–Saturday; back to Spain → Monday–Sunday)

**Checkpoint**: History is grouped by week with correct headers and ordering — independently shippable

---

## Phase 4: User Story 2 - Readable day-and-time stamp on every meal (Priority: P2)

**Goal**: Every row's timestamp reads `Vie. 25 Jul, 16:40` — abbreviated weekday, day, abbreviated month, time — in the device's language and 12/24-hour convention.

**Independent Test**: Open the History tab with saved meals and confirm every row's timestamp follows the weekday/day/month/time pattern in the device language.

### Implementation for User Story 2

- [X] T016 [US2] In `Kalorias/Features/History/HistoryView.swift`, populate `MealRowDisplay.formattedDate` from `MealDateFormatting.rowTimestamp(for: entry.capturedAt)` using the per-pass formatter instance — formatting happens **once at group-build time**, never inside a row body (FR-017)
- [X] T017 [US2] In `Kalorias/Features/History/MealRowView.swift`, render `display.formattedDate` as plain `Text` and delete the inline `Text(entry.capturedAt, format: .dateTime.day().month().hour().minute())`. Keep the `.caption` / `AppColor.textSecondary` styling and the `history.row.date` identifier
- [ ] T018 [US2] Validate quickstart.md **V3**: rows read `Vie. 25 Jul, 16:40`; toggling **24-Hour Time** off yields `4:40 PM` (this is the check that catches a hardcoded `HH:mm`); switching the app to English yields English weekday/month abbreviations correctly arranged

**Checkpoint**: US1 and US2 both work — grouped list with readable timestamps

---

## Phase 5: User Story 3 - Calorie figures colored from green to red within each week (Priority: P3)

**Goal**: Within each week group, color the calorie number on a green → yellow → orange → red scale from that group's own lowest and highest totals.

**Independent Test**: With several meals of clearly different calorie totals in one week, open the History tab and confirm the lowest total is green, the highest is red, and intermediate totals take yellow/orange in ascending order.

### Implementation for User Story 3

- [X] T019 [P] [US3] Create `Kalorias/Assets.xcassets/Palette/Caution.colorset/Contents.json` following the shape of the existing palette entries (sRGB, universal idiom, plus a `luminosity: dark` appearance variant): light `#B8860B`, dark `#F2D24B`. The light value is a dark goldenrod rather than a bright yellow because this token is used as **text** — a bright yellow lands near 1.9:1 on `surfacePrimary` `#F7F8F6` and fails legibility (research R5)
- [X] T020 [US3] Expose `static let caution = Color(.caution)` in the Status section of `Kalorias/DesignSystem/AppColor.swift` with a doc comment describing its role (second step of the calorie scale) (depends on T019)
- [X] T021 [US3] Add the `caution` row to the token table in the "Design System & Color Tokens" section of `.specify/memory/constitution.md` and bump the version 1.1.0 → 1.1.1 (PATCH — a palette addition, no principle touched), updating the Sync Impact Report header and **Last Amended** date. The constitution requires this **in the same change** as the colorset; shipping the token without it violates its own amendment rule (depends on T019)
- [X] T022 [P] [US3] Create `Kalorias/Features/History/CalorieColorScale.swift` with `CalorieColorStep: Int, Comparable, CaseIterable` (`.low`/`.moderate`/`.high`/`.veryHigh`) and `static func step(for:lowest:highest:) -> CalorieColorStep`. Guard `highest <= lowest → .low` first (covers the single-item and all-equal groups **and** removes the divide-by-zero), then `position = (value - lowest) / (highest - lowest)` and `index = min(3, Int(position * 4))`. **No SwiftUI import** — returns a domain enum, never a `Color` (Principle I)
- [X] T023 [P] [US3] Create `KaloriasTests/CalorieColorScaleTests.swift` covering all 8 cases in quickstart.md §"CalorieColorScaleTests". The must-have is the **top-endpoint clamp**: `value == highest` produces a raw index of `4`, and only `min(3, …)` turns it into `.veryHigh` — without that test the bug ships as an out-of-range step. Also assert monotonicity across an ascending sweep (FR-013), the quarter-band boundaries, and `highest < lowest` returning `.low` without crashing
- [X] T024 [US3] In `Kalorias/Features/History/HistoryView.swift`, populate `MealRowDisplay.colorStep` from `CalorieColorScale.step(for: entry.totalCalories, lowest: group.lowestCalories, highest: group.highestCalories)` — using **that group's** bounds, so each week is scaled against itself (FR-012) (depends on T022)
- [X] T025 [US3] In `Kalorias/Features/History/MealRowView.swift`, map `display.colorStep` to tokens for the calorie number's `.foregroundStyle` — `.low → AppColor.success`, `.moderate → AppColor.caution`, `.high → AppColor.warning`, `.veryHigh → AppColor.danger` — replacing the fixed `AppColor.brandPrimary`. Leave the number itself as text so the information is never color-only, and keep the `kcal` unit label on `AppColor.textSecondary` (depends on T020, T024)
- [ ] T026 [US3] Validate quickstart.md **V4**: lowest green / highest red / middles ascending; two week sections scaled independently (the same kcal figure may legitimately differ in color between weeks); a single-meal week shows **green, not red**; an all-equal week shows all green

**Checkpoint**: All three user stories independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T027 Build with zero warnings under Swift 6 strict concurrency: `xcodebuild -project Kalorias.xcodeproj -scheme Kalorias -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build` — any concurrency warning on the new `nonisolated` types is a failure, not a nit (Principle I)
- [X] T028 Run the full suite and confirm the three new suites pass **and** every feature-003 suite from the T001 baseline still passes — this feature must not regress persistence
- [X] T029 [P] Grep the three new source files and their tests for `Calendar.current`, `Locale.current`, `TimeZone.current`, and `Date()`; the only permitted occurrences are inside `Kalorias/Features/History/HistoryView.swift` at the view boundary (Principle II determinism)
- [X] T030 [P] Confirm FR-018 held: `git diff` shows no change to `MealEntry`'s stored properties, and `MealDetailsView.swift`, `MealHistoryRepository.swift`, `ImageStore.swift`, `MealTitle.swift`, and `Router.swift` are untouched
- [ ] T031 Validate quickstart.md **V5**: both appearances (paying particular attention to the new `caution` yellow in **light** mode, the worst case for contrast — verify ≥ 3:1 against `surfacePrimary`), both languages with no raw key strings on screen, Larger Text sizes wrapping headers instead of clipping, and VoiceOver announcing each section header as context for its rows
- [ ] T032 Validate quickstart.md **V6**: with ≥ 1,000 entries across 52+ weeks, the list appears in under 1 second and flick-scrolls smoothly. If not, profile with Instruments — the prime suspect is `DateFormatter` construction leaking into a row body instead of happening once per grouping pass
- [X] T033 Confirm all 6 new keys in `Kalorias/Resources/Localizable.xcstrings` carry EN + ES values with translator comments, and that no user-facing string literal was introduced in `HistoryView.swift`, `WeekSectionHeaderView.swift`, or `MealRowView.swift` (Principle VI)
- [ ] T034 Walk the Definition of Done checklist at the end of quickstart.md and check off every box

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies — start immediately
- **Foundational (Phase 2)**: depends on Setup — **BLOCKS all user stories**
- **US1 (Phase 3)**: depends on Phase 2
- **US2 (Phase 4)**: depends on Phase 2; touches lines in `HistoryView`/`MealRowView` that US1 also touches
- **US3 (Phase 5)**: depends on Phase 2; same file overlap as US2
- **Polish (Phase 6)**: depends on all desired stories

### User Story Dependencies

- **US1 (P1)**: independent once Phase 2 is done — the MVP
- **US2 (P2)**: logically independent (its formatter is fully tested in Phase 2); only a *file-level* overlap with US1 in `HistoryView.swift` and `MealRowView.swift`
- **US3 (P3)**: logically independent; same file-level overlap. Its calorie scale needs *some* group bounds — with US1 done those are per-week (the spec'd behavior); without US1 they would be whole-list bounds, so **ship US3 after US1** for correct semantics

This is deliberately a single-screen feature: the three stories are independently
*testable and demoable*, but T013, T016/T017, and T024/T025 all edit the same two
view files, so one developer should carry Phases 3–5 sequentially rather than
splitting them.

### Within Each User Story

- Pure logic types before the views that consume them
- Tests authored alongside their type (Principle II permits "before or alongside"; in Swift, writing a test against a type that does not yet exist breaks the build rather than producing a red test)
- Localization keys before the view that references them
- Story complete and validated before starting the next priority

### Parallel Opportunities

- **Phase 2**: T003 and T005 are `[P]`; T004 depends on T003, and T005 is written against T004's signatures
- **Phase 3**: T008, T009, T010, T011 are all `[P]` — four different files. T012–T014 are sequential (same view files)
- **Phase 5**: T019, T022, T023 are `[P]`; T021 (constitution) runs parallel to T022/T023
- **Phase 6**: T029 and T030 are `[P]` — read-only verification passes

---

## Parallel Example: User Story 1

```bash
# Four independent files — launch together:
Task: "Create MealWeekGrouping.swift with WeekGroupable, MealWeekGroup, WeekHeaderLabel, groups(from:calendar:now:)"
Task: "Add WeekGroupable conformance for MealEntry in Kalorias/Features/History/MealEntry.swift"
Task: "Create KaloriasTests/MealWeekGroupingTests.swift with the 13 quickstart cases"
Task: "Add history.week.current and history.week.previous to Localizable.xcstrings (EN+ES)"

# Then sequentially (both touch the same view files):
# T012 WeekSectionHeaderView → T013 HistoryView sections → T014 accessibility ids
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1 Setup — capture the green baseline
2. Phase 2 Foundational — **blocks everything**
3. Phase 3 US1 — grouped list with headers
4. **STOP and VALIDATE**: quickstart V1 + V2, both languages, both appearances
5. Shippable: the History tab is grouped by week, which is the core of the request

### Incremental Delivery

1. Setup + Foundational → date composition tested, row seam in place
2. + US1 → grouped list with headers → validate → **MVP**
3. + US2 → readable `Vie. 25 Jul, 16:40` timestamps → validate
4. + US3 → per-week calorie color scale → validate
5. Phase 6 Polish → performance, accessibility, zero-warning build

### Notes

- `[P]` = different files, no dependency on an incomplete task
- Commit after each task or logical group — **manually**; the constitution forbids automated tooling from running `git commit` or `git push`, or from offering to
- Stop at any checkpoint to validate a story independently
- New sources under `Kalorias/` need no `project.pbxproj` edit; new files in `KaloriasTests/` do (see Path Conventions)
- Do **not** author or run UI tests (Principle II)
- T021 (constitution token table) is not optional bookkeeping: the constitution's own Design System section requires the table and the colorset to land together
