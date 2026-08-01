# Implementation Plan: Progress Tab — Weekly Summary & 7-Day Calorie Chart

**Branch**: `005-progress-stats-widgets` | **Date**: 2026-07-26 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/005-progress-stats-widgets/spec.md`

## Summary

Replace the empty `ProgressPlaceholderView` with two widgets built entirely from data
that already exists: a **current-week summary** (total logged kcal, average per logged
day, meal count, highest day, plus an elapsed-aligned comparison against last week) and
a **rolling 7-day bar chart** (one bar per day, average indicator, days without logs
rendered as labelled gaps rather than zeros).

Technical approach (native, per constitution): one new **pure, `nonisolated`,
unit-testable** file — `ProgressStatistics.swift` — holds every figure the tab shows
(`DailyTally`, `PeriodChange`, `WeekSummary` and the functions that build them), generic
over feature 004's existing `WeekGroupable` protocol so its tests need no
`ModelContainer`. The chart uses **Swift Charts** (`BarMark` + `RuleMark`), an Apple
framework. Feature 004's `CalorieColorScale` is reused verbatim for bar coloring, which
satisfies three requirements for free. Nothing is written: `MealEntry`, the History tab,
and the analysis flow are untouched.

Three findings shape the design (see [research.md](./research.md)):

1. **`ProgressView` is a SwiftUI built-in type.** The tab root must not be named that; it
   is `ProgressTabView`.
2. **The "no data" day is not a styled bar — it is a labelled gap.** A ghost bar at any
   nonzero height reads as a small value, which is exactly the lie FR-012 exists to
   prevent. Logged days get a `BarMark`; the axis is pinned to all 7 days so unlogged
   days appear as labelled empty slots.
3. **The constitution's shared-glass-helper rule is already being violated.**
   `.glassEffect(.regular, in: .rect(cornerRadius: 18))` is duplicated ad hoc in
   `AnalysisResultView` and `MealDetailsView`. This feature adds two more card surfaces,
   so it introduces the missing shared helper rather than making it four copies.

## Technical Context

**Language/Version**: Swift 6 (strict concurrency `complete`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`).

**Primary Dependencies**: SwiftUI, **Swift Charts** (`BarMark`, `RuleMark`,
`chartXScale`) — new to the project but an Apple framework, so it satisfies the
constitution's "prefer Apple frameworks" constraint with no third-party dependency.
Foundation (`Calendar`, `DateComponents`). SwiftData (`@Query`, read-only). Reuses
feature 004's `WeekGroupable` and `CalorieColorScale`, and feature 003's `MealEntry`.

**Storage**: None added. Reads `MealEntry.capturedAt` and `MealEntry.totalCalories`.
**No schema change, no migration, no writes.**

**Testing**: XCTest in `KaloriasTests`, three new suites. Every pure function takes its
`Calendar` and "now" as **parameters**, so tests are deterministic and locale/clock
independent (Principle II). Fixtures conform to `WeekGroupable`, so no `ModelContainer`
is needed. UI tests OFF.

**Target Platform**: iOS 26.5+.

**Project Type**: Native iOS app (single SwiftUI target). New sources under `Kalorias/`
are auto-included; **new test files require a `project.pbxproj` edit** (only `Kalorias/`
is a filesystem-synchronized group — learned in feature 004).

**Performance Goals**: Progress tab visible < 1s and responsive with ≥ 1,000 saved meals
across 52+ weeks (SC-007). Aggregation is a single O(n) pass per data change, computed
once per body evaluation — never per bar or per tile.

**Constraints**: no calorie goal anywhere (explicitly out of scope — the tab is
comparative, not goal-relative); days without logs must never be treated as zero;
percentage change from a zero baseline must be suppressed, not shown as ∞; all colors
from `AppColor`; glass through a shared helper; EN+ES for every string; no writes.

**Scale/Scope**: 1 new pure statistics file + 1 shared glass helper + 3 new views
(tab root + 2 widgets); 1 placeholder deleted; `RootView` rewired by one line; 3 new
test suites. No persistence, navigation, or analysis changes.

## Constitution Check

*GATE: evaluated against Kalorias Constitution v1.1.1. Re-checked after Phase 1 — see below.*

