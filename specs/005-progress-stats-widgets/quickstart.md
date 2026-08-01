# Quickstart & Validation: Progress Tab — Weekly Summary & 7-Day Calorie Chart

**Feature**: `005-progress-stats-widgets` | **Date**: 2026-07-26

How to build, test and prove this feature works. Signatures live in
[contracts/ui-contracts.md](./contracts/ui-contracts.md); shapes and invariants in
[data-model.md](./data-model.md); the reasoning in [research.md](./research.md).

---

## Prerequisites

- Xcode 26.6+ (project targets **iOS 26.5**, Swift 6, `SWIFT_STRICT_CONCURRENCY = complete`)
- Scheme `Kalorias`, targets `Kalorias` + `KaloriasTests`
- No new packages. Swift Charts ships in the SDK — `import Charts` needs no linking step.

New `.swift` files under `Kalorias/` are picked up automatically (that group is
filesystem-synchronized). **`KaloriasTests/` is not** — it uses explicit file references, so
each new test file must be registered in `project.pbxproj` (PBXBuildFile +
PBXFileReference + the group's `children` + the target's `Sources` phase) or it will silently
not run. **A test count that does not grow is the symptom** — this cost a debugging cycle in
feature 004.

---

## Build

```bash
xcodebuild -project Kalorias.xcodeproj -scheme Kalorias \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build 2>&1 | tail -20
```

**Expected**: `BUILD SUCCEEDED`, **zero warnings** (Principle I).

> If the simulator fails to launch with `FBSOpenApplicationServiceErrorDomain ... Busy`,
> boot it first: `xcrun simctl boot "iPhone 17 Pro Max" && xcrun simctl bootstatus "iPhone 17 Pro Max" -b`.

## Test

```bash
xcodebuild -project Kalorias.xcodeproj -scheme Kalorias \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  test 2>&1 | tail -30
```

**Expected**: `TEST SUCCEEDED`. The **79 tests** from features 001–004 must all still pass
(this feature writes nothing, so any regression there is a real defect), plus the three new
suites.

```bash
# just the new suites while iterating
xcodebuild -project Kalorias.xcodeproj -scheme Kalorias \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:KaloriasTests/DailyTallyTests \
  -only-testing:KaloriasTests/WeekSummaryTests \
  -only-testing:KaloriasTests/PeriodChangeTests \
  test 2>&1 | tail -20
```

> UI tests stay **off** (Principle II). Do not author or run XCUITest here.

---

## Required unit coverage

This feature is almost entirely arithmetic, so the tests *are* the deliverable. Every test
injects its own `Calendar` and `now` — no test may read `Calendar.current` or `Date()`.

### `PeriodChangeTests` — the zero-baseline guard

| Case | Asserts | Contract |
|---|---|---|
| `baseline == 0`, current > 0 | **`nil`** — not `∞`, `NaN` or `100%` | C1 / FR-006 |
| `baseline` negative (defensive) | `nil`, no crash | C1 |
| `current == baseline` | `.unchanged`, `percent == 0` | C2 / FR-007 |
| `current > baseline` (e.g. 1120 vs 1000) | `.up`, `percent == 12` | C3 / FR-004 |
| `current < baseline` (e.g. 880 vs 1000) | `.down`, `percent == 12` | C3 |
| Both zero | `nil` | C1 |
| Huge ratio (2000 vs 10) | `.up`, large `percent`, no overflow | C4 |
| Any result | `percent >= 0` (sign lives in `direction`) | C5 |

### `DailyTallyTests` — "no log" is not zero

| Case | Asserts | Contract |
|---|---|---|
| Empty input, 7 days | 7 tallies, all `hasLog == false` | D7 / FR-018 |
| Meals on 3 of 7 days | 7 tallies; exactly 3 with `hasLog == true` | D1, D2 / FR-012 |
| Ordering | oldest → newest, last tally is `endingOn`'s day | D1 / FR-010 |
| Two meals same day | one tally, `mealCount == 2`, total is the sum | D3 |
| **A logged meal totalling 0 kcal** | `hasLog == true`, `totalCalories == 0` — the test that catches deriving `hasLog` from the total | D4 / research R4 |
| Meal 8 days ago | excluded from a 7-day window | D5 |
| Meal earlier today, and one at 23:59 of the first window day | both included (boundary days are inclusive) | D5 |
| Non-UTC time zone | meals bucket by local day, not UTC day | D6 |
| `averageOfLoggedDays` with unlogged days present | divides by logged days only | FR-013 |
| `averageOfLoggedDays`, none logged | `nil` | FR-020 |
| `loggedBounds`, none logged | `nil` | FR-017 |
| `loggedBounds`, one logged day | `lowest == highest` (feeds green via the reused scale) | FR-017 |

### `WeekSummaryTests` — the elapsed-alignment rule

