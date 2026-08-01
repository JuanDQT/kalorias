# Phase 1 Contracts: Meal Details Refinements

**Feature**: `006-meal-details-refinements` | **Date**: 2026-07-26

The app exposes no public API, so the contracts that matter are the **pure APIs**, the **Gemini
wire-format delta** (the one genuinely external interface), the **screen states**, the
**accessibility identifiers**, and the **localization keys**.

---

## 1. Gemini request/response delta

The only change to the external call is an **optional** per-food `box`.

### `responseSchema` addition

```
foods.items.properties.box = {
  "type": "OBJECT",
  "properties": {
    "ymin": { "type": "INTEGER" },
    "xmin": { "type": "INTEGER" },
    "ymax": { "type": "INTEGER" },
    "xmax": { "type": "INTEGER" }
  },
  "required": ["ymin", "xmin", "ymax", "xmax"]
}
```

`box` is **NOT** added to `foods.items.required`. That single fact is what implements FR-021: a
response with no boxes still validates, still decodes, and still saves a meal.

### Prompt addition

Must state, explicitly: report for each food the bounding box of the region it occupies, as
integers on a **0–1000 normalized** scale relative to the image, where `ymin`/`ymax` measure from
the **top** edge and `xmin`/`xmax` from the **left**.

**Why named edges rather than Gemini's native `box_2d` array**: the native form is
`[ymin, xmin, ymax, xmax]` — **y before x**, the opposite of the `(x, y, …)` order most code
assumes. Reading that array pair-swapped yields a valid-looking crop of the wrong part of the
photo, with no error raised anywhere. Named fields make the axis order unmissable on both sides
of the wire (research R3).

### `FoodPayload.Food` decoding contract

| # | Guarantee | Requirement |
|---|---|---|
| G1 | `box` absent → food decodes with `region == nil` | FR-021 |
| G2 | Some foods with `box`, some without → all decode; only the former get a region | FR-021 |
| G3 | A malformed `box` (missing an edge, wrong type) → that food's `region` is `nil`; **the meal still parses** | FR-015, FR-021 |
| G4 | `ymin/xmin/ymax/xmax` map to top/left/bottom/right — **never** pair-swapped | research R3 |
| G5 | Conversion divides by 1000 to reach unit space | R3, R5 |
| G6 | Existing decoding behaviour for name/calories/macros is unchanged | FR-020 |

---

## 2. Pure logic APIs

### 2.1 `FoodRegion` — `Kalorias/Features/Analysis/FoodRegion.swift`

```swift
nonisolated struct FoodRegion: Codable, Hashable, Sendable {
    let x: Double        // 0...1, from the left
    let y: Double        // 0...1, from the top
    let width: Double    // > 0
    let height: Double   // > 0

    /// Unit-space rect. Clamps into 0...1; nil when the result is not croppable.
    init?(clampingX x: Double, y: Double, width: Double, height: Double)

    /// Gemini's 0–1000 normalized edges, y-first by convention.
    init?(geminiTop ymin: Int, left xmin: Int, bottom ymax: Int, right xmax: Int)
}
```

**Contract**

| # | Guarantee | Requirement |
|---|---|---|
| F1 | Every constructible value is croppable — an invalid region cannot exist | FR-015 |
| F2 | Edges outside `0...1` are clamped, not rejected | R5 |
| F3 | Non-positive width/height after clamping → `nil` | FR-015 |
| F4 | Inverted edges (`ymax < ymin`) → `nil` | FR-015 |
| F5 | A box covering the whole image is **valid** (0,0,1,1) | spec edge case |
| F6 | `geminiTop:left:bottom:right:` divides by 1000 and maps top→`y`, left→`x` | G4, G5 |
| F7 | No UIKit/CoreGraphics import — testable without an image | Principle II |
| F8 | Round-trips through `Codable` unchanged | FR-017 |

### 2.2 `FoodThumbnailCropper` — `Kalorias/Features/History/FoodThumbnailCropper.swift`

```swift
nonisolated enum FoodThumbnailCropper {
    /// Crop `image` to `region`, rendered at up to `maxDimension` points.
    /// nil when the region cannot produce a usable image.
    static func crop(_ image: UIImage, to region: FoodRegion, maxDimension: CGFloat) -> UIImage?

    /// All crops for the foods that have a region, keyed by food id.
    static func crops(
        for foods: [StoredFood],
        from image: UIImage,
        maxDimension: CGFloat
    ) -> [UUID: UIImage]
}
```

**Contract**

