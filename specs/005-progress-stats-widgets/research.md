# Phase 0 Research: Progress Tab — Weekly Summary & 7-Day Calorie Chart

**Feature**: `005-progress-stats-widgets` | **Date**: 2026-07-26

All Technical Context unknowns are resolved below. No `NEEDS CLARIFICATION` remains.

---

## R1 — Naming: `ProgressView` is taken

**Decision**: the tab root is **`ProgressTabView`**, not `ProgressView`.

**Rationale**: `ProgressView` is a SwiftUI built-in (the spinner / progress bar). Declaring
our own would shadow it inside the module, so any future `ProgressView()` spinner in the app
would silently resolve to our dashboard instead — a confusing, hard-to-diagnose bug rather
than a compile error. The existing file is `ProgressPlaceholderView`, so no established name
is being broken.

**Alternatives considered**: `ProgressDashboardView` (fine, but longer and the app has no
other "dashboard" concept); `ProgressScreen` (inconsistent — every other view in the project
ends in `View`).

---

## R2 — Elapsed-aligned week comparison (FR-005)

**Decision**: compute the number of elapsed days in the current week, then sum the previous
week over the **same** number of days from its own start:

```
weekStart    = calendar.dateInterval(of: .weekOfYear, for: now).start
elapsedDays  = dateComponents([.day], from: weekStart, to: startOfDay(now)).day + 1   // 1...7
prevStart    = calendar.date(byAdding: .day, value: -7, to: weekStart)
prevWindow   = prevStart ..< calendar.date(byAdding: .day, value: elapsedDays, to: prevStart)
```

**Rationale**: verified against Foundation for Wednesday 22 July 2026 with a Monday-first
calendar — `weekStart` = Mon 20 Jul, `elapsedDays` = 3, previous window = Mon 13 Jul 00:00
up to (not including) Thu 16 Jul 00:00. Exactly the matching three days.

Without this alignment, a Wednesday total (3 days) is compared against a full 7-day week and
shows a ~55% "decline" no matter how much the user ate. That is not a rough edge — it is a
figure that is wrong in the direction users care about, every single week, until Sunday.

**DST safety, verified**: using `calendar.date(byAdding: .day, value: -7,)` rather than
subtracting `7 * 86400` seconds matters. Checked against Madrid's 25 October 2026 fall-back:
from `weekStart` Mon 26 Oct 00:00 the calendar arithmetic returns Mon 19 Oct **00:00**,
whereas fixed-seconds arithmetic would land on Sun 18 Oct **23:00** and pull an extra
evening's meals into the baseline.

**Alternatives considered**:
- *Compare against the previous week in full* — rejected: systematically misleading mid-week
  (above). Would need a caveat label on every screen to be honest.
- *Compare only averages, drop the total's comparison* — rejected: the spec asks for a total
  comparison, and per-logged-day averaging alone hides whether the user is logging more or
  less often.
- *Pro-rate the previous week (`prevTotal × elapsed/7`)* — rejected: invents data. If last
  week's eating was concentrated at the weekend, pro-rating misrepresents it; taking the
  actual matching days does not.

**The average needs no alignment**: "per logged day" is an intensity, not a volume, so the
current week's average is directly comparable to the previous week's full-week average.

---

## R3 — Percentage change, and the zero-baseline trap (FR-006, FR-007)

**Decision**: `PeriodChange` is optional and carries a direction enum plus a magnitude:

```
guard baseline > 0 else { return nil }          // suppressed entirely (FR-006)
percent   = (current - baseline) / baseline * 100, rounded to nearest integer
direction = current > baseline ? .up : current < baseline ? .down : .unchanged
```

**Rationale**:
- **Zero baseline returns `nil`, not a number.** `(50 - 0) / 0` is undefined; naively it
  yields `+∞` or a `NaN` that renders as "nan%". Returning `nil` and hiding the whole
  comparison is the only honest outcome, and it also covers "no previous-week data" with the
  same code path.
- **`.unchanged` is a distinct case** so the view can say "sin cambio" instead of "↑0%",
  which reads as a contradiction (FR-007).
- **Direction as an enum, not a sign.** This forces the view to render a glyph and text; a
  signed number invites conveying direction by red/green alone, which fails accessibility.

**Rounding**: to the nearest integer percent. Large magnitudes (baseline 10 → current 2000
gives +19900%) are left uncapped — capping would misreport — so the tile must be laid out to
truncate or wrap gracefully rather than assume 3 digits.

**Alternatives considered**: percentage-point difference (wrong unit here); returning `0`
for a zero baseline (silently claims "no change" when there is no basis for comparison);
returning a signed `Double` and letting the view decide (invites the color-only rendering
above).

---

## R4 — Distinguishing "no log" from a genuine zero (FR-012, FR-013)

**Decision**: `DailyTally.hasLog` is derived from **`mealCount > 0`**, never from
`totalCalories > 0`. Days with no logs are omitted from the average's divisor and from the
color scale's min/max.

**Rationale**: these are different questions, and conflating them is the single easiest way
to get this feature wrong. A day could in principle hold a logged meal whose total is 0 kcal
(the analysis sums per-food calories; nothing guarantees a positive result). Keying off the
total would then erase a real log. Keying off the count is exactly the question being asked:
"did the user record anything that day?"

**Alternatives considered**: `totalCalories > 0` (wrong, above); an `Optional<Int>` total
where `nil` means unlogged (equivalent in effect but loses the meal count the summary also
needs, and optional arithmetic spreads through every call site).

---

## R5 — Rendering an unlogged day in a bar chart (FR-012)