| Case | Asserts | Contract |
|---|---|---|
| Monday-first calendar, `now` = Wednesday | `elapsedDays == 3`, `weekStart` is Monday | W1, W2 |
| Sunday-first calendar, same instant | `weekStart` is Sunday, `elapsedDays` differs accordingly | W1 / FR-002 |
| `now` = week's first day | `elapsedDays == 1` | W2 |
| `now` = week's last day | `elapsedDays == 7` | W2 |
| Totals | cover the current week only; earlier weeks excluded | W3 |
| Average | divides by logged days, not by `elapsedDays` | W4 / FR-003 |
| No logged days this week | `averagePerLoggedDay == nil`, `hasData == false` | W4, W9 / FR-019 |
| **Partial week vs full previous week** — 3 elapsed days, previous week loaded on days 5–7 | `totalChange == nil` (baseline portion is empty), **not** a large decline | W6, W8 / FR-005 |
| **Elapsed-aligned baseline** — previous week's first 3 days total 1000, current 3 days total 1120 | `.up`, `12%` — proves the baseline is 1000, not the previous week's full total | W6 / FR-005 |
| Highest day | greatest total wins | W5 |
| **Highest-day tie** | resolves to the **most recent** tied day, deterministically across repeated calls | W5 / FR-008 |
| Empty input | `hasData == false`, `nil` average / highest / both changes | W9 |
| **DST week** (Madrid fall-back, 26 Oct 2026 week) | window edges land on 00:00; no meal is pulled in from the previous evening | W11 / research R2 |
| Determinism | two calls with identical inputs return an equal `WeekSummary` | Principle II |

---

## Manual validation

Seeding several weeks of data is the hard part. A few real captures plus moving the simulator
date works; a `#if DEBUG` seeding helper is acceptable **provided it cannot run in a release
path**.

### V1 — Weekly summary (US1)

1. With meals in this week and last week, open **Progress**.
2. **Expect**: total logged kcal, average per logged day, meal count, and the highest day
   with its total.
3. **Expect**: an up/down indicator with a percentage next to the total and the average —
   shown as an **arrow plus text**, not color alone.
4. **Expect**: the card says which period it covers.
5. Check the arithmetic by hand against the History tab for the same week — they must agree
   exactly (SC-002).

### V2 — The elapsed-alignment rule (FR-005) ⚠️ highest-value check

1. Mid-week (e.g. Wednesday), with a **full** previous week logged and a partial current week.
2. **Expect**: the comparison reflects only the previous week's **first 3 days**, so a
   normal-eating week does **not** show a large false decline.
3. This is the single easiest thing to get wrong and the hardest to notice — if the total
   always shows a big drop early in the week and recovers by Sunday, the alignment is broken.

### V3 — 7-day chart (US2)

1. **Expect**: exactly 7 day slots, ending today, each labelled.
2. **Expect**: days with no logs appear as **labelled gaps**, clearly not zero-height bars.
3. **Expect**: the average line reflects only logged days — verify by hand that adding an
   unlogged day does not move it.
4. **Expect**: lowest logged day green, highest red, middles ascending; never a higher bar
   cooler than a lower one.
5. **Expect**: the chart states its period, and it is evident this is a different window
   from the weekly card (FR-022).

### V4 — Empty and sparse states (US3)

1. Fresh install → **Progress**. **Expect** an explanatory empty state, **no** widget frames,
   **no** empty chart, **no** zeros.
2. Log exactly one meal. **Expect** both widgets render; total/average/count reflect that one
   day; highest day is that day; **no comparison** appears.
3. With data only in earlier weeks: **expect** "nothing logged this week" rather than a grid
   of zeros.
4. **Expect** no figure anywhere renders as a bare `0` where the truth is "unknown".

### V5 — Appearance, language, accessibility

1. Toggle Dark Mode → **expect** bars, average line, glass cards and text all legible; check
   the `caution` yellow in **light** mode particularly (worst case for contrast).
2. Both languages → **expect** no raw key strings on screen (`progress.week.total` visible
   means a missing catalog entry), and every figure labelled as *logged* / *registradas*.
3. Larger Text at a large size → **expect** tiles and labels wrap rather than clip.
4. VoiceOver → **expect** each day's value reachable including "no data" days, and change
   direction announced in words, not implied by color.

### V6 — Performance (FR-027, SC-007)

1. With ≥ 1,000 saved meals across 52+ weeks, open **Progress**.
2. **Expect**: widgets visible in under 1 second, no stutter switching tabs.
3. If not: profile with Instruments. The intended fix is the `@Query` predicate limited to
   the last ~14 days (research R8), not restructuring the aggregation.

---

## Definition of done

- [X] `BUILD SUCCEEDED`, zero warnings under Swift 6 strict concurrency
- [X] `TEST SUCCEEDED` — 3 new suites green **and** all 79 prior tests still passing
- [X] All three new test files registered in `project.pbxproj` (test count grew)
- [ ] V1–V6 pass by hand, in both languages and both appearances
- [ ] **V2 verified specifically** — no false mid-week decline
- [X] `ProgressPlaceholderView.swift` deleted, `RootView` renders `ProgressTabView`
- [X] Both widget cards use the shared `GlassCard` helper, not an ad-hoc `.glassEffect`
- [X] Every new string has `en` + `es`, and every figure is labelled *logged*
- [X] No `Calendar.current` / `Date()` inside `ProgressStatistics` or its tests
- [X] No writes: `MealEntry`, History, and the analysis flow unchanged (FR-026)
- [X] No new color token; constitution table untouched
