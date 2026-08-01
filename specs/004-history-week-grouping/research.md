# Phase 0 Research: History Weekly Grouping & Calorie Color Scale

**Feature**: `004-history-week-grouping` | **Date**: 2026-07-26

All Technical Context unknowns are resolved below. No `NEEDS CLARIFICATION`
remains.

---

## R1 — How to determine week boundaries that follow the device's region (FR-002)

**Decision**: Use `Calendar.current.dateInterval(of: .weekOfYear, for: date)`.
The interval's `start` is the group key; the displayed end is `start + 6 days`
(the interval's own `end` is exclusive — it is midnight of the *next* week's first
day, which would render an off-by-one header like "2 Febrero - 8 Febrero").

The pure API takes the `Calendar` as a **parameter** with `Calendar.current` passed
only at the view boundary, so tests can inject a fixed calendar.

**Rationale**: `Calendar.firstWeekday` is already region-driven — verified:
`es_ES` → `2` (Monday), `en_US` → `1` (Sunday), `en_GB` → `2` (Monday). Using
`.weekOfYear` gets Monday–Sunday and Sunday–Saturday for free, exactly matching the
user's "(lun-dom o para americano dom sabado)". No custom arithmetic and no in-app
setting is needed.

**Alternatives considered**:
- *Manual `weekday` arithmetic* — rejected: reimplements what `Calendar` already
  does correctly, and gets DST and year boundaries wrong.
- *`.weekOfMonth`* — rejected: resets at month boundaries, so a week straddling
  two months would split into two groups.
- *An in-app "week starts on" setting* — rejected: out of scope per the spec's
  Assumptions; the device setting is the single source of truth.

**Force-unwrap note**: `dateInterval(of:for:)` returns `DateInterval?`. Per
Principle I it must not be `!`-unwrapped. Entries whose interval cannot be computed
fall back to `startOfDay` as their key, with a comment documenting that this is
unreachable for a Gregorian calendar and exists only to avoid the force-unwrap.

---

## R2 — Producing the `Vie. 25 Jul, 16:40` row timestamp (FR-010)

**Decision**: Compose the string from locale symbols and arrange it with a
**localized pattern key** (`history.date.rowFormat`) taking four positional
arguments: weekday, day, month, time.

- weekday: `DateFormatter.shortWeekdaySymbols[weekdayIndex]`, first letter
  capitalized via `capitalized(with: locale)`, then a `.` appended
- day: `calendar.component(.day, from:)`, plain integer
- month: `DateFormatter.shortMonthSymbols[monthIndex]`, first letter capitalized
- time: a `DateFormatter` with `setLocalizedDateFormatFromTemplate("jmm")` — the
  `j` skeleton is what makes the device's 12/24-hour preference apply

**Rationale**: No stock formatter emits the requested shape. Measured output for
Sat 25 Jul 2026 16:40:

| Approach | `es_ES` | `en_US` |
|---|---|---|
| `.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())` | `sáb, 25 jul 2026, 16:40` | `Sat, Jul 25, 2026 at 4:40 PM` |
| `setLocalizedDateFormatFromTemplate("EEE d MMM")` | `sáb, 25 jul` | `Sat, Jul 25` |
| **Target** | `Sáb. 25 Jul, 16:40` | — |

Spanish abbreviations are lowercase and carry no period in modern CLDR, and
English US reorders month-before-day. Composition is therefore unavoidable if the
user's format is to be honored. Routing the *arrangement* through the string
catalog keeps Principle VI satisfied (no hardcoded user-facing text, translators
control word order) while the *names* still come from the device locale, so a
French or German device is not left with Spanish word order.

