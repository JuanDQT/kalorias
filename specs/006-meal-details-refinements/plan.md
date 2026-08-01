# Implementation Plan: Meal Details Refinements — Clearance, Colour Consistency & Ingredient Thumbnails

**Branch**: `006-meal-details-refinements` | **Date**: 2026-07-26 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/006-meal-details-refinements/spec.md`

## Summary

Three changes to the meal details screen, in priority order:

1. **Bottom-bar clearance (US1)** — fixed at the root, not per screen: `RootView` currently draws
   `BottomBar` as a `ZStack` overlay, so it is invisible to the safe-area system and no scroll
   view insets for it. Moving it to `.safeAreaInset(edge: .bottom)` makes every screen inset
   correctly, satisfies FR-004 for free, and lets us delete the manual `.padding(.bottom, 96)`
   hack that feature 005 added to `ProgressTabView`.
2. **Colour consistency (US2)** — `HistoryView` already computes each row's `CalorieColorStep`
   relative to its week. That same value is handed to `MealDetailsView` through the navigation
   destination, so the two screens cannot disagree (FR-006 forbids re-deriving it).
3. **Ingredient thumbnails (US3)** — the analysis is asked for a per-food bounding box, the box
   is stored as a **proportional** region alongside the food, and the details screen crops the
   meal's own stored photo to it.

Four research findings shape the design (see [research.md](./research.md)):

- **Gemini returns boxes as `[ymin, xmin, ymax, xmax]` normalized 0–1000 — y first.** Assuming
  the usual x-first order silently produces crops of the wrong part of the photo.
- **No SwiftData migration is needed.** Feature 003 persists foods as JSON in a single `Data`
  column, so adding an optional `region` to `StoredFood` decodes as `nil` on every existing row.
- **`cgImage.cropping(to:)` is the wrong tool**: it ignores `UIImage.imageOrientation`, and the
  stored JPEG is not guaranteed to be `.up` (`DiskImageStore.downsized` returns the original
  untouched when it is already small enough).
- **Crop once, not per row**: the details screen already loads the photo once; all crops are
  produced in a single detached pass so 15 rows do not spawn 15 file reads.

## Technical Context

**Language/Version**: Swift 6 (strict concurrency `complete`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).

**Primary Dependencies**: SwiftUI, UIKit (`UIImage`, `UIGraphicsImageRenderer` for
orientation-safe cropping), Foundation. Google Gemini via the existing
`GeminiCalorieService` — the prompt and response schema gain one field; **no new external
service**. Reuses feature 004's `CalorieColorScale` / `CalorieColorStep` and feature 005's
`CalorieColorStep.color` mapping.

**Storage**: One **additive, optional** field on `StoredFood` (persisted inside the existing
`foodsData` JSON). **No schema migration, no new file, no store version bump.**

**Testing**: XCTest in `KaloriasTests`. New pure suites for region validation and for cropping
geometry; the existing `CalorieAnalysisDecodingTests` gains box-parsing fixtures. UI tests OFF.

**Target Platform**: iOS 26.5+.

**Project Type**: Native iOS app. New sources under `Kalorias/` are auto-included; **new test
files require a `project.pbxproj` edit** (`KaloriasTests/` is not a synchronized group).

**Performance Goals**: Details screen visible < 1s and smooth with ≥ 15 ingredients (SC-005).
Cropping happens off the main thread and never gates the screen appearing (FR-018).

**Constraints**: regions are optional everywhere and MUST NOT become a precondition for saving a
meal (FR-021); a missing/degenerate/out-of-bounds box yields a placeholder, never a distorted
crop (FR-015); everything works offline (FR-016); the bottom bar stays translucent and floating
(FR-003); colours from `AppColor` only; EN+ES for new strings.

**Scale/Scope**: 1 new pure value type + 1 new cropping helper + 1 root-level layout change +
edits to 2 views, the analysis service, and 2 model files; 2 new test suites + 1 extended.

## Constitution Check

*GATE: evaluated against Kalorias Constitution v1.1.1. Re-checked after Phase 1 — see below.*

| Principle | Gate | Status |
|-----------|------|--------|
| I. Code Quality | Region validation, unit→pixel conversion and crop geometry live in dedicated testable types, never in view bodies. No force-unwraps; every optional box path is explicit. No dead code — the `.padding(.bottom, 96)` hack from feature 005 is **removed**, not left alongside the real fix. | ✅ |
| II. Testing (NON-NEG) | Region clamping/rejection, the y-first axis order, unit→pixel conversion, and crop output size are unit-tested with normal, zero/empty and boundary cases. Decoding gains fixtures for box present / absent / malformed / out-of-range. | ✅ see [quickstart.md](./quickstart.md) |
| III. UX Consistency | Colour now means the same thing on both screens (the point of US2). Thumbnails are decorative — the name and calories remain the labels (FR-022). Placeholder styling matches the existing photo fallback. Glass rows keep native Liquid Glass; the ingredient rows are migrated to the shared `GlassCard` helper introduced in feature 005 rather than keeping a fourth ad-hoc `.glassEffect`. Dynamic Type: rows grow, never clip. | ✅ |
| IV. Performance | Crops computed once per screen in one detached pass, not per row; thumbnails are small; the screen renders before crops arrive. No main-thread image work. | ✅ |
| V. Architecture (NON-NEG) | Swift 6 strict; MV — views render passed-in values. Gemini stays confined to `GeminiCalorieService` (never called from a view). Router untouched: the colour step travels through the existing `navigationDestination`, not through new navigation state. | ✅ |
| VI. Localization & Appearance (NON-NEG) | New strings (placeholder accessibility wording) in EN+ES; thumbnails and placeholder verified in light and dark. | ✅ |
| Tech Constraints | No third-party dependency; no new networked service — one extra field on an existing approved Gemini call. Nothing leaves the device beyond the photo already being sent for analysis. | ✅ |
| Design System (governance) | No new token; reuses `success`/`caution`/`warning`/`danger` via the existing step→colour mapping. Constitution table untouched. | ✅ |

**Result**: All gates pass. Two pre-existing violations are *reduced* rather than propagated
(see Complexity Tracking). No new violations to justify.

## Project Structure

### Documentation (this feature)

```text
specs/006-meal-details-refinements/
├── plan.md                  # This file
├── research.md              # Phase 0 — 8 resolved decisions
├── data-model.md            # Phase 1 — the one additive field + derived values
├── quickstart.md            # Phase 1 — build/test/validate guide
├── contracts/
│   └── ui-contracts.md      # pure APIs, Gemini schema delta, screen states, a11y, l10n
├── checklists/requirements.md
└── tasks.md                 # /speckit-tasks (not created here)
```

### Source Code (repository root)

```text
Kalorias/
├── App/
│   └── RootView.swift                      # MODIFIED (US1): ZStack overlay → .safeAreaInset(edge: .bottom)
├── Features/Progress/
│   └── ProgressTabView.swift               # MODIFIED (US1): delete the manual .padding(.bottom, 96)
├── Features/Analysis/
│   ├── FoodRegion.swift                    # NEW: pure proportional rect + validating init
│   ├── CalorieAnalysis.swift               # MODIFIED: FoodItem gains `region: FoodRegion?`
│   └── GeminiCalorieService.swift           # MODIFIED: prompt + responseSchema request box_2d; parse it
├── Features/History/
│   ├── MealEntry.swift                     # MODIFIED: StoredFood gains `region: FoodRegion?` (no migration)
│   ├── FoodThumbnailCropper.swift           # NEW: orientation-safe crop, unit rect → UIImage
│   ├── MealDetailsView.swift                # MODIFIED: colour step, thumbnails, GlassCard
│   └── HistoryView.swift                    # MODIFIED: hoist groups so the destination can pass the step
└── Resources/
    └── Localizable.xcstrings                # MODIFIED: thumbnail placeholder a11y strings (EN+ES)

