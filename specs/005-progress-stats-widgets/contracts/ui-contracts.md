# Phase 1 Contracts: Progress Tab — Weekly Summary & 7-Day Calorie Chart

**Feature**: `005-progress-stats-widgets` | **Date**: 2026-07-26

The app exposes no network or CLI surface, so the contracts are the **pure-function APIs**
(the seam tests bind to), the **screen states**, the **accessibility identifiers**, and the
**localization keys**. Signatures are the contract; bodies belong to implementation.

---

## 1. Pure logic API

`Kalorias/Features/Progress/ProgressStatistics.swift` — `nonisolated`, no SwiftUI import.

```swift
nonisolated enum ChangeDirection { case up, down, unchanged }

nonisolated struct PeriodChange: Equatable {
    let direction: ChangeDirection
    let percent: Int            // magnitude only; never negative
}

nonisolated struct DailyTally: Identifiable, Equatable {
    let day: Date               // start of day; also `id`
    let totalCalories: Int
    let mealCount: Int
    var hasLog: Bool { mealCount > 0 }
}

nonisolated struct WeekSummary: Equatable {
    let weekStart: Date
    let elapsedDays: Int              // 1...7
    let totalCalories: Int
    let loggedDayCount: Int
    let mealCount: Int
    let averagePerLoggedDay: Int?     // nil when loggedDayCount == 0
    let highestDay: DailyTally?       // nil when nothing logged
    let totalChange: PeriodChange?    // vs same elapsed portion of last week
    let averageChange: PeriodChange?  // vs last week's per-logged-day average
    var hasData: Bool { mealCount > 0 }
}

nonisolated enum ProgressStatistics {
    /// One tally per day for `dayCount` days ending on the day containing `endingOn`,
    /// oldest first. Emits a tally for unlogged days too (hasLog == false).
    static func dailyTallies<Item: WeekGroupable>(
        from items: [Item],
        calendar: Calendar,
        endingOn: Date,
        dayCount: Int
    ) -> [DailyTally]

    /// Figures for the week containing `now`, with comparisons against the previous week.
    static func weekSummary<Item: WeekGroupable>(
        from items: [Item],
        calendar: Calendar,
        now: Date
    ) -> WeekSummary

    /// Mean of the logged days only; nil when none are logged.
    static func averageOfLoggedDays(_ tallies: [DailyTally]) -> Int?

    /// Lowest/highest totals among logged days; nil when none are logged.
    static func loggedBounds(_ tallies: [DailyTally]) -> (lowest: Int, highest: Int)?

    /// nil when `baseline <= 0` — the zero-baseline suppression rule.
    static func change(current: Int, baseline: Int) -> PeriodChange?
}
```

### Contract guarantees

**`dailyTallies`**

| # | Guarantee | Requirement |
|---|---|---|
| D1 | Returns exactly `dayCount` tallies, oldest first, ending on `endingOn`'s day | FR-010 |
| D2 | A day with no meals still gets a tally, with `mealCount == 0` and `hasLog == false` | FR-012 |
| D3 | `totalCalories` is the Σ of that day's meals; `0` iff `mealCount == 0` | FR-011 |
| D4 | `hasLog` derives from `mealCount`, **never** from `totalCalories` — a logged 0 kcal meal still counts as logged | research R4 |
| D5 | Items outside the window are ignored; items on the boundary days are included | FR-010 |
| D6 | Day bucketing uses the supplied calendar's time zone | FR-010 |
| D7 | Empty input yields `dayCount` tallies all with `hasLog == false` | FR-018 |

**`weekSummary`**

| # | Guarantee | Requirement |
|---|---|---|
| W1 | The week follows the calendar's `firstWeekday` | FR-002 |
| W2 | `elapsedDays` is 1 on the week's first day and 7 on its last | FR-005 |
| W3 | `totalCalories` / `mealCount` cover only the current week | FR-001 |
| W4 | `averagePerLoggedDay` divides by days with ≥ 1 meal, and is `nil` when there are none | FR-003, FR-020 |
| W5 | `highestDay` is the greatest total; ties resolve to the **most recent** day | FR-008 |
| W6 | `totalChange`'s baseline is the previous week's **first `elapsedDays` days only** | FR-005 |
| W7 | `averageChange`'s baseline is the previous week's full per-logged-day average | research R2 |
| W8 | Either change is `nil` when its baseline is empty or zero | FR-006 |
| W9 | Empty input yields `hasData == false` with `nil` average, highest day and changes | FR-019 |
| W10 | Never force-unwraps; date arithmetic optionals use documented fallbacks | Principle I |
| W11 | Uses `date(byAdding: .day,)` — **not** fixed-second arithmetic — so DST shifts do not move window edges | research R2 |

**`change(current:baseline:)`**

| # | Guarantee | Requirement |
|---|---|---|
| C1 | `baseline <= 0` → `nil` | FR-006, SC-006 |
| C2 | `current == baseline` → `.unchanged`, `percent == 0` | FR-007 |
| C3 | `current > baseline` → `.up`; `current < baseline` → `.down` | FR-004 |
| C4 | `percent` is the rounded absolute percentage magnitude | research R3 |
| C5 | Never returns `NaN`, infinity, or a negative `percent` | SC-006 |