**Alternatives considered**:
- *A hardcoded `dateFormat = "EEE. d MMM, HH:mm"`* — rejected twice over: it
  hardcodes 24-hour time (breaking FR-010's 12/24-hour clause on US devices), and
  a fixed `dateFormat` string is exactly the kind of unlocalized literal Principle
  VI forbids.
- *Accept the native `sáb, 25 jul 2026, 16:40`* — rejected: does not meet FR-010,
  and the year is noise in a list already grouped by week.
- *`Date.FormatStyle` with `.locale(...)` overrides* — rejected: the ordering and
  the `, ` / ` at ` separators are baked into CLDR patterns and are not
  overridable without dropping to a raw pattern anyway.

**Capitalization**: use `capitalized(with: locale)` on the first character only —
not `.capitalized` on the whole string, which would turn a multi-word symbol into
title case incorrectly in some locales.

---

## R3 — Producing the `1 Febrero - 7 Febrero` week-range header (FR-005, FR-006)

**Decision**: Same composition strategy, with a `history.week.dayMonth` pattern for
one endpoint (day + full month, `standaloneMonthSymbols` capitalized) and
`history.week.range` joining the two endpoints. When an endpoint's year differs
from the current year, that endpoint uses `history.week.dayMonthYear` instead.

**Rationale**: The measured locale templates are again wrong for the target:
`dMMMM` on `es_ES` yields `1 de febrero` (note the "de", and lowercase) and on
`en_US` yields `February 1`. The user's example is `1 Febrero - 7 Febrero` — no
"de", capitalized, day-first. `standaloneMonthSymbols` gives the nominative form
(`febrero`) rather than the genitive-style form embedded in date patterns, which
is the correct symbol set when a month name stands next to a bare day number.

Per-endpoint year handling covers both edge cases in one rule: an ordinary old week
renders `1 Febrero 2025 - 7 Febrero 2025`, and a week straddling New Year renders
`29 Diciembre 2025 - 4 Enero 2026` without special-casing.

**Alternatives considered**:
- *`DateIntervalFormatter`* — rejected: it produces `1–7 de febrero de 2026`,
  collapsing the repeated month and inserting "de"; the collapse is arguably nicer
  but is not the requested format and cannot be tuned.
- *Year appended once after the range* — rejected: silently wrong for
  year-straddling weeks.
- *Abbreviated month in headers* — rejected: the user's example uses the full name
  (`Febrero`), and headers have room the row timestamp does not.

---

## R4 — Mapping a calorie total to one of four colors within its group (FR-011…FR-014)

**Decision**: A pure `CalorieColorScale.step(for:lowest:highest:)` returning an
ordered `CalorieColorStep` enum (`.low`, `.moderate`, `.high`, `.veryHigh`):

```
if highest <= lowest  → .low
position = (value - lowest) / (highest - lowest)     // 0.0 ... 1.0
index    = min(3, Int(position * 4))                 // 4 equal bands
```

The view maps steps to tokens: `.low → success`, `.moderate → caution`,
`.high → warning`, `.veryHigh → danger`.

**Rationale**:
- **Monotonic by construction** (FR-013): `position` is non-decreasing in `value`,
  and both `Int(_:)` truncation and `min` preserve that ordering.
- **Endpoints exact** (FR-011): `value == lowest` → `position 0` → `.low` (green);
  `value == highest` → `position 1.0` → raw index `4`, clamped to `3` → `.veryHigh`
  (red). The clamp is the *only* thing making the top endpoint land on red, so it
  gets a dedicated test.
- **Degenerate groups** (FR-014): the `highest <= lowest` guard covers both the
  single-entry group and the all-equal group, and also removes the division-by-zero
  risk. Returning `.low` matches the spec's "green" decision.
- Returning an enum rather than a `Color` keeps SwiftUI out of the tested logic
  (Principle I) and keeps the token mapping in one place in the view layer.

**Alternatives considered**:
- *Rank-based buckets (quartiles by position in the sorted list)* — rejected: with
  3 meals at 500/510/2000 kcal it would paint 510 as orange, misrepresenting a
  cluster; value-proportional banding reflects the actual spread.
- *Continuous gradient interpolation* — rejected: the spec's Assumptions fix four
  discrete steps, and interpolated colors cannot be token-sourced (Principle III).
- *Absolute kcal thresholds* — rejected: contradicts the spec's explicit
  per-group relative decision. Flagged in the spec's Assumptions as the alternative
  to revisit if the relative scale proves confusing.

---

## R5 — Sourcing a yellow that the palette does not have (FR-015)

**Decision**: Add a `caution` token (light `#B8860B`, dark `#F2D24B`) to
`Assets.xcassets/Palette/Caution.colorset`, expose it in `AppColor`, and add its
row to the constitution's token table in the same change (v1.1.0 → v1.1.1, PATCH —
a palette addition, not a principle change).

