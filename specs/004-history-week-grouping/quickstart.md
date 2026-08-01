# Quickstart & Validation: History Weekly Grouping & Calorie Color Scale

**Feature**: `004-history-week-grouping` | **Date**: 2026-07-26

How to build, test, and prove this feature works. Types and signatures live in
[contracts/ui-contracts.md](./contracts/ui-contracts.md); shapes and invariants in
[data-model.md](./data-model.md).

---

## Prerequisites

- Xcode 26.6+ (project targets **iOS 26.5**, Swift 6, `SWIFT_STRICT_CONCURRENCY = complete`)
- Scheme `Kalorias`, targets `Kalorias` + `KaloriasTests`
- No new packages, no signing changes, no network access needed

New `.swift` files under `Kalorias/` are picked up automatically (that group is
filesystem-synchronized). **`KaloriasTests/` is not** — it uses explicit file
references, so a new test file must be registered in `project.pbxproj`
(PBXBuildFile + PBXFileReference + the group's `children` + the target's `Sources`
phase) or it will silently not run. A test-count that does not grow is the symptom.

---

## Build

```bash
xcodebuild -project Kalorias.xcodeproj -scheme Kalorias \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build 2>&1 | tail -20
```

**Expected**: `BUILD SUCCEEDED` with **zero warnings** (Principle I). Any Swift 6
concurrency warning on the new `nonisolated` types is a failure, not a nit.

## Test

```bash
xcodebuild -project Kalorias.xcodeproj -scheme Kalorias \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  test 2>&1 | tail -30
```

**Expected**: `TEST SUCCEEDED`, all existing suites still green (the 003 suites in
particular — this feature must not regress persistence), plus the three new suites.

Run just the new suites while iterating:

```bash
xcodebuild -project Kalorias.xcodeproj -scheme Kalorias \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:KaloriasTests/MealWeekGroupingTests \
  -only-testing:KaloriasTests/CalorieColorScaleTests \
  -only-testing:KaloriasTests/MealDateFormattingTests \
  test 2>&1 | tail -20
```

> UI tests stay **off** (Principle II). Do not author or run XCUITest here.

---

## Required unit coverage

Every test injects its `Calendar`, `Locale`, `TimeZone`, and `now` — no test may
read `Calendar.current`, `Locale.current`, or `Date()`, or it will pass on your
machine and fail in CI (Principle II: deterministic, locale-independent).

### `MealWeekGroupingTests`

| Case | Asserts | Contract |
|---|---|---|
| Empty input | returns `[]` | G1 / FR-009 |
| Entries across 3 weeks | 3 groups, `weekStart` descending | G4 / FR-007 |
| Within a group | items stay `capturedAt` descending | G5 / FR-007 |
| Monday-first calendar (`es_ES`, `firstWeekday = 2`) | Sun 22:00 and the next Mon 08:00 land in **different** groups | G6 / FR-002 |
| Sunday-first calendar (`en_US`, `firstWeekday = 1`) | the same two instants land in **different** groups, but Sat and the preceding Sun share one | G6 / FR-002 |
| Entry on `now`'s week | label `== .currentWeek` | G7 / FR-003 |
| Entry 7 days before `now` | label `== .previousWeek` | G8 / FR-004 |
| Entry 3+ weeks back | label `== .dateRange(...)` | G9 / FR-005 |
| `.dateRange` endpoints | `weekEnd` is `weekStart + 6 days`, **not** the exclusive interval end | G10 / FR-005 |
| Gap week (entries in week 1 and week 3 only) | exactly 2 groups, none empty | G3 / FR-008 |
| Mixed totals in a group | `lowestCalories`/`highestCalories` are the true min/max | G11 / FR-011 |
| Partition | Σ `group.items.count` == input count, no duplicate ids | G2 / SC-001 |
| Week straddling New Year | one group, endpoints in different years | edge case |

### `CalorieColorScaleTests`

| Case | Asserts | Contract |
|---|---|---|
| `lowest == highest` (all equal) | `.low` | C1 / FR-014 |
| Single item (`lowest == highest == value`) | `.low` | C1 / FR-014 |
| `value == lowest`, spread group | `.low` | C2 / FR-011 |
| `value == highest`, spread group | `.veryHigh` — **the clamp test**; without `min(3, …)` this returns an out-of-range index | C3 / FR-011 |
| Ascending sweep across the range | steps are non-decreasing | C4 / FR-013 |
| Quarter boundaries (e.g. 0…400 → 0/100/200/300/400) | `.low`/`.low`/`.moderate`/`.high`/`.veryHigh` at the band edges | C5 |
| `highest < lowest` (defensive) | `.low`, no crash | C1, C6 |
| Enum ordering | `.low < .moderate < .high < .veryHigh` | C4 |

