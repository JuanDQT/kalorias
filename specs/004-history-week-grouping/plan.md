# Implementation Plan: History Weekly Grouping & Calorie Color Scale

**Branch**: `004-history-week-grouping` | **Date**: 2026-07-26 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/004-history-week-grouping/spec.md`

## Summary

Restructure the History tab's flat, newest-first list (feature 003) into
calendar-week sections with headers — "Semana actual" / "Semana anterior" / a
`1 Febrero - 7 Febrero` date range — give every row a `Vie. 25 Jul, 16:40`
timestamp, and color each row's calorie number on a green → yellow → orange → red
scale computed **per week group** from that group's own lowest and highest totals.

Technical approach (native, per constitution): three new **pure, `nonisolated`,
unit-testable types** — `MealWeekGrouping` (groups by `Calendar.weekOfYear`,
honoring the device's `firstWeekday`), `CalorieColorScale` (value → one of four
ordered steps), and `MealDateFormatting` (locale-composed date strings) — plus a
`List` + `Section` rewrite of `HistoryView` and small edits to `MealRowView`.
`MealEntry`, the SwiftData store, `MealDetailsView`, and the save path are
**untouched**: this is a presentation-only change.

Two research findings shape the design (see [research.md](./research.md)):

1. **No stock formatter produces the requested strings.** Verified against
   Foundation's own symbols: `es_ES` gives `sáb, 25 jul` and `1 de febrero`;
   `en_US` reverses to `February 1`. Both target formats are therefore composed
   from locale symbols and arranged by a **localized pattern string** in
   `Localizable.xcstrings`, so translators own the word order while day/month/
   weekday names and the 12/24-hour time still come from the device.
2. **The palette has no yellow.** `success` (green), `warning` (orange) and
   `danger` (red) cover three of the four steps; a new `caution` token is added to
   the palette *and* to the constitution's token table (v1.1.0 → v1.1.1).

## Technical Context

**Language/Version**: Swift 6 (strict concurrency `complete`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`, default MainActor isolation).

**Primary Dependencies**: SwiftUI (`List`/`Section`/`ForEach`), Foundation
(`Calendar`, `DateInterval`, `DateFormatter` symbols, `Locale`), SwiftData
(`@Query`, read-only here). Reuses feature 003's `MealEntry`, `MealRowView`,
`ImageStore`, `Router`. No new dependencies, no network.

**Storage**: None added. Reads the existing `MealEntry.capturedAt` and
`MealEntry.totalCalories`; **no schema change, no migration**.

**Testing**: XCTest in `KaloriasTests`. All new logic is pure and takes its
`Calendar`, `Locale`, `TimeZone` and "now" as **parameters**, so tests are
deterministic and locale-independent (constitution Principle II) — no in-memory
`ModelContainer` needed for the new types. UI tests OFF by default.

**Target Platform**: iOS 26.5+.

**Project Type**: Native iOS app (single SwiftUI target, filesystem-synchronized
groups — new files under `Kalorias/` are picked up without editing the pbxproj).

**Performance Goals**: History list visible < 1s and smooth scrolling with ≥ 1,000
entries across 52+ weeks (SC-005). Grouping is O(n log n) once per data change;
date strings are formatted **once at group-build time**, never per row body.

**Constraints**: `Calendar.current`/`Date()` read only at the view boundary (never
inside pure logic); all four scale colors from `AppColor` tokens; new `caution`
token must stay legible in light *and* dark; EN+ES for every new string; no change
to saved data or the details screen (FR-018).

**Scale/Scope**: 3 new pure types + 1 new header view + 1 new color token; 2
modified views; 3 new test files. No changes to persistence, navigation, or the
analysis pipeline.

## Constitution Check

*GATE: evaluated against Kalorias Constitution v1.1.0. Re-checked after Phase 1 — see below.*