---

## 2. Screen state contract — `ProgressTabView`

> Named `ProgressTabView`, **not** `ProgressView` — that name is a SwiftUI built-in
> (research R1).

| State | Condition | Rendering |
|---|---|---|
| Empty | `@Query` returns no entries at all | `ContentUnavailableView` only — **no widget frames, no chart, no zeros** (FR-018) |
| No data this week | entries exist, `summary.hasData == false` | summary card shows an explicit "nothing logged this week" message; chart still renders its 7 slots (FR-019) |
| Populated | ≥ 1 entry this week | both widgets render fully |

`RootView.swift` changes one line: `case .progress:` renders `ProgressTabView()` instead of
`ProgressPlaceholderView()`. `ProgressPlaceholderView.swift` is deleted (no dead code,
Principle I). The Router is **not** touched — this feature adds no navigation.

### `WeekSummaryCard` (widget 1)

Renders a `WeekSummary`. Computes nothing. Shows: total, average per logged day, meal count,
highest day + its total, and up to two `PeriodChange` indicators.

- A `nil` figure is **omitted or labelled unavailable**, never shown as `0` (FR-020).
- A `nil` change renders **no indicator at all** — not a dash, not `0%` (FR-006).
- Direction is shown as an SF Symbol arrow **plus** the percentage text; color is
  supplementary and never the sole carrier (FR-028).
- The card states the period it covers (FR-022).

### `DailyCaloriesChart` (widget 2)

Renders `[DailyTally]` + the average. Computes nothing.

- `BarMark` per **logged** day, `.foregroundStyle` from the reused `CalorieColorScale` step.
- **No mark for unlogged days**; `chartXScale(domain:)` pins all 7 days so the gap is a
  labelled empty slot rather than a missing axis entry (FR-012, research R5).
- `RuleMark` for the average across logged days (FR-014).
- Each day exposes an accessibility value; unlogged days explicitly announce "no data"
  (FR-028).
- The chart states the period it covers (FR-022).

---

## 3. Accessibility contract

| Identifier | Element |
|---|---|
| `screen.progress` | tab root — **reused** from `ProgressPlaceholderView` so existing selectors keep working |
| `progress.empty` | whole-tab empty state |
| `progress.week.card` | weekly summary card |
| `progress.week.total` | total figure |
| `progress.week.average` | average-per-logged-day figure |
| `progress.week.meals` | meal count |
| `progress.week.highest` | highest day |
| `progress.week.noData` | "nothing logged this week" message |
| `progress.chart` | chart container |

**Requirements**

- Chart data must be reachable by VoiceOver per day, including unlogged days, so meaning is
  never carried by bar height or color alone (FR-028).
- No fixed heights or `lineLimit` that would clip at large Dynamic Type sizes.
- Change direction is announced as words ("up 12 percent"), not as a color.

---

## 4. Localization contract — `Kalorias/Resources/Localizable.xcstrings`

All keys need `en` + `es` (Principle VI). Percentages and numbers are formatted through
locale-aware formatting, not string concatenation.

| Key | `en` | `es` |
|---|---|---|
| `progress.title` | `Progress` | `Progreso` |
| `progress.empty.title` | `Nothing logged yet` | `Aún no hay registros` |
| `progress.empty.message` | `Analyze a meal and your stats will appear here.` | `Analiza una comida y tus estadísticas aparecerán aquí.` |
| `progress.week.title` | `This week` | `Esta semana` |
| `progress.week.noData` | `Nothing logged this week` | `Nada registrado esta semana` |
| `progress.week.total` | `Calories logged` | `Calorías registradas` |
| `progress.week.average` | `Average per logged day` | `Media por día registrado` |
| `progress.week.meals` | `Meals logged` | `Comidas registradas` |
| `progress.week.highest` | `Highest day` | `Día más alto` |
| `progress.change.up` | `Up %@ vs last week` | `Sube %@ vs semana anterior` |
| `progress.change.down` | `Down %@ vs last week` | `Baja %@ vs semana anterior` |
| `progress.change.unchanged` | `Same as last week` | `Igual que la semana anterior` |
| `progress.chart.title` | `Last 7 days` | `Últimos 7 días` |
| `progress.chart.average` | `Average` | `Media` |
| `progress.chart.noData` | `No data` | `Sin datos` |
| `progress.unavailable` | `—` | `—` |

**Wording rule (FR-021)**: every label says *logged* / *registradas*. No key may describe a
figure as the user's intake, consumption, or total eaten — logging is partial by nature and
the copy must not overclaim.

---

## 5. Design-system contract

**No new color token.** The chart reuses `success` / `caution` / `warning` / `danger` through
`CalorieColorScale`, and text uses `textPrimary` / `textSecondary`. The constitution's token
table therefore needs no change (unlike feature 004).

**New shared helper**: `Kalorias/DesignSystem/GlassCard.swift` wraps Apple's native
`.glassEffect(.regular, in: .rect(cornerRadius:))` so both widget cards — and every future
card — go through one place, as Principle III requires. See research R9 for why this is being
introduced now and why migrating the two existing ad-hoc call sites is kept as separate,
optional cleanup.