### `MealDateFormattingTests`

| Case | Asserts | Contract |
|---|---|---|
| `es_ES`, Fri 25 Jul 2025 16:40 | `"Vie. 25 Jul, 16:40"` | FR-010 |
| `en_US`, same instant | English weekday/month abbreviations, US 12-hour time (`4:40 PM`) | D3 / FR-010 |
| `en_GB`, same instant | 24-hour time (`16:40`) — proves `jmm`, not a hardcoded `HH` | D3 / FR-010 |
| Weekday/month capitalization | first letter uppercased in both languages (`sáb` → `Sáb.`) | D2 |
| Explicit `timeZone` | the same instant renders differently in two zones | D5 |
| `weekRange`, same year as reference | `"1 Febrero - 7 Febrero"` (no year, no "de") | FR-005 |
| `weekRange`, older year | both endpoints carry their year | D6 / FR-006 |
| `weekRange`, straddling New Year | each endpoint carries its **own** year | D6 / FR-006 |
| Determinism | two calls with the same inputs return identical strings | D7 |

---

## Manual validation

Seed data spanning several weeks is easiest via a few real captures plus adjusting
the simulator date; alternatively add a `#if DEBUG` seeding helper (do **not** ship
it in a release path).

### V1 — Grouping and headers (US1, FR-001…FR-009)

1. Launch, open the **History** tab with meals in this week, last week, and 2+
   weeks ago.
2. **Expect**: three headers, top to bottom — `Semana actual`, `Semana anterior`,
   then a date range like `1 Febrero - 7 Febrero`.
3. **Expect**: each header is followed only by that week's meals; meals within a
   section run newest → oldest; no header appears for a week with no meals.
4. Delete all meals (or use a fresh install) → **expect** the existing empty state
   and **no headers at all**.

### V2 — Region-driven week boundaries (FR-002)

1. Settings → General → Language & Region → **Region: United States**, relaunch.
2. **Expect**: weeks run **Sunday–Saturday** — a Sunday meal now groups with the
   days that follow it, not the ones before.
3. Switch back to **Spain** → **expect** Monday–Sunday grouping.

### V3 — Row timestamp (US2, FR-010)

1. **Expect** every row reads like `Vie. 25 Jul, 16:40` — capitalized weekday with
   a period, day, capitalized abbreviated month, comma, time.
2. Settings → General → Date & Time → toggle **24-Hour Time** off → **expect**
   `4:40 PM`. This is the check that catches a hardcoded `HH:mm`.
3. Switch the app language to English → **expect** English weekday/month
   abbreviations, still correctly arranged.

### V4 — Calorie color scale (US3, FR-011…FR-015)

1. In a week with meals spread across a wide calorie range: **expect** the lowest
   total green, the highest red, and the middle ones yellow/orange in ascending
   order — never a higher number greener than a lower one.
2. Compare two week sections: **expect** each week scaled against **its own**
   min/max — the same kcal figure may legitimately differ in color between weeks.
3. A week with exactly one meal → **expect green**, not red.
4. A week where every meal has the same total → **expect all green**.

### V5 — Appearance, language, accessibility (FR-015, FR-016, FR-019)

1. Toggle Dark Mode → **expect** all four scale colors and header text legible;
   pay particular attention to the new `caution` yellow in **light** mode, the
   worst case for contrast.
2. Both languages → **expect** no untranslated key strings (a raw
   `history.week.current` on screen means a missing catalog entry).
3. Settings → Accessibility → Display & Text Size → **Larger Text** at a large
   size → **expect** headers wrap rather than clip or truncate.
4. VoiceOver on → **expect** each section header announced as context for the rows
   beneath it, and each row still announcing its numeric calorie total (the color
   is decorative and must never be the only carrier of information).

### V6 — Performance (FR-017, SC-005)

1. With ≥ 1,000 entries across 52+ weeks, open **History**.
2. **Expect**: list visible in under 1 second, and flick-scrolling stays smooth.
3. If it does not: profile with Instruments (Time Profiler). The prime suspect is
   `DateFormatter` construction leaking into a row body — it must happen once per
   grouping pass (research R6), not per row.

---

## Definition of done

- [X] `BUILD SUCCEEDED`, zero warnings under Swift 6 strict concurrency
- [X] `TEST SUCCEEDED` — 3 new suites green, all 003 suites still green
- [ ] V1–V6 pass by hand, in **both** languages and **both** appearances
- [X] `caution` colorset added **and** the constitution's token table updated, version 1.1.0 → 1.1.1
- [X] All 6 new localization keys have `en` + `es` values with translator comments
- [X] No change to `MealEntry`'s stored schema, `MealDetailsView`, or the save path (FR-018)
- [X] No `Calendar.current` / `Locale.current` / `Date()` inside the pure types or their tests