| # | Guarantee | Requirement |
|---|---|---|
| C1 | Uses `UIGraphicsImageRenderer` + `draw(in:)`; **never** `cgImage.cropping(to:)`, which ignores `imageOrientation` | FR-015, R6 |
| C2 | Geometry is computed against `image.size` (orientation-corrected logical size), not `cgImage.width/height` | R6 |
| C3 | Output is no larger than `maxDimension` on its longest side | FR-018, R7 |
| C4 | Output aspect ratio matches the region's — no stretching | FR-015 |
| C5 | A zero-sized source image → `nil`, no crash | FR-015 |
| C6 | `crops(for:from:)` skips foods with `region == nil`; the returned dictionary has no entry for them | FR-010 |
| C7 | One pass over the in-memory image — no file reads per food | FR-018, R7 |
| C8 | Never force-unwraps | Principle I |

---

## 3. Screen state contracts

### 3.1 `RootView` — the US1 fix

| Before | After |
|---|---|
| `ZStack(alignment: .bottom) { surface; content; BottomBar() }` | `content` with `.safeAreaInset(edge: .bottom) { BottomBar(...) }` |

**Requirements**

- The bar keeps its current appearance: native Liquid Glass, translucent, floating, horizontally
  inset (FR-003). Only its participation in the layout changes.
- Every screen behind it inherits the inset — no per-screen padding (FR-004).
- `ProgressTabView`'s `.padding(.bottom, 96)` is **deleted** in the same change, or the Progress
  tab ends up doubly inset.
- The camera `fullScreenCover` and the surface background are unaffected.

### 3.2 `HistoryView`

The week grouping moves to a scope both the list **and** `navigationDestination(for:)` can read,
so the destination can resolve the tapped entry's `CalorieColorStep` from the same values that
coloured its row. **No visible change to the list** (FR-020) — same rows, same order, same
headers, same colours.

### 3.3 `MealDetailsView`

Signature gains the colour step:

```swift
MealDetailsView(entry: MealEntry, colorStep: CalorieColorStep, imageStore: any ImageStoring)
```

| Element | Change |
|---|---|
| Large calorie figure | `AppColor.brandPrimary` → `colorStep.color` (FR-005) |
| Ingredient rows | gain a leading thumbnail or placeholder (FR-009, FR-010) |
| Ingredient row glass | ad-hoc `.glassEffect(...)` → the shared `glassCard(...)` helper |
| Header photo, date line, total label | **unchanged** |
| Bottom padding | none added — the safe-area inset from `RootView` handles it |

**Thumbnail rendering**

- Fixed-size leading square, rounded-rect clipped, matching `MealRowView`'s visual language at a
  smaller size.
- Placeholder: `surfaceElevated` with a `fork.knife` symbol in `textSecondary` — the same
  treatment the header photo already falls back to.
- Fixed size, never flexible width, so large Dynamic Type grows the row instead of squeezing the
  text (FR-012).
- Marked **decorative / hidden from assistive technology** (FR-022): the name and calories are the
  informative content and are already announced, so labelling the crop would only add noise.

---

## 4. Accessibility contract

Existing identifiers are **preserved**: `mealDetails.screen`, `mealDetails.total`,
`mealDetails.foodList`.

| New identifier | Element |
|---|---|
| `mealDetails.food.thumbnail` | the leading image or placeholder on an ingredient row |

**Requirements**

- Thumbnails are decorative and hidden from VoiceOver; each row still announces name, calories and
  macros as it does today.
- The coloured calorie figure remains readable text — colour is never the sole carrier (FR-008).
- No fixed row heights or `lineLimit` that would clip at accessibility text sizes.

---

## 5. Localization contract — `Kalorias/Resources/Localizable.xcstrings`

This feature adds **no visible copy**. Existing `mealDetails.*` and `history.kcalUnit` keys are
unchanged.

| Key | `en` | `es` | Use |
|---|---|---|---|
| `mealDetails.food.noImage` | `No image available` | `Sin imagen disponible` | Reserved for the placeholder should it ever need an accessibility label; **not** applied while thumbnails stay decorative (FR-022). |

Adding this one key keeps the option open without shipping untranslated text later. If the
decorative decision holds through implementation, the key may be dropped rather than left unused —
Principle I forbids dead code, and that includes unused catalog entries.

---

## 6. Design-system contract

**No new token.** The calorie figure uses the existing `CalorieColorStep.color` mapping
(`success` / `caution` / `warning` / `danger`) added in feature 005; the placeholder uses
`surfaceElevated` and `textSecondary`. The constitution's token table is untouched.

**Glass**: ingredient rows move to the shared `glassCard(...)` helper from feature 005, removing
one of the two remaining ad-hoc `.glassEffect` call sites. `AnalysisResultView.swift:125` is the
last one and stays out of scope.
