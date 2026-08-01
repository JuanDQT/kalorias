# Phase 1 Data Model: History Weekly Grouping & Calorie Color Scale

**Feature**: `004-history-week-grouping` | **Date**: 2026-07-26

> **No persistence change.** `MealEntry` keeps its exact SwiftData schema — no new
> stored property, no migration, no store version bump. Everything below is a
> **presentation-level** value type, built on the fly from the `@Query` results and
> discarded when the view goes away.

---

## Existing entity (read-only input)

### `MealEntry` — *unchanged*, `Kalorias/Features/History/MealEntry.swift`

| Field | Type | Used by this feature |
|---|---|---|
| `id` | `UUID` | row identity (already `Identifiable`) |
| `capturedAt` | `Date` | **grouping key + row timestamp** (FR-001, FR-010) |
| `totalCalories` | `Int` | **color scale input** (FR-011) |
| `title` | `String` | unchanged row content |
| `foods` | `[StoredFood]` | unchanged row content (macro summary) |
| `imageFileName` | `String` | unchanged row thumbnail |

**Only addition**: a `WeekGroupable` conformance (below). This is a protocol
conformance on an existing type — it adds no stored property and does not touch the
SwiftData schema.

---

## New presentation types

### `WeekGroupable` (protocol)

The minimal surface the grouping logic needs. Keeps `MealWeekGrouping` free of any
SwiftData import, so its tests run against plain structs.

| Member | Type | Notes |
|---|---|---|
| `capturedAt` | `Date` | determines the week the item falls in |
| `totalCalories` | `Int` | feeds the group's lowest/highest |

Conformers: `MealEntry` (production), a test fixture struct (tests).

---

### `MealWeekGroup<Item: WeekGroupable>`

One rendered section. Built by `MealWeekGrouping`, consumed by `HistoryView`.

| Field | Type | Meaning | Rules |
|---|---|---|---|
| `id` | `Date` | the week's start instant | doubles as `Identifiable` id; unique per group |
| `weekStart` | `Date` | first instant of the week | from `Calendar.dateInterval(of: .weekOfYear:)`, region-aware (FR-002) |
| `weekEnd` | `Date` | the week's **last day** | `weekStart + 6 days` — *inclusive*, not the exclusive interval end (see research R1) |
| `label` | `WeekHeaderLabel` | which header to draw | see below (FR-003…FR-006) |
| `items` | `[Item]` | the week's meals | non-empty by construction (FR-008); newest-first (FR-007) |
| `lowestCalories` | `Int` | min over `items` | color-scale floor (FR-011) |
| `highestCalories` | `Int` | max over `items` | color-scale ceiling (FR-011) |

**Invariants**

1. `items` is never empty — a group is only created when an entry falls in it, so
   empty weeks produce no group and no header (FR-008).
2. `lowestCalories <= highestCalories`; both equal when the group has one item or
   all items share a total (the degenerate case of FR-014).
3. Groups are emitted **newest week first**; `items` within a group stay
   **newest first** (FR-007).
4. Every entry lands in exactly one group (SC-001) — the grouping is a partition.

---

### `WeekHeaderLabel` (enum)

What the header says, as domain data — deliberately *not* a `String`, so the
localization lives in the view layer and the grouping stays testable without a
bundle.

| Case | Rendered as | When |
|---|---|---|
| `.currentWeek` | "Semana actual" / "This week" | group's week contains `now` (FR-003) |
| `.previousWeek` | "Semana anterior" / "Last week" | group's week contains `now − 1 week` (FR-004) |
| `.dateRange(start: Date, end: Date)` | "1 Febrero - 7 Febrero" | every older week (FR-005) |

`.dateRange` carries the inclusive endpoints; the year is added per endpoint at
render time when that endpoint's year ≠ the current year (FR-006).

---

### `CalorieColorStep` (enum)

An ordered four-step scale. Ordered so tests can assert monotonicity (FR-013)
without knowing anything about colors.

| Case | Order | Token (mapped in the view) | Meaning |
|---|---|---|---|
| `.low` | 0 | `AppColor.success` (green) | at/near the group's lowest total |
| `.moderate` | 1 | `AppColor.caution` (yellow, **new**) | |
| `.high` | 2 | `AppColor.warning` (orange) | |
| `.veryHigh` | 3 | `AppColor.danger` (red) | at the group's highest total |

Conforms to `Comparable` (via `Int` raw value) so a test can assert
`step(a) <= step(b)` whenever `a <= b`.

---

### `MealRowDisplay` (view-level value)

What `MealRowView` receives so its body does no formatting or scale work (research
R6). Constructed once per entry during the grouping pass.

| Field | Type | Source |
|---|---|---|
| `entry` | `MealEntry` | the row's data + navigation target |
| `formattedDate` | `String` | `MealDateFormatting.rowTimestamp(...)` (FR-010) |
| `colorStep` | `CalorieColorStep` | `CalorieColorScale.step(...)` (FR-011) |

---

## Derivation flow

```text
@Query [MealEntry]            (already sorted capturedAt DESC)
        │
        ▼
MealWeekGrouping.groups(from:calendar:now:)
        │  • bucket by Calendar.dateInterval(of: .weekOfYear)   → FR-001, FR-002
        │  • label each bucket vs `now`                          → FR-003…FR-006
        │  • min/max totalCalories per bucket                    → FR-011
        │  • sort buckets by weekStart DESC                      → FR-007
        ▼
[MealWeekGroup<MealEntry>]
        │
        ├─► WeekSectionHeaderView(label:)   → localized header text
        │
        └─► per item: CalorieColorScale.step(for:lowest:highest:)   → CalorieColorStep
                      MealDateFormatting.rowTimestamp(...)          → String
                      ▼
                  MealRowView(display:)
```

## Validation rules summary

| Rule | Source | Enforced by |
|---|---|---|
| Week bounds follow device region | FR-002 | `Calendar` passed in; `firstWeekday` respected |
| No empty groups | FR-008 | groups built only from present entries |
| Newest week first, newest item first | FR-007 | sort on `weekStart` DESC; `@Query` order preserved |
| Exactly one group per entry | SC-001 | dictionary keyed on week start |
| Monotonic color assignment | FR-013 | `position` non-decreasing in value |
| Degenerate group → `.low` | FR-014 | `highest <= lowest` guard |
| Endpoints hit green / red | FR-011 | `position` 0 → `.low`; 1.0 clamped → `.veryHigh` |
| No schema change | FR-018 | conformance only; no stored property added |