| Principle | Gate | Status |
|-----------|------|--------|
| I. Code Quality | Every total, average, percentage, bucketing and highest-day selection lives in `ProgressStatistics`, never in a view body; no force-unwraps (`dateComponents(...).day` and `date(byAdding:)` optionals handled with documented fallbacks). | ✅ |
| II. Testing (NON-NEG) | This feature is almost entirely arithmetic, so coverage is the deliverable: normal, zero/empty, and boundary cases for day bucketing, per-logged-day averaging, elapsed-week alignment, zero-baseline suppression, and highest-day ties. 3 new suites. UI tests off. | ✅ see [quickstart.md](./quickstart.md) |
| III. UX Consistency | HIG layout; **native Liquid Glass via a new shared `GlassCard` helper** (fixing an existing ad-hoc-usage violation); `AppColor` only; explicit empty and sparse states; no destructive actions; no async work so no loading state is required; Dynamic Type + VoiceOver with chart values exposed to assistive tech (FR-028). | ✅ |
| IV. Performance | Single O(n) aggregation pass per data change; figures computed once per body evaluation, not per bar/tile; no main-thread blocking work added (all reads are local). | ✅ |
| V. Architecture (NON-NEG) | Swift 6 strict; MV — the view is a pure function of `@Query` state through pure functions; no ViewModel; **Router untouched** (no navigation added, drill-down out of scope). | ✅ |
| VI. Localization & Appearance (NON-NEG) | Every new string EN+ES; percentages and numbers formatted per locale; direction conveyed by an arrow glyph **and** text, never by color alone; verified in light and dark. | ✅ |
| Tech Constraints | Swift Charts is an Apple framework (`Charts.framework` ships in the iOS SDK), so it needs no third-party justification. No network; nothing leaves the device. | ✅ |
| Design System (governance) | Reuses `success` / `caution` / `warning` / `danger` — **no new token**, so no constitution table change this time. | ✅ |

**Result**: All gates pass. One pre-existing violation is *corrected* by this feature
rather than propagated (see Complexity Tracking). No new violations → nothing to justify.

## Project Structure

### Documentation (this feature)

```text
specs/005-progress-stats-widgets/
├── plan.md                  # This file
├── research.md              # Phase 0 — 8 resolved decisions
├── data-model.md            # Phase 1 — presentation-only value types
├── quickstart.md            # Phase 1 — build/test/validate guide
├── contracts/
│   └── ui-contracts.md      # pure-function APIs, screen states, a11y ids, l10n keys
├── checklists/requirements.md
└── tasks.md                 # /speckit-tasks (not created here)
```

### Source Code (repository root)

```text
Kalorias/
├── DesignSystem/
│   ├── GlassCard.swift                     # NEW: shared native Liquid Glass card surface
│   └── AppColor.swift                      # UNCHANGED (success/caution/warning/danger reused)
├── Features/Progress/
│   ├── ProgressPlaceholderView.swift       # DELETED (replaced by ProgressTabView)
│   ├── ProgressTabView.swift               # NEW: tab root — @Query, empty state, both widgets
│   ├── ProgressStatistics.swift            # NEW: pure DailyTally / PeriodChange / WeekSummary
│   ├── WeekSummaryCard.swift               # NEW: widget 1
│   └── DailyCaloriesChart.swift            # NEW: widget 2 (Swift Charts)
├── Features/History/
│   ├── MealWeekGrouping.swift              # UNCHANGED — `WeekGroupable` reused
│   └── CalorieColorScale.swift             # UNCHANGED — reused verbatim for bar colors
├── App/
│   └── RootView.swift                      # MODIFIED: `.progress` → ProgressTabView()
└── Resources/
    └── Localizable.xcstrings               # MODIFIED: new Progress keys (EN+ES)

KaloriasTests/                              # add (all three need a project.pbxproj entry)
├── DailyTallyTests.swift
├── WeekSummaryTests.swift
└── PeriodChangeTests.swift
```

**Structure Decision**: The feature lives in the existing `Features/Progress/` folder.
All arithmetic is concentrated in one `nonisolated` file with **zero SwiftUI imports**,
generic over `WeekGroupable` — the same seam that made feature 004's grouping testable
without SwiftData, reused rather than reinvented. The two widgets are dumb views that
render a `WeekSummary` and a `[DailyTally]`; they compute nothing. `GlassCard` goes in
`DesignSystem/` because it is app-wide, not Progress-specific.

### Post-Design Constitution Re-Check

Re-evaluated after the Phase 1 artifacts were written:

- **No new violations.** No ViewModel, no third-party dependency, no network, no writes,
  no new color token.
- **Principle I/II strengthened**: making `ProgressStatistics` generic over the existing
  `WeekGroupable` keeps SwiftData entirely out of the test path, so all three suites are
  pure-function tests.
- **Principle III improved beyond this feature's scope**: `GlassCard` gives the project
  the shared glass helper the constitution has always required.
- **Principle IV**: aggregation was deliberately designed as one pass returning finished
  value types, so no figure is recomputed per bar or per tile during scrolling/redraw.
- **Principle VI**: `PeriodChange` carries a `direction` enum rather than a signed
  number, which forces the view to render an explicit glyph and text instead of relying
  on red/green alone.

## Complexity Tracking

> No violations introduced by this feature. The row below records a **pre-existing**
> violation this feature corrects, for traceability.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Ad-hoc `.glassEffect(.regular, in: .rect(cornerRadius: 18))` duplicated in `AnalysisResultView.swift:125` and `MealDetailsView.swift:100` — Principle III requires glass to be drawn "through the project's shared helpers rather than by scattering `.glassEffect(...)` ad hoc per screen" | This feature adds two more glass card surfaces. Repeating the modifier a third and fourth time would deepen a violation the constitution names explicitly. | Adding two more copies was rejected: it makes future tinting/grouping changes a four-site edit. Migrating the two existing call sites is **optional cleanup**, flagged separately rather than folded in silently, since it touches files outside this feature. |
