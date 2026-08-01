# Implementation Plan: Fix Analysis Reliability, Ingredient Thumbnails & Bottom-Bar Clearance

**Branch**: `007-fix-scroll-and-boxes` | **Date**: 2026-07-26 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/007-fix-scroll-and-boxes/spec.md`

## Summary

Both defects were reproduced and both fixes were **measured working** before this plan was written.
Nothing here is inferred.

1. **Analysis reliability (US1)** — making the per-food `box` **optional** in the response schema is
   what broke the analysis. Verified against the live service with one photo: optional → the model
   ran away to `MAX_TOKENS` and returned ~65,000 characters of malformed digits (unparseable, meal
   lost); required → clean reply with a box for every food. Fix: mark `box` **required** in the
   schema, keep the parser lenient, and add an output-token ceiling so a runaway reply fails fast.
2. **Ingredient thumbnails (US2)** — a consequence of US1. Once boxes arrive, the existing crop
   pipeline already works; verified by seeding regions through the real persistence and navigation
   path and observing correct per-quadrant crops.
3. **Bottom-bar clearance (US3)** — root-caused numerically. `NavigationStack` **consumes** the
   root's safe-area inset: the ZStack content reports `safeAreaInsets.bottom = 148`, but the pushed
   detail view reports **`0`** with a **full-screen** height of 956. Every tab wraps itself in a
   `NavigationStack`, so a root-level inset can never reach any scrolling content. Fix:
   `.contentMargins(.bottom, …, for: .scrollContent)` **inside** each scroll container, from one
   shared constant. Verified: after a real programmatic scroll the last row is fully visible above
   the bar, where before it was unreachable.

## Technical Context

**Language/Version**: Swift 6 (strict concurrency `complete`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).

**Primary Dependencies**: SwiftUI (`contentMargins`, `ScrollView`, `List`), UIKit (existing
cropping), Google Gemini via the existing service. No new dependency, no new service.

**Storage**: No change. The `region` field added in feature 006 already exists on saved data; this
feature only changes how it is *requested*. No migration.

**Testing**: XCTest in `KaloriasTests`. The 158 existing tests must stay green. New coverage targets
the two things that were wrong: the schema declares `box` required, and the parser still tolerates a
missing/garbage box. Clearance is inherently a layout property — verified by the runtime procedure in
[quickstart.md](./quickstart.md), not by a unit test.

**Target Platform**: iOS 26.5+.

**Project Type**: Native iOS app. New sources under `Kalorias/` auto-included; new test files need a
`project.pbxproj` entry.

**Performance Goals**: unchanged. The output ceiling only caps pathological replies.

**Constraints**: the analysis must not become less reliable than pre-006 (FR-002); a missing box must
never block saving (FR-005); the bar stays floating and translucent in place (FR-013); no double
inset (FR-015); clearance verified by scrolling to the end (FR-014).

**Scale/Scope**: 1 schema/prompt change + 1 config addition + 1 shared clearance constant/modifier
applied at 3 scroll containers + revert of an ineffective root-level inset. 2–3 new test cases.

## Constitution Check

*GATE: evaluated against Kalorias Constitution v1.1.1. Re-checked after Phase 1 — see below.*

| Principle | Gate | Status |
|-----------|------|--------|
| I. Code Quality | The clearance value lives in **one** shared constant, not repeated magic numbers — the mistake feature 005/006 made twice. The ineffective root-level inset is **removed**, not left beside the working fix. No force-unwraps. | ✅ |
| II. Testing (NON-NEG) | A regression test asserts the schema marks `box` required — the exact defect, so it cannot silently return. Parser leniency keeps its existing cases. Bug-fix-with-regression-test is explicitly required by Principle II. | ✅ |
| III. UX Consistency | Bar unchanged visually: native Liquid Glass, translucent, same position; content still passes behind it. Analysis failures already surface an actionable error; the ceiling routes runaway replies into that same path rather than a hang. | ✅ |
| IV. Performance | No new main-thread work. The token ceiling strictly reduces worst-case latency and cost. | ✅ |
| V. Architecture (NON-NEG) | Swift 6 strict; Gemini stays confined to its service; Router untouched; no ViewModel. | ✅ |
| VI. Localization & Appearance | No new user-facing copy expected (the existing analysis error is reused). Any new string would need EN+ES. | ✅ |
| Tech Constraints | Gemini remains the only external service; the change is one schema field plus a generation-config cap. Nothing new leaves the device. | ✅ |
| Design System (governance) | No new token. Table untouched. | ✅ |

**Result**: All gates pass. One prior violation is corrected (a magic clearance number and an
ineffective inset both removed). Complexity Tracking records the reverted 006 approach.

## Project Structure

### Documentation (this feature)

```text
specs/007-fix-scroll-and-boxes/
├── plan.md                  # This file
├── research.md              # Phase 0 — 5 measured decisions
├── data-model.md            # Phase 1 — no data change; request contract change only
├── quickstart.md            # Phase 1 — incl. the verification procedure FR-014 demands
├── contracts/
│   └── ui-contracts.md      # schema delta, clearance contract, screen states
├── checklists/requirements.md
└── tasks.md                 # /speckit-tasks (not created here)
```

### Source Code (repository root)

```text
Kalorias/
├── Features/Analysis/
│   └── GeminiCalorieService.swift        # MODIFIED (US1): `box` → required; add maxOutputTokens
├── DesignSystem/
│   └── BottomBar.swift                   # MODIFIED (US3): expose the shared clearance constant
├── App/
│   └── RootView.swift                    # MODIFIED (US3): remove the ineffective safeAreaInset,
│                                         #   restore the bar as a floating overlay
├── Features/History/
│   ├── MealDetailsView.swift             # MODIFIED (US3): bottom content margin
│   └── HistoryView.swift                 # MODIFIED (US3): bottom content margin on the List
├── Features/Progress/
│   └── ProgressTabView.swift             # MODIFIED (US3): bottom content margin
└── (no change to FoodRegion, FoodThumbnailCropper, MealEntry, StoredFood)

