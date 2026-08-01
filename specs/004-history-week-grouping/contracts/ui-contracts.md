# Phase 1 Contracts: History Weekly Grouping & Calorie Color Scale

**Feature**: `004-history-week-grouping` | **Date**: 2026-07-26

The app exposes no network or CLI surface, so the contracts that matter are the
**pure-type APIs** (the seam the unit tests bind to), the **screen states**, the
**accessibility identifiers** (the seam future UI tests bind to), and the
**localization keys**. Signatures below are the contract; bodies belong to
implementation.

---

## 1. Pure logic APIs

### 1.1 `MealWeekGrouping` — `Kalorias/Features/History/MealWeekGrouping.swift`

```swift
protocol WeekGroupable {
    var capturedAt: Date { get }
    var totalCalories: Int { get }
}

struct MealWeekGroup<Item: WeekGroupable>: Identifiable {
    let id: Date              // == weekStart
    let weekStart: Date
    let weekEnd: Date         // inclusive: weekStart + 6 days
    let label: WeekHeaderLabel
    let items: [Item]         // non-empty, newest-first
    let lowestCalories: Int
    let highestCalories: Int
}

enum WeekHeaderLabel: Equatable {
    case currentWeek
    case previousWeek
    case dateRange(start: Date, end: Date)
}

nonisolated enum MealWeekGrouping {
    /// Partition `items` into week groups, newest week first.
    /// - Parameters:
    ///   - items: entries in any order (production passes them newest-first).
    ///   - calendar: supplies `firstWeekday`; `Calendar.current` at the view boundary.
    ///   - now: reference instant for the current/previous labels.
    static func groups<Item: WeekGroupable>(
        from items: [Item],
        calendar: Calendar,
        now: Date
    ) -> [MealWeekGroup<Item>]
}
```

**Contract**

| # | Guarantee | Requirement |
|---|---|---|
| G1 | `items.isEmpty` → returns `[]` | FR-009 |
| G2 | Every input item appears in exactly one returned group | SC-001 |
| G3 | No returned group has empty `items` | FR-008 |
| G4 | Groups ordered by `weekStart` descending | FR-007 |
| G5 | Within a group, items ordered by `capturedAt` descending | FR-007 |
| G6 | Two items in the same region-week share a group; items either side of the region's week boundary do not | FR-001, FR-002 |
| G7 | The group containing `now` is labelled `.currentWeek` | FR-003 |
| G8 | The group containing `now − 7 days` is labelled `.previousWeek` | FR-004 |
| G9 | All older groups are labelled `.dateRange(weekStart, weekEnd)` | FR-005 |
| G10 | `weekEnd` is the week's **last day**, not the exclusive interval end | FR-005 |
| G11 | `lowestCalories`/`highestCalories` are the min/max over `items` | FR-011 |
| G12 | Never force-unwraps; a nil `dateInterval` falls back to `startOfDay` | Principle I |

---

### 1.2 `CalorieColorScale` — `Kalorias/Features/History/CalorieColorScale.swift`

```swift
enum CalorieColorStep: Int, Comparable, CaseIterable {
    case low = 0, moderate = 1, high = 2, veryHigh = 3
}

nonisolated enum CalorieColorScale {
    /// Which of four ordered steps `value` falls into, between a group's bounds.
    static func step(for value: Int, lowest: Int, highest: Int) -> CalorieColorStep
}
```

**Contract**

| # | Guarantee | Requirement |
|---|---|---|
| C1 | `highest <= lowest` → `.low` (covers single-item and all-equal groups) | FR-014 |
| C2 | `value == lowest` → `.low` | FR-011 |
| C3 | `value == highest` (with `highest > lowest`) → `.veryHigh` | FR-011 |
| C4 | `a <= b` ⟹ `step(a) <= step(b)` for the same bounds | FR-013 |
| C5 | Bounds split into 4 equal bands over `[lowest, highest]` | Assumptions |
| C6 | Never divides by zero | Principle I |
| C7 | Returns a domain enum, never a `Color` — no SwiftUI import | Principle I |

**Token mapping** (view layer only, `MealRowView`):
`.low → AppColor.success` · `.moderate → AppColor.caution` ·
`.high → AppColor.warning` · `.veryHigh → AppColor.danger`

---

### 1.3 `MealDateFormatting` — `Kalorias/Features/History/MealDateFormatting.swift`

```swift
nonisolated struct MealDateFormatting {
    init(locale: Locale, calendar: Calendar, timeZone: TimeZone)

    /// "Vie. 25 Jul, 16:40" — abbreviated weekday, day, abbreviated month, time.
    func rowTimestamp(for date: Date) -> String

    /// "1 Febrero - 7 Febrero", with per-endpoint year when it isn't `referenceYear`.
    func weekRange(start: Date, end: Date, referenceYear: Int) -> String
}
```

