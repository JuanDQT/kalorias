# Quickstart & Validation: Meal Details Refinements

**Feature**: `006-meal-details-refinements` | **Date**: 2026-07-26

How to build, test and prove this feature works. Signatures in
[contracts/ui-contracts.md](./contracts/ui-contracts.md); shapes and invariants in
[data-model.md](./data-model.md); the reasoning in [research.md](./research.md).

---

## Prerequisites

- Xcode 26.6+ (project targets **iOS 26.5**, Swift 6, `SWIFT_STRICT_CONCURRENCY = complete`)
- Scheme `Kalorias`, targets `Kalorias` + `KaloriasTests`
- No new packages
- **A Gemini API key in `Config/Secrets.xcconfig`** is required only for the live box-quality check
  (V5). Everything else — including all unit tests — runs without one.

New `.swift` files under `Kalorias/` are picked up automatically. **`KaloriasTests/` is not** — each
new test file must be registered in `project.pbxproj` (PBXBuildFile + PBXFileReference + the
group's `children` + the target's `Sources` phase) or it silently never runs. **A test count that
does not grow is the symptom.**

---

## Build

```bash
xcodebuild -project Kalorias.xcodeproj -scheme Kalorias \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build 2>&1 | tail -20
```

**Expected**: `BUILD SUCCEEDED`, **zero warnings**.

> If the simulator reports `FBSOpenApplicationServiceErrorDomain ... Busy`, boot it first:
> `xcrun simctl boot "iPhone 17 Pro Max" && xcrun simctl bootstatus "iPhone 17 Pro Max" -b`

## Test

```bash
xcodebuild -project Kalorias.xcodeproj -scheme Kalorias \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  test 2>&1 | tail -30
```

**Expected**: `TEST SUCCEEDED`. The **122 tests** from features 001–005 must all still pass — this
feature changes no calorie or macro behaviour, so any regression there is a real defect — plus the
two new suites and the extended decoding suite.

```bash
# just the new/changed suites while iterating
xcodebuild -project Kalorias.xcodeproj -scheme Kalorias \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:KaloriasTests/FoodRegionTests \
  -only-testing:KaloriasTests/FoodThumbnailCropperTests \
  -only-testing:KaloriasTests/CalorieAnalysisDecodingTests \
  test 2>&1 | tail -20
```

> UI tests stay **off** (Principle II).

---

## Required unit coverage

### `FoodRegionTests` — the geometry gate

| Case | Asserts | Contract |
|---|---|---|
| Valid unit rect | constructed, values preserved | F1 |
| Whole image `(0,0,1,1)` | **valid**, not rejected | F5 |
| Edge slightly out of range (e.g. `height` to 1.02) | clamped into range, still valid | F2 |
| Zero width | `nil` | F3 |
| Zero height | `nil` | F3 |
| Negative width | `nil` | F3 |
| Wholly out of bounds (x = 2.0) | `nil` after clamping | F2, F3 |
| **`geminiTop:left:bottom:right:` maps top→`y`, left→`x`** | `(ymin:100, xmin:500, ymax:300, xmax:900)` → `y == 0.1`, `x == 0.5`, `height == 0.2`, `width == 0.4` — **the test that catches an x/y swap** | F6 / research R3 |
| Gemini 0–1000 → unit | divides by 1000 | F5, F6 |
| Gemini full frame `(0,0,1000,1000)` | valid, equals the whole image | F5 |
| Gemini inverted (`ymax < ymin`) | `nil` | F4 |
| Gemini out of range (`ymax` 1005) | clamped, still valid | F2 |
| `Codable` round-trip | equal before and after | F8 |

### `FoodThumbnailCropperTests` — pixels and orientation

Build source images synthetically (as `ImageStoreTests` already does) — no fixtures on disk.

| Case | Asserts | Contract |
|---|---|---|
| Crop the left half of a 2:1 image | output aspect ≈ 1:1, not stretched | C4 |
| Crop respects `maxDimension` | longest side ≤ the limit | C3 |
| Whole-image region | output ≈ the source, scaled down | C4 |
| **Non-`.up` oriented source** | the crop covers the same visible region as for an `.up` source — **the test that catches `cgImage.cropping`** | C1, C2 / research R6 |
| Zero-sized source | `nil`, no crash | C5 |
| `crops(for:from:)` with mixed foods | entries only for foods that have a region | C6 |
| `crops(for:from:)` with no regions at all | empty dictionary, no crash | C6 |
| Keys | each entry keyed by its food's `id` | C6 |

### `CalorieAnalysisDecodingTests` — additions