KaloriasTests/                               # both new files need a project.pbxproj entry
├── FoodRegionTests.swift                    # NEW
├── FoodThumbnailCropperTests.swift          # NEW
└── CalorieAnalysisDecodingTests.swift       # MODIFIED: box_2d fixtures
```

**Structure Decision**: `FoodRegion` lives in `Features/Analysis/` because it originates in the
analysis response and is consumed by both the analysis domain (`FoodItem`) and the persisted
snapshot (`StoredFood`) — the same direction of dependency `FoodItem` → `StoredFood` already
has. It is a pure `nonisolated` `Codable` value with **no UIKit import**, so the geometry rules
are unit-testable without an image. `FoodThumbnailCropper` sits in `Features/History/` beside
`ImageStore`, since it is the only place UIKit cropping happens and it mirrors the existing
image-IO boundary.

### Post-Design Constitution Re-Check

Re-evaluated after the Phase 1 artifacts were written:

- **No new violations.** No ViewModel, no third-party dependency, no new external service, no
  schema migration, no new colour token.
- **Principle I improved**: the root-cause safe-area fix lets a genuine hack be deleted rather
  than a second one added. The ingredient rows also stop being a fourth ad-hoc `.glassEffect`
  call site.
- **Principle II**: splitting geometry (`FoodRegion`, pure, no UIKit) from pixels
  (`FoodThumbnailCropper`, UIKit) means the axis-order and clamping rules — the parts most likely
  to be wrong — are tested without constructing images.
- **Principle IV**: the crop pass was moved from per-row to once-per-screen during design, so a
  15-ingredient meal does one decode instead of fifteen.
- **Risk accepted and recorded**: FR-021 makes regions strictly optional at every layer, so the
  worst case of the analysis change is that thumbnails are missing — never that a meal fails to
  save. This is the guardrail that keeps a presentation feature from endangering the core flow.

## Complexity Tracking

> No violations introduced. The rows below record **pre-existing** issues this feature reduces.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| `BottomBar` drawn as a `ZStack` overlay in `RootView`, invisible to the safe-area system — the root cause of US1, and the reason feature 005 needed a manual `.padding(.bottom, 96)` | US1 requires content to scroll clear of the bar on *every* screen (FR-004). Fixing the container fixes all of them at once. | Adding per-screen bottom padding was rejected: it is what created the inconsistency (Progress padded, Details not), and every future screen would have to remember it. |
| Ad-hoc `.glassEffect(.regular, in: .rect(cornerRadius: 18))` at `MealDetailsView.swift:100` — Principle III requires glass through a shared helper | This feature already edits the ingredient rows, so migrating them to the `GlassCard` helper costs nothing extra and removes one of the two remaining ad-hoc sites. | Leaving it was rejected: the helper now exists (feature 005), so a new edit to this exact line has no excuse to keep the duplication. `AnalysisResultView.swift:125` remains and stays out of scope. |