**Decision**: unlogged days get **no mark at all** — a labelled empty slot. The X axis is
pinned to all 7 days via `chartXScale(domain:)` so the gap is visibly intentional, and the
day's accessibility value explicitly reads "no data".

**Rationale**: the requirement is that an unlogged day must not read as zero. Every
"styled bar" option fails that:
- A ghost bar at a small fixed height reads as *a small value* — precisely the lie.
- A zero-height bar is indistinguishable from a bar that is actually zero.
- `BarMark` has no dashed-stroke API, so a "hollow dashed bar" is not expressible without
  hand-rolling the chart and giving up Charts' axes and accessibility.

A gap under a present day label is unambiguous: the slot exists, and nothing is in it. Pinning
the axis domain is what makes the difference between "intentional gap" and "chart looks
broken".

**Alternatives considered**: hand-rolled `RoundedRectangle` bars (full styling control, but
re-implements axis layout, Dynamic Type behaviour and accessibility that Charts provides);
plotting unlogged days at the average height in a faint style (invents a value).

---

## R6 — Swift Charts vs. hand-rolled bars

**Decision**: **Swift Charts** — `BarMark` per logged day, `RuleMark` for the average,
`chartXScale(domain:)` for the fixed 7-day axis.

**Rationale**: `Charts.framework` ships in the iOS SDK, so it is an Apple framework and needs
no third-party justification under the constitution's Technology Constraints. It brings axis
layout, Dynamic Type, dark mode and per-mark accessibility for free — all four of which are
constitution requirements this feature would otherwise have to implement by hand. Seven bars
is small enough that performance is not a factor either way.

**Bar color** comes from `AppColor` via `.foregroundStyle(...)` per mark, so Principle III
(tokenized color) holds inside the chart.

**Alternatives considered**: hand-rolled `HStack` of rectangles — genuinely simpler for 7
bars and gives total control over the unlogged-day treatment, but re-implements the four
platform behaviours above, and R5 removed the only reason to want that control.

---

## R7 — Reusing feature 004's color scale (FR-015 … FR-017)

**Decision**: call `CalorieColorScale.step(for:lowest:highest:)` unchanged, passing the min
and max of the **logged** days in the 7-day window.

**Rationale**: three requirements are satisfied with no new code. FR-016 (monotonic) holds
because that function is monotonic by construction; FR-017 (single logged day, or all totals
equal → green) is already its `highest <= lowest` guard, which was written and tested for
exactly this degenerate case in feature 004. The visual payoff is that a given calorie level
reads the same way in Progress as it does in History.

The scale is **relative to the window**, consistent with History's per-week relativity — so
the same caveat applies and is already documented in the spec: a week of uniformly light days
still shows one red bar.

**Alternatives considered**: a separate absolute scale for the chart — rejected: it would
make the two tabs disagree about what "red" means, and there is no goal to anchor absolute
thresholds to.

---

## R8 — Where the data comes from, and keeping the tab fast (FR-027, SC-007)

**Decision**: `ProgressTabView` holds one `@Query(sort: \MealEntry.capturedAt, order:
.reverse)`; `ProgressStatistics` does its own windowing over that array and returns finished
value types. `Calendar.current` and `Date()` are read **only** in the view body and passed in
as parameters.

**Rationale**: consistent with `HistoryView` (feature 004) — `@Query` is SwiftData's reactive
read path, and deriving from it as a computed property keeps the view a pure function of
state, satisfying the MV pattern without a ViewModel. Aggregation is one O(n) pass over
~1,000 small objects, which is sub-millisecond; returning finished `WeekSummary` /
`[DailyTally]` values means no figure is recomputed per tile or per bar on redraw.

Because `now` is resolved at body evaluation, day and week rollover re-resolve when the tab
is next presented — no timer.

**Alternatives considered**:
- *A `@Query` predicate limited to the last ~14 days* — a real optimization (it would make
  the work independent of history size) but rejected as premature: the predicate needs a
  `now` fixed at init, which complicates rollover. Noted as the first thing to try if
  SC-007 ever fails.
- *Early-exit while scanning the newest-first array* — rejected: makes the pure function's
  correctness depend on its input being sorted, an invariant the type system would not
  enforce.
- *Aggregating on a background actor* — rejected: sub-millisecond work does not warrant
  adding a loading state to a screen that currently needs none (a Principle III regression).

---

## R9 — The missing shared glass helper (Principle III)

**Decision**: add `GlassCard` to `DesignSystem/` — a shared modifier/container wrapping
Apple's native `.glassEffect(.regular, in: .rect(cornerRadius:))` — and use it for both
widget cards.

**Rationale**: Principle III requires that glass surfaces "MUST be drawn through the
project's shared helpers rather than by scattering `.glassEffect(...)` ad hoc per screen, so
tinting, hit-testing, and grouping stay consistent." No such helper exists; the identical
modifier is currently duplicated in `AnalysisResultView.swift:125` and
`MealDetailsView.swift:100`. Adding two more copies for these widgets would take it to four
and make any future change to the app's glass treatment a four-site edit.

**Scope boundary**: creating the helper and using it for the *new* surfaces is in scope.
**Migrating the two existing call sites is optional cleanup**, kept as a separate flagged
task because it edits files this feature otherwise has no reason to touch — the maintainer
should decide, not have it folded in silently.

**Alternatives considered**: a `GlassCard` container view rather than a `ViewModifier`
extension — either works; the plan leaves the exact shape to implementation, requiring only
that both widgets and any future card go through one place. Doing nothing was rejected: it
knowingly deepens a violation the constitution calls out by name.
