# Phase 1 Data Model: Meal Details Refinements

**Feature**: `006-meal-details-refinements` | **Date**: 2026-07-26

> **One additive optional field. No SwiftData migration, no store version bump.**
> Verified empirically (see research R4): JSON written by the shipped app decodes against the
> extended struct with `region == nil`.

---

## New value type

### `FoodRegion` — `Kalorias/Features/Analysis/FoodRegion.swift`

Where in a meal's photo a detected food sits. Pure, `nonisolated`, `Codable`, **no UIKit import**.

| Field | Type | Meaning | Range |
|---|---|---|---|
| `x` | `Double` | left edge, proportion of image width | `0...1` |
| `y` | `Double` | top edge, proportion of image height | `0...1` |
| `width` | `Double` | proportion of image width | `> 0`, and `x + width <= 1` |
| `height` | `Double` | proportion of image height | `> 0`, and `y + height <= 1` |

**Coordinate contract**: origin **top-left**, axes proportional to the image's logical size.
Deliberately *not* pixels — `DiskImageStore` saves a downsized JPEG (max dimension 1024), so a
pixel region would mis-crop by the downscale ratio, differently for every photo (research R5).

**Invariants**

1. An invalid `FoodRegion` **cannot exist**. The only way to make one is a validating
   initializer that returns `nil`, so every value in the system is croppable (FR-015).
2. Out-of-range edges are **clamped** into `0...1` before validation — a box reported slightly
   past the edge (`ymax = 1005` on the 0–1000 scale) is still useful.
3. After clamping, a non-positive `width` or `height` yields `nil`. This collapses degenerate,
   inverted, and wholly-out-of-bounds boxes into the placeholder path.
4. Values are proportions, never pixels, and survive the photo being stored at any scale.

---

## Modified existing types

### `FoodItem` — `Kalorias/Features/Analysis/CalorieAnalysis.swift`

| Change | Notes |
|---|---|
| **+** `region: FoodRegion?` | Optional. Defaults to `nil` so every existing construction site compiles unchanged. Excluded from `==` for the same reason `id` is: two foods with the same nutrition are the same food regardless of where they were spotted. |

### `StoredFood` — `Kalorias/Features/History/MealEntry.swift`

| Change | Notes |
|---|---|
| **+** `region: FoodRegion?` | Optional, carried through `init(from: FoodItem)` and `asFoodItem`. Persisted inside the existing `foodsData` JSON blob — **no schema change**. |

### `MealEntry` — *schema unchanged*

| Field | Used by this feature |
|---|---|
| `foods` | source of the ingredient rows and their regions |
| `imageFileName` | the photo every crop is taken from |
| `totalCalories` | already used by the list to pick the colour step; unchanged here |

**No stored property added.** The `foods` computed property already tolerates a decode failure
(`?? []`), so a malformed blob degrades to an empty list rather than crashing.

---

## Derived (not persisted) values

### `CalorieColorStep` — *reused from feature 004, unchanged*

Passed **into** `MealDetailsView` from `HistoryView`'s already-computed week groups. Not stored:
it is relative to the entry's week and changes as that week fills up, so persisting it would go
stale (research R2).

### Ingredient thumbnail — `[UUID: UIImage]`

Produced once per details screen, keyed by `StoredFood.id`, discarded when the view goes away.

| Property | Rule |
|---|---|
| Key | the food's `id`, so rows look theirs up directly |
| Presence | only for foods with a non-`nil` `region` **and** a loadable photo |
| Absence | row shows the placeholder — indistinguishable to the user from "no region recorded" |
| Timing | the screen renders before the crops arrive; they fill in after (FR-018) |

---

## Data flow

```text
Photo ──► GeminiCalorieService
              │  responseSchema gains an OPTIONAL per-food `box`
              │  {ymin, xmin, ymax, xmax} as INTEGER on Gemini's 0–1000 scale
              │  named edges, not an array — the array form is [ymin, xmin, …],
              │  y-first, and mis-reading it crops the wrong region silently (R3)
              ▼
       FoodRegion(clamping:) ──► nil  ─────────────► placeholder
              │  valid
              ▼
        FoodItem.region ──► StoredFood.region ──► foodsData JSON  (no migration, R4)
                                                        │
                                                        ▼
                                             MealDetailsView
                                                        │
   ImageStore.loadImage ──► UIImage ──► FoodThumbnailCropper (one detached pass, R7)
                                             │  UIGraphicsImageRenderer + draw(in:)
                                             │  NOT cgImage.cropping — that ignores
                                             │  imageOrientation and crops the
                                             │  wrong region for non-.up photos (R6)
                                             ▼
                                     [UUID: UIImage] ──► ingredient rows

HistoryView week groups ──► CalorieColorStep ──► MealDetailsView calorie figure (R2)
```

---

## Validation rules summary

| Rule | Source | Enforced by |
|---|---|---|
| Regions are proportional, never pixels | FR-014 | `FoodRegion` unit-space contract |
| Invalid box → placeholder, never a distorted crop | FR-015 | validating init returns `nil` |
| Out-of-range edges clamped, not rejected | R5 | clamp before validate |
| Regions never block saving a meal | FR-021 | optional at every layer; `box` not `required` in the schema |
| Existing meals stay valid | FR-017 | additive optional field in JSON (verified) |
| Crop respects photo orientation | FR-015 | renderer `draw(in:)`, not `cgImage.cropping` |
| Works offline | FR-016 | crops come from the stored photo, no network |
| Colour cannot disagree with the list | FR-006 | step passed in, never re-derived |
| Screen renders before crops | FR-018 | crops produced asynchronously after first render |
| Thumbnail never squeezes the text | FR-012 | fixed image size, flexible text column |
| Image adds no essential information | FR-022 | decorative, hidden from assistive technology |