| Case | Asserts | Contract |
|---|---|---|
| Payload **without** `box` (today's shape) | decodes; `region == nil`; calories/macros unchanged | G1, G6 |
| Payload with `box` on every food | each food gets a region with correct orientation | G2, G4 |
| Payload with `box` on **some** foods | mixed regions; all foods decode | G2 |
| `box` missing an edge | that food's `region == nil`; **the meal still parses** | G3 |
| `box` with wrong value types | same — degrades, does not throw for the whole meal | G3 |
| `box` out of range | clamped via `FoodRegion` | G5 |

### Persistence regression

Add to the existing `MealHistoryRepositoryTests`, or a new case:

| Case | Asserts | Contract |
|---|---|---|
| Record a meal whose foods have regions | regions survive save → fetch | FR-014 |
| Record a meal whose foods have **no** regions | saves normally; `region == nil` on read back | FR-021 |
| Decode a `foodsData` blob written **without** a `region` key | decodes, `region == nil` | FR-017, research R4 |

---

## Manual validation

### V1 — Bottom-bar clearance (US1) ⚠️ start here

1. Open a meal with enough ingredients to require scrolling. Scroll to the very bottom.
2. **Expect**: the last ingredient row is **fully visible**, clear of the bottom bar.
3. **Expect**: while scrolling, content passes *behind* the translucent bar — the bar has not
   become opaque and has not moved.
4. Open a meal with one ingredient (no scrolling needed): **expect** nothing overlapped.
5. Check **every** screen, since the fix is at the root: the **History list** (scroll to the last
   row) and the **Progress tab** (scroll to the bottom of the chart card). Progress must **not**
   look doubly inset — if there is a large gap above the bar, the old `.padding(.bottom, 96)` was
   not removed.

### V2 — Colour consistency (US2)

1. In the History list, find a week with several meals at different calorie levels.
2. Note the colour of the **lowest** meal's figure (green) — tap in. **Expect** the large figure is
   green.
3. Go back, note the **highest** meal (red) — tap in. **Expect** red.
4. Repeat for a middle meal (yellow/orange). **Expect** an exact match each time.
5. Open a meal from a week that has only that one meal. **Expect** green, matching the list.

### V3 — Ingredient thumbnails, existing meals (US3)

1. Open a meal saved **before** this feature.
2. **Expect**: every ingredient row shows the **placeholder**, the row text is fully readable, and
   nothing is blank or broken. This is the permanent state for old meals — regions were never
   recorded.

### V4 — Ingredient thumbnails, new meals (US3)

1. Capture and analyze a new photo with several distinguishable foods.
2. Open its details. **Expect**: most ingredient rows show a small crop of your own photo showing
   roughly that food.
3. **Expect**: any row the model did not box shows the placeholder, mixed freely with cropped rows.
4. **Expect**: the screen appears immediately; thumbnails may fill in a moment later — they must
   not delay the screen (FR-018).
5. **Expect**: no stretched, squashed or empty thumbnails.

### V5 — Box quality and the axis order ⚠️ the check that catches the y/x swap

Requires a real API key.

1. Analyze a photo where the foods are in **clearly different, asymmetric positions** — e.g. one
   food top-left and one bottom-right. Do **not** use a symmetric plate: a swapped x/y would look
   plausible.
2. **Expect**: the top-left food's thumbnail shows the top-left food. If the two thumbnails appear
   swapped or rotated, the `ymin/xmin` mapping is reversed (research R3).
3. **Expect**: boxes are roughly right. Loose crops are acceptable per the spec; crops of the
   wrong food are not.

### V6 — Failure paths

1. Turn off the network and analyze: the analysis fails as it does today. **Expect** no meal is
   saved, exactly as before — unchanged behaviour.
2. Open an existing meal with airplane mode on. **Expect** the details screen and its thumbnails
   work fully — crops come from the stored photo (FR-016).
3. Delete the stored photo file for a meal (or use one whose image is missing). **Expect** the
   header falls back to its placeholder **and** every ingredient row shows the placeholder, with
   no crash.

### V7 — Appearance, language, accessibility

1. Both appearances: **expect** thumbnails, placeholders, glass rows and the coloured figure all
   legible. Check the `caution` yellow figure in **light** mode particularly.
2. Both languages: **expect** no raw key strings, and the total's label unchanged.
3. Larger Text at a large size: **expect** ingredient rows **grow in height**, the text wraps, and
   the thumbnail stays its fixed size without squeezing the text off-screen.
4. VoiceOver: **expect** each ingredient row announces name, calories and macros; the thumbnail is
   **not** announced (it is decorative). The calorie figure is announced as a number.

### V8 — Performance (SC-005)

1. Open a meal with ≥ 15 ingredients.
2. **Expect**: visible in under 1 second, smooth scrolling, no hitch as thumbnails appear.
3. If it hitches: confirm the crops are produced in **one** pass off the main thread, not per row
   (research R7).

---

## Definition of done

- [X] `BUILD SUCCEEDED`, zero warnings under Swift 6 strict concurrency
- [X] `TEST SUCCEEDED` — new suites green **and** all 122 prior tests still passing
- [X] Both new test files registered in `project.pbxproj` (test count grew)
- [ ] V1 verified on **all three** scrollable screens; Progress is **not** doubly inset
- [ ] V2 matches exactly for a low, a middle and a high meal in the same week
- [ ] V3 old meals show placeholders and never break
- [ ] V5 verified with an asymmetric photo — thumbnails are not x/y swapped
- [ ] V6 offline details and missing-photo paths both degrade gracefully
- [X] `ProgressTabView`'s manual `.padding(.bottom, 96)` deleted
- [X] Ingredient rows use the shared `glassCard(...)` helper, not an ad-hoc `.glassEffect`
- [X] A meal still saves with correct calories when the analysis returns no boxes (FR-021)
- [X] No SwiftData migration added; existing meals open unchanged
- [X] No new colour token; constitution table untouched
- [X] `mealDetails.food.noImage` either used or removed — no unused catalog entry