KaloriasTests/
└── CalorieAnalysisDecodingTests.swift    # MODIFIED: assert `box` is required in the schema
```

**Structure Decision**: The clearance is applied **inside** each scroll container because that is
the only place it demonstrably takes effect — a root-level inset is swallowed by `NavigationStack`
(research R3). To avoid repeating the magic number that feature 005 introduced and feature 006 tried
to delete, the value is exposed once on `BottomBar` (the thing whose height it describes) and
referenced by all three call sites. No new file is created; this is a fix, not a feature.

### Post-Design Constitution Re-Check

- **No new violations.** No new dependency, service, token, migration or ViewModel.
- **Principle I improved**: one constant replaces the per-screen magic numbers, and the ineffective
  inset is deleted rather than layered under the real fix.
- **Principle II sharpened**: the regression test asserts the *schema shape* (`box` in `required`),
  which is the precise thing whose absence caused an outage. A test on parsing alone would not have
  caught it, because parsing was never the broken part.
- **Risk accepted**: clearance remains verifiable only at runtime. FR-014 and the quickstart
  procedure exist so the verification can actually fail — the gap that let 006 ship broken.

## Complexity Tracking

> No new violations. The rows record what this feature reverts or corrects.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Feature 006's root-level `safeAreaInset` is removed rather than kept alongside the new fix | Measured ineffective: `NavigationStack` re-propagates `safeAreaInsets.bottom = 0`. Keeping it would leave two mechanisms for one job and risk double-insetting any future screen not wrapped in a `NavigationStack` (FR-015). | Keeping both was rejected: it is exactly the "hack beside the real fix" that Principle I forbids, and it is how the clearance number ended up duplicated in the first place. |
| Per-scroll-container clearance reintroduces a per-screen concern that 006 tried to centralize | It is the only mechanism that works, given `NavigationStack`'s behaviour. Centralized through one constant on `BottomBar`, so there is still a single source of truth. | A native `TabView` bar would let the framework handle insets, but replacing the custom Liquid Glass bar with its centre camera action is a redesign well beyond a defect fix. Recorded as the longer-term option. |
| `box` becomes `required` in the schema although the app treats it as optional | Measured: optional causes a `MAX_TOKENS` runaway that loses the meal entirely. Required produces clean replies with boxes. | Leaving it optional was rejected on evidence. FR-006 records that request-strictness and parser-tolerance are separate concerns — conflating them is what caused the outage. |