Instantiated **once per grouping pass** and reused for every entry — see research
R6. Formatter symbols are read from `Locale`/`DateFormatter`, never hardcoded.

**Contract**

| # | Guarantee | Requirement |
|---|---|---|
| D1 | Weekday and month names come from the locale's symbols, not literals | FR-016 |
| D2 | Weekday/month first letter capitalized via `capitalized(with: locale)` | FR-010 |
| D3 | Time honors the device 12/24-hour setting (`jmm` skeleton) | FR-010 |
| D4 | Arrangement comes from a localized pattern key, not a Swift literal | Principle VI |
| D5 | Rendered in the supplied `timeZone` | FR-010 |
| D6 | Range endpoints in a non-reference year each carry their year | FR-006 |
| D7 | Deterministic for a fixed (locale, calendar, timeZone) triple | Principle II |

---

## 2. Screen state contract — `HistoryView`

| State | Condition | Rendering |
|---|---|---|
| Empty | `@Query` returns no entries | existing `ContentUnavailableView` — **no headers** (FR-009) |
| Grouped | ≥ 1 entry | `List` of `Section`s, one per `MealWeekGroup`, newest week first |

Structural change from feature 003: `List(entries) { … }` becomes
`List { ForEach(groups) { group in Section { … } header: { WeekSectionHeaderView(label:) } } }`.
`.listStyle(.plain)`, the `Button` + `.buttonStyle(.plain)` row wrapper, the
`.listRowBackground(Color.clear)`, the `navigationTitle`, and the
`navigationDestination` are all **unchanged** — tapping still routes through
`router.openMeal(entry)` (FR-018).

`MealRowView`'s signature changes from `(entry:imageStore:)` to
`(display:imageStore:)` where `display` is `MealRowDisplay`; its layout, thumbnail
loading, and macro summary are unchanged. Only two things differ visually: the
date text now uses `display.formattedDate` instead of the inline
`.dateTime.day().month().hour().minute()` format, and the calorie number's
`.foregroundStyle` switches from the fixed `AppColor.brandPrimary` to the
step-mapped token.

---

## 3. Accessibility contract

Existing identifiers are **preserved** (`history.list`, `history.empty`,
`history.row`, `history.row.title`, `history.row.date`, `history.row.total`).

| New identifier | Element | Purpose |
|---|---|---|
| `history.week.header` | week section header text | assert header presence/label in future UI tests |

**Requirements**

- Headers are real `Section` headers so VoiceOver announces them as section
  context for the rows beneath (FR-019).
- Header text supports Dynamic Type — no fixed frame heights, no `.lineLimit(1)`
  that would clip an accessibility text size (FR-019).
- The calorie color is **decorative**: the number itself is always present as text,
  so the information is never color-only. The row's combined accessibility label
  keeps reading the numeric total.

---

## 4. Localization contract — `Kalorias/Resources/Localizable.xcstrings`

Six new keys, each with `en` + `es` (Principle VI). Existing `history.*` keys are
untouched.

| Key | `en` | `es` |
|---|---|---|
| `history.week.current` | `This week` | `Semana actual` |
| `history.week.previous` | `Last week` | `Semana anterior` |
| `history.week.range` | `%1$@ - %2$@` | `%1$@ - %2$@` |
| `history.week.dayMonth` | `%1$@ %2$@` | `%1$@ %2$@` |
| `history.week.dayMonthYear` | `%1$@ %2$@ %3$@` | `%1$@ %2$@ %3$@` |
| `history.date.rowFormat` | `%1$@ %2$@ %3$@, %4$@` | `%1$@ %2$@ %3$@, %4$@` |

**Positional argument meanings** — must be documented as a comment on each key so
translators can safely reorder:

- `history.week.dayMonth` — `%1$@` day number, `%2$@` full month name
  → `1 Febrero`
- `history.week.dayMonthYear` — `%1$@` day, `%2$@` full month, `%3$@` year
  → `1 Febrero 2025`
- `history.date.rowFormat` — `%1$@` weekday with trailing period (`Vie.`),
  `%2$@` day, `%3$@` abbreviated month, `%4$@` time → `Vie. 25 Jul, 16:40`

Positional specifiers (`%1$@`) are mandatory rather than bare `%@`, precisely so a
language that needs month-before-day can reorder without a code change.

---

## 5. Design-system contract

| Token | Colorset | Light | Dark | Role |
|---|---|---|---|---|
| `caution` | `Assets.xcassets/Palette/Caution.colorset` | `#B8860B` | `#F2D24B` | second step of the calorie scale |

The colorset follows the shape of the existing palette entries: sRGB, universal
idiom, plus a `luminosity: dark` appearance variant.

**Governance obligation**: the constitution's "Design System & Color Tokens" table
must gain the `caution` row **in the same change** as the colorset, with the
version moving 1.1.0 → 1.1.1 (PATCH — a palette addition, no principle touched).
Shipping the token without the table update violates the constitution's own
amendment rule.