**Rationale**: The existing status trio maps cleanly onto three of the four steps
(`success` green, `warning` orange, `danger` red) but there is no yellow. The
constitution forbids inlining a literal and mandates "create the color set first,
then expose it in `AppColor`".

Hex choice is constrained by the token being used as **text**, not as a fill: a
bright yellow fails contrast on the light `surfacePrimary` (`#F7F8F6`).
`#B8860B` is a dark goldenrod at roughly 3.4:1 on that background — clearing the
3:1 bar for the bold `.headline`-sized calorie number — while staying visually
distinct from `warning` (`#E8890C`, a more saturated orange). Dark mode inverts the
constraint, so `#F2D24B` is a bright yellow against `#0E120F`.

**Alternatives considered**:
- *Reuse `macroCarbs` (`#F5A623`)* — rejected: it is semantically the carbohydrate
  accent; reusing it inside the same row that already shows a carbs dot would be
  genuinely ambiguous.
- *Reuse `brandSecondary` (`#FF8A0A`)* — rejected: near-identical to `warning`, so
  the middle two steps would be indistinguishable.
- *A pure yellow such as `#F5C518`* — rejected: ~1.9:1 on the light surface, fails
  as text.

**Open for design tuning**: the exact hexes are a starting point and may be
adjusted during implementation, provided both appearances are re-verified at ≥ 3:1
and the constitution table is updated to match.

---

## R6 — Where grouping runs, and keeping the list at 60fps (FR-017, SC-005)

**Decision**: `HistoryView` keeps its `@Query(sort: \MealEntry.capturedAt, order:
.reverse)` and derives sections from it through `MealWeekGrouping`. Each
`MealWeekGroup` is built **with its rows' display strings and color steps already
computed**, so `MealRowView` receives a `String` and a `CalorieColorStep` and does
no date or scale work in its body. `DateFormatter` instances are created once per
grouping pass (not per row) and reused across all entries.

**Rationale**: `DateFormatter` construction is the classic cost here — creating one
per row per body evaluation is what breaks 60fps at 1,000 rows. Formatting once at
group-build makes the cost O(n) per data change instead of O(n × re-renders).
Grouping itself is a single pass into a dictionary plus a sort of the (≤ 52-ish)
group keys; the entries arrive already sorted newest-first from `@Query`, so
within-group order is preserved for free by appending in iteration order.

Deriving sections as a computed property (rather than mirroring into `@State`)
keeps the MV pattern intact — the view stays a pure function of `@Query` state —
and SwiftUI only re-evaluates the body when the query results actually change.

**Alternatives considered**:
- *`SectionedFetchRequest`-style grouping in the query* — rejected: SwiftData has
  no sectioned-query equivalent, and the section identity here ("current"/
  "previous"/range) is relative to *now*, not a stored property.
- *Grouping on a background actor* — rejected as premature: a single pass over
  1,000 small structs is sub-millisecond, and hopping actors would add a loading
  state to a screen that currently has none (a UX regression under Principle III).
- *Caching groups in `@State` with `.onChange(of: entries)`* — rejected: adds a
  second source of truth for no measured gain; revisit only if profiling shows the
  computed property re-running unnecessarily.

**Week rollover**: because the "current"/"previous" labels are computed from a
`now` passed in at body evaluation, the labels re-resolve whenever the view is
re-presented — satisfying the spec's rollover edge case without a timer.
