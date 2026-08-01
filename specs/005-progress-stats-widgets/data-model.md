# Phase 1 Data Model: Progress Tab — Weekly Summary & 7-Day Calorie Chart

**Feature**: `005-progress-stats-widgets` | **Date**: 2026-07-26

> **Nothing is persisted and nothing is written.** `MealEntry` keeps its exact schema — no
> new stored property, no migration. Every type below is a **derived value** computed from
> the `@Query` results and discarded when the view goes away.

---

## Existing inputs (read-only)

### `MealEntry` — *unchanged*, `Kalorias/Features/History/MealEntry.swift`

| Field | Used by this feature |
|---|---|
| `capturedAt` | day bucketing + week windowing (FR-001, FR-010) |
| `totalCalories` | every total, average and color step (FR-011, FR-015) |
| `id`, `title`, `foods`, `imageFileName` | **not used** — macros are deferred to a later feature |

### `WeekGroupable` — *reused from feature 004*

Already declares exactly the two members this feature needs (`capturedAt`,
`totalCalories`). `MealEntry` already conforms. `ProgressStatistics` is generic over it, so
its tests run against plain fixture structs with no `ModelContainer` — the same seam feature
004 established.

### `CalorieColorStep` / `CalorieColorScale` — *reused from feature 004, unchanged*

Supplies the four-step green → yellow → orange → red scale for the chart bars, including the
degenerate-group guard that FR-017 depends on.

---

## New derived types

All live in `Kalorias/Features/Progress/ProgressStatistics.swift`, all `nonisolated`, no
SwiftUI import.

### `DailyTally`

One calendar day inside a window.

| Field | Type | Meaning | Rules |
|---|---|---|---|
| `day` | `Date` | start of that day | `id` for `Identifiable`; unique within a window |
| `totalCalories` | `Int` | Σ of that day's logged meals | `0` when `mealCount == 0` |
| `mealCount` | `Int` | meals logged that day | `>= 0` |
| `hasLog` | `Bool` | whether anything was logged | **derived from `mealCount > 0`, never from `totalCalories > 0`** (research R4) |

**Invariants**

1. `hasLog == (mealCount > 0)`. This is the discriminator that separates "no data" from a
   genuine zero — the distinction FR-012/FR-013 exist to protect.
2. A window always yields **exactly** one tally per day, including unlogged days, so the
   chart can render 7 labelled slots (FR-010).
3. Tallies are ordered oldest → newest (left to right in the chart).

---

### `PeriodChange`

A comparison between two periods. **Optional by design** — its absence is a meaningful state.

| Field | Type | Meaning |
|---|---|---|
| `direction` | `ChangeDirection` | `.up` / `.down` / `.unchanged` |
| `percent` | `Int` | magnitude, rounded, always non-negative (sign lives in `direction`) |

**Rules**

| # | Rule | Requirement |
|---|---|---|
| P1 | A zero (or negative) baseline yields **`nil`** — never `∞`, `NaN`, or `0%` | FR-006 |
| P2 | Equal values yield `.unchanged`, not `.up` with `0%` | FR-007 |
| P3 | `direction` is an enum, not a sign, so the view must render a glyph + text rather than relying on color | FR-028 |
| P4 | `percent` is rounded to the nearest integer and uncapped | research R3 |

---

### `WeekSummary`

Everything widget 1 renders.

| Field | Type | Meaning | Rules |
|---|---|---|---|
| `weekStart` | `Date` | first instant of the current week | region-aware (FR-002) |
| `elapsedDays` | `Int` | days elapsed in the week, inclusive of today | `1 ... 7`; drives the aligned comparison |
| `totalCalories` | `Int` | Σ logged calories this week | `0` when nothing logged |
| `loggedDayCount` | `Int` | days this week with ≥ 1 meal | the average's divisor |
| `mealCount` | `Int` | meals logged this week | descriptive only, no comparison (FR-009) |
| `averagePerLoggedDay` | `Int?` | `totalCalories / loggedDayCount` | **`nil` when `loggedDayCount == 0`** — never a division by zero, never a bare `0` (FR-020) |
| `highestDay` | `DailyTally?` | the week's biggest day | `nil` when nothing logged; ties resolve to the **most recent** (FR-008) |
| `totalChange` | `PeriodChange?` | vs the **same elapsed portion** of last week | `nil` when that baseline is empty (FR-005, FR-006) |
| `averageChange` | `PeriodChange?` | vs last week's full-week average per logged day | needs no elapsed alignment (research R2) |

**Invariants**

1. `averagePerLoggedDay` is `nil` — not `0` — when there are no logged days. A `0` here would
   assert "you averaged zero calories", which FR-020 forbids.
2. `hasData == (mealCount > 0)`; when false the widget renders the "nothing logged this week"
   message (FR-019) rather than a grid of zeros.
3. `totalChange` compares like-for-like day counts. This is the feature's single most
   important correctness rule — see research R2.
4. Both changes are independently optional: one can be present while the other is absent.

---

## Derivation flow

```text
@Query [MealEntry]  (newest-first)
        │
        ├──► ProgressStatistics.dailyTallies(from:calendar:endingOn:dayCount: 7)
        │         • bucket by startOfDay                            → FR-010, FR-011
        │         • emit a tally for EVERY day, hasLog = count > 0   → FR-012
        │         ▼
        │    [DailyTally] (7, oldest → newest)
        │         │
        │         ├─► average over tallies where hasLog              → FR-013, FR-014
        │         └─► min/max over tallies where hasLog
        │                   └─► CalorieColorScale.step(...)          → FR-015 … FR-017
        │                             ▼
        │                    DailyCaloriesChart
        │
        └──► ProgressStatistics.weekSummary(from:calendar:now:)
                  • current week window  [weekStart, now]            → FR-001, FR-002
                  • elapsedDays                                      → FR-005
                  • previous week aligned to elapsedDays             → FR-005
                  • PeriodChange (nil on zero baseline)              → FR-006, FR-007
                  • highestDay, most-recent on tie                   → FR-008
                        ▼
                   WeekSummary ──► WeekSummaryCard
```

## Validation rules summary

| Rule | Source | Enforced by |
|---|---|---|
| Unlogged day ≠ zero | FR-012, FR-013 | `hasLog` from `mealCount` |
| Average over logged days only | FR-003, FR-013 | `loggedDayCount` divisor |
| No division by zero | FR-020 | `averagePerLoggedDay` is `Int?` |
| Partial week compared like-for-like | FR-005 | `elapsedDays`-aligned baseline |
| No ∞ / NaN / 0-baseline percentage | FR-006, SC-006 | `PeriodChange` returns `nil` |
| Zero change reads as unchanged | FR-007 | `.unchanged` case |
| Deterministic highest day | FR-008 | most-recent tie-break |
| Region-aware weeks | FR-002 | injected `Calendar.firstWeekday` |
| Monotonic bar colors | FR-016 | reused `CalorieColorScale` |
| Exactly 7 day slots | FR-010 | one tally per day, always |
| No schema change | FR-026 | derived values only, no writes |