| Principle | Gate | Status |
|-----------|------|--------|
| I. Code Quality | Grouping, color-step selection, and date composition live in dedicated testable types, never inline in view bodies; no force-unwrap (`dateInterval(of:for:)` returns an optional and is handled by a documented fallback, not `!`). | ✅ `MealWeekGrouping`, `CalorieColorScale`, `MealDateFormatting`. |
| II. Testing (NON-NEG) | Unit tests for each pure type covering normal, empty/zero, and boundary cases: empty history, single-entry group, all-totals-equal, min/max endpoints, week rollover, Sunday-first vs Monday-first locales, year-spanning weeks. Written alongside implementation. UI tests off. | ✅ 3 new test files, see [quickstart.md](./quickstart.md). |
| III. UX Consistency | HIG-standard sectioned `List` with plain headers; existing Liquid Glass/row treatment unchanged; all colors from `AppColor`; no new destructive action; Dynamic Type + VoiceOver (headers announced as section titles) + a11y identifiers. | ✅ `WeekSectionHeaderView` + existing `MealRowView`. |
| IV. Performance | Grouping O(n log n) once per `@Query` change, not per row; date strings precomputed at group-build; formatter symbols cached per locale; no main-thread blocking work added. | ✅ see Performance Goals. |
| V. Architecture (NON-NEG) | Swift 6 strict; MV — the view derives sections from `@Query` state via pure functions; no new ViewModel; no navigation change (Router untouched). Pure types are `nonisolated` and `Sendable`-safe. | ✅ |
| VI. Localization & Appearance (NON-NEG) | Every new string in `Localizable.xcstrings` with EN+ES, including the two composition patterns; new `caution` token ships light + dark variants; all four scale colors verified in both appearances. | ✅ 6 new keys + 1 new colorset. |
| Tech Constraints | Foundation + SwiftUI only; no third-party dependency; no network; nothing leaves the device. | ✅ |
| Design System (governance) | Adding the `caution` token **requires updating the constitution's token table in the same change**, per the "Design System & Color Tokens" section. | ⚠️ **Required action**, tracked below — not a violation. |

**Result**: All principle gates pass. One governance obligation (constitution
token-table update + PATCH version bump 1.1.0 → 1.1.1) is carried into the task
list rather than deferred. Complexity Tracking is empty — no violations to justify.

## Project Structure

### Documentation (this feature)

```text
specs/004-history-week-grouping/
├── plan.md                  # This file
├── research.md              # Phase 0 — 6 resolved decisions
├── data-model.md            # Phase 1 — presentation types (no persistence change)
├── quickstart.md            # Phase 1 — build/test/validate guide
├── contracts/
│   └── ui-contracts.md      # pure-type APIs, screen states, a11y ids, l10n keys
├── checklists/requirements.md
└── tasks.md                 # /speckit-tasks (not created here)
```

### Source Code (repository root)

```text
Kalorias/
├── DesignSystem/
│   └── AppColor.swift                        # MODIFIED: + `caution` token (yellow step)
├── Assets.xcassets/Palette/
│   └── Caution.colorset/Contents.json        # NEW: light + dark yellow
├── Features/History/
│   ├── MealWeekGrouping.swift                # NEW: pure week grouping + WeekHeaderLabel
│   ├── CalorieColorScale.swift               # NEW: pure value → CalorieColorStep
│   ├── MealDateFormatting.swift              # NEW: pure locale-composed date strings
│   ├── WeekSectionHeaderView.swift           # NEW: label → localized header text
│   ├── HistoryView.swift                     # MODIFIED: sectioned List instead of flat List
│   ├── MealRowView.swift                     # MODIFIED: takes formatted date + colorStep
│   ├── MealEntry.swift                       # MODIFIED: + WeekGroupable conformance (no schema change)
│   ├── MealDetailsView.swift                 # UNCHANGED (FR-018)
│   ├── MealHistoryRepository.swift           # UNCHANGED
│   ├── ImageStore.swift                      # UNCHANGED
│   └── MealTitle.swift                       # UNCHANGED
└── Resources/
    └── Localizable.xcstrings                 # MODIFIED: 6 new keys (EN+ES)

KaloriasTests/                                # add
├── MealWeekGroupingTests.swift
├── CalorieColorScaleTests.swift
└── MealDateFormattingTests.swift

.specify/memory/constitution.md               # MODIFIED: + `caution` row, v1.1.0 → v1.1.1
```

**Structure Decision**: The feature stays inside the existing
`Features/History/` module — it is a presentation change to one screen. The three
new files are **pure `nonisolated` types with zero SwiftUI imports** (grouping and
scale logic return domain enums, not `Color`), so they are unit-testable in
isolation and the SwiftUI layer only maps their output to tokens and localized
text. `MealEntry` gains a `WeekGroupable` conformance rather than the grouping
code depending on SwiftData, which keeps the grouping tests free of a
`ModelContainer` and satisfies the determinism rule in Principle II.

### Post-Design Constitution Re-Check

Re-evaluated after the Phase 1 artifacts were written:

- **No new violations introduced.** The design added no ViewModel layer, no
  third-party dependency, no network call, and no persistence change.
- **Principles I/II strengthened by design**: making the grouping generic over
  `WeekGroupable` (rather than over `MealEntry`) removed SwiftData from the test
  path entirely, so all three new types test as pure functions.
- **Principle IV verified by design**: formatting moved out of the row body into
  group construction, so a 1,000-entry / 52-week history formats each string once
  instead of on every row re-render.
- **The one governance obligation stands**: the `caution` token must land in the
  constitution's table in the same change as the colorset. Gate remains ⚠️
  "required action", and it is an explicit task, not an assumption.

## Complexity Tracking

> No constitution violations. Section intentionally empty.
