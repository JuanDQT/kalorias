# Phase 0 Research: Meal Details Refinements

**Feature**: `006-meal-details-refinements` | **Date**: 2026-07-26

All Technical Context unknowns are resolved below. No `NEEDS CLARIFICATION` remains.

---

## R1 — Root cause of the bottom bar covering content (US1, FR-001…FR-004)

**Decision**: move `BottomBar` from the `ZStack` overlay in `RootView` into
`.safeAreaInset(edge: .bottom) { BottomBar(...) }`, and delete the manual
`.padding(.bottom, 96)` that feature 005 added to `ProgressTabView`.

**Rationale**: `RootView` currently renders

```
ZStack(alignment: .bottom) { surface; content; BottomBar() }
```

A `ZStack` sibling is invisible to the safe-area system, so no scroll view or list inside
`content` knows the bar exists and none of them inset for it. That is the whole bug: the details
screen's `ScrollView` genuinely has nowhere left to scroll, which is exactly what the user
reported ("incluso haciendo scroll hacia abajo").

`safeAreaInset` is the framework's answer to this: it reserves the bar's height as bottom safe
area for everything inside, so scroll views and lists inset automatically. Content still passes
*behind* the translucent bar while scrolling and comes to rest clear of it — which is precisely
FR-001 + FR-003 together, the same behaviour a real `TabView` bar has.

It also fixes FR-004 across the whole app in one change, and reveals that feature 005's
`.padding(.bottom, 96)` was compensating for this at one call site. That padding is **deleted**,
not left in place, or the Progress tab would end up doubly inset.

**Alternatives considered**:
- *Per-screen bottom padding on the details screen* — rejected: this is what produced the
  inconsistency in the first place (Progress padded, Details not), and every future screen would
  have to remember a magic number.
- *Hide the bar while a details screen is pushed* — rejected: a navigation-behaviour change, out
  of scope per the spec's Assumptions, and it would not fix FR-004 for other screens.
- *Make the bar opaque and non-floating* — rejected outright by FR-003.

---

## R2 — Getting the list's colour onto the details screen (US2, FR-005/FR-006)

**Decision**: hoist the week grouping in `HistoryView` so both the list and the
`navigationDestination(for: MealEntry.self)` closure read the same `[MealWeekGroup]`, look up the
tapped entry's group, and pass its `CalorieColorStep` into `MealDetailsView`.

**Rationale**: FR-006 forbids re-deriving the colour, and for good reason — the list's colour is
*relative to the entry's week* (`lowest`/`highest` of its group). Any second computation is a
place for the two screens to drift apart, which is the exact bug the user is reporting, just
moved. Reading the already-computed groups makes a mismatch structurally impossible.

The Router is untouched: `historyPath` still carries `MealEntry`, and the step travels as a
parameter of the destination view rather than as new navigation state (Principle V).

Feature 004's grouping guarantees the lookup succeeds — the groups partition every entry
(asserted by `testEveryItemLandsInExactlyOneGroup`). The `.low` fallback for "group not found" is
therefore unreachable and exists only to avoid a force-unwrap.

**Alternatives considered**:
- *Recompute in `MealDetailsView` from its own `@Query`* — rejected by FR-006: two
  implementations of "which week is this and what are its bounds" will eventually disagree.
- *Store the step on `MealEntry`* — rejected: it is relative and changes as the week fills up, so
  persisting it would go stale. Also a schema change for a derived value.
- *Pass `lowest`/`highest` and recompute the step in the details view* — rejected: same drift
  risk for no benefit; the step itself is the smaller, more precise thing to pass.

**Consequence, already recorded in the spec**: because the scale is week-relative, a meal's
colour can change as more meals are logged that week. The details screen shows whatever the list
currently shows, which is the consistency asked for.

---

## R3 — Bounding-box format from the analysis (US3, FR-014)

**Decision**: extend the existing `responseSchema` with an optional per-food `box` object of four
**named** integer properties — `ymin`, `xmin`, `ymax`, `xmax` — on Gemini's documented
**0–1000 normalized** scale, and state that convention explicitly in the prompt. `box` is **not**
added to the schema's `required` list.

**Rationale**: Gemini's object-localization convention returns boxes as `[ymin, xmin, ymax, xmax]`
normalized to 0–1000 — **y before x**, which is the opposite of the `(x, y, w, h)` ordering most
code assumes. Consuming that as an array is a standing invitation to a silent bug: swapping the
pair produces a perfectly valid-looking crop of the wrong part of the photo, with no error
anywhere.

Using **named fields** removes that entire bug class. We already send a `responseSchema`
(structured output), so the model's output shape is constrained either way; naming the edges
costs nothing and makes both the wire format and our parsing self-documenting. The 0–1000 scale
is kept rather than switching to 0–1 floats, because it matches what the model is trained to
emit.

Marking `box` optional (not `required`) is what implements FR-021: a response with no boxes, or
boxes on only some foods, still decodes and still saves a meal with its calories and macros.

**Alternatives considered**:
- *Native `box_2d` array* — the format the model knows best, but it carries the y-first ordering
  trap into our code. Named fields keep the same semantics without the trap.
- *Ask for 0–1 floats* — deviates from the trained convention for no gain, since we normalize on
  ingest anyway.
- *A separate localization call* — rejected: doubles latency, cost and failure modes for a
  decorative thumbnail.

**Not verified here**: real-world box quality. The prompt/schema change is mechanical, but how
tightly the model actually boxes food is an empirical question that needs a live call with a real
photo. That is a manual validation step in [quickstart.md](./quickstart.md), and the spec already
accepts loose boxes (a thumbnail is a visual aid, not evidence).

---

## R4 — Storing the region without a migration (FR-017)

**Decision**: add `region: FoodRegion?` to `StoredFood`. **No SwiftData migration, no store
version bump.**

**Rationale**: verified empirically rather than assumed. Feature 003 persists foods as
`foodsData: Data` — a JSON blob — rather than as a SwiftData relationship, so the *schema* does
not mention foods at all. Adding an optional property to the `Codable` struct inside that blob is
backward compatible: JSON written by the current app has no `region` key, and an optional decodes
as `nil`.

Confirmed by decoding a payload in the exact shape the shipped app writes
(`{"id":…,"name":"Pollo","calories":320,"protein":31.5}`) against the extended struct: it decodes,
`region == nil`, and a round-trip with a region preserves it. `MealEntry.foods` additionally has
a `?? []` fallback on decode failure, so even a malformed blob degrades rather than crashes.

This is a genuinely lucky property of feature 003's design; it would not hold had foods been a
SwiftData relationship.

**Alternatives considered**:
- *A parallel array of regions on `MealEntry`* — rejected: two collections to keep index-aligned
  is a correspondence bug waiting to happen.
- *A new SwiftData model for regions* — rejected: a relationship and a migration for a small
  optional value inside data that is already JSON.

---

## R5 — The region's own representation (FR-014, FR-015)

**Decision**: a pure `nonisolated struct FoodRegion: Codable, Hashable, Sendable` holding
**proportional** `x`, `y`, `width`, `height` in unit space (`0...1`), origin top-left, created
through a **validating initializer that returns `nil`** for unusable input. No UIKit import.

**Rationale**:
- **Proportional, not pixels** (FR-014): `DiskImageStore` saves a *downsized* JPEG (max dimension
  1024), so the stored photo's pixel size differs from what the model saw. A pixel region would
  mis-crop by the downscale ratio — silently, and differently per photo. Unit coordinates survive
  any rescaling.
- **Validating initializer** as the single gate for FR-015: clamp each edge into `0...1` (a box
  reported slightly past the edge, e.g. `ymax = 1005`, is still useful, so clamping beats
  rejecting), then return `nil` if the clamped width or height is not positive. Degenerate,
  inverted and wholly-out-of-bounds boxes all collapse to `nil` → placeholder.
- **No UIKit**, so the geometry rules — the part most likely to be wrong — are unit-testable
  without constructing an image.

**Alternatives considered**:
- *Store `CGRect`* — it is `Codable`, but drags CoreGraphics into the analysis domain and, worse,
  carries no unit-vs-pixel information in its type. A named type documents the contract.
- *Reject rather than clamp out-of-range edges* — rejected: throws away usable thumbnails for
  boxes that are merely a few units over.
- *Validate at the crop site instead* — rejected: two call sites (analysis ingest, crop) would
  each need the rules; one validating initializer means an invalid `FoodRegion` cannot exist.

---

## R6 — Cropping the photo correctly (FR-015, FR-016)

**Decision**: crop with `UIGraphicsImageRenderer` and `draw(in:)`, **not**
`cgImage?.cropping(to:)`.

**Rationale**: `CGImage` has no notion of `UIImage.imageOrientation`. Cropping through it
silently ignores orientation, so for any photo whose orientation is not `.up` the crop comes from
a rotated interpretation of the coordinates — a wrong-region bug that looks like a bad model box.

That case is reachable here: `DiskImageStore.downsized` returns the **original image untouched**
when its longest side is already within the limit, and `UIImage.jpegData` preserves orientation
metadata, so `loadImage(named:)` can hand back a non-`.up` image. Only photos that actually got
downsized are guaranteed `.up` (the renderer normalizes them).

Drawing through `UIGraphicsImageRenderer` applies orientation as part of `draw(in:)`, so the unit
rect maps to what the user sees. Geometry: convert the unit rect against `image.size` (the
orientation-corrected logical size, not `cgImage.width/height`), then draw the full image offset
so the wanted region lands in the renderer's bounds.

**Alternatives considered**:
- *`cgImage.cropping(to:)` plus manual orientation handling* — rejected: reimplements what
  `draw(in:)` already does, with eight cases to get wrong.
- *Normalize every stored photo to `.up` at save time* — a defensible fix, but it changes
  feature 003's write path and re-encodes images for a presentation feature. Out of scope; the
  crop is made orientation-safe instead.

---

## R7 — Where and when crops are produced (FR-018, SC-005)

**Decision**: the details screen loads the photo once (as it already does), then produces **all**
crops in a **single detached pass** into a `[UUID: UIImage]` keyed by food id. Rows read that
dictionary synchronously and show the placeholder until it arrives.

**Rationale**: the naive approach — a `.task` per row, each loading and cropping — is 15 image
decodes for a 15-ingredient meal, on top of the full-size load the screen already does. Doing one
pass over the already-in-memory `UIImage` reduces that to zero extra decodes.

Crops must not gate the screen appearing (FR-018), so the view renders immediately with
placeholders and fills in when the pass completes — the same pattern `MealRowView` already uses
for its thumbnail, so it is consistent with the codebase.

Thumbnails are rendered at a small target size rather than kept at crop resolution, so 15
sub-images do not sit in memory at photo scale.

**Alternatives considered**:
- *Per-row `.task`* — rejected on the decode count above.
- *Precompute crops at save time and store them as files* — rejected: multiplies stored images
  per meal for a decorative feature, and would need a backfill story for existing meals.
- *Crop synchronously in the body* — rejected: main-thread image work, forbidden by Principle IV.

---

## R8 — Thumbnail presentation and accessibility (FR-010, FR-012, FR-022)

**Decision**: a small fixed-size leading square with the app's rounded-rect clipping, matching
`MealRowView`'s existing 56pt thumbnail treatment at a smaller size; the existing
`fork.knife`-on-`surfaceElevated` fallback as the placeholder; and the image marked
**decorative** (hidden from assistive technology).

**Rationale**: the ingredient rows already sit next to a codebase that solved this exact problem
in `MealRowView` — reusing its visual language keeps Principle III's consistency requirement and
gives an obvious placeholder that users have already seen on the history list.

Hiding the image from VoiceOver is the correct call under FR-022: the name and calorie figure are
the informative content and are already announced. A generated crop has no meaningful alt text —
labelling it "thumbnail of Pollo" would only add noise before the name that follows.

For Dynamic Type (FR-012), the image keeps a fixed size while the text column wraps, so rows grow
in height rather than squeezing the text — the image must not be given flexible width.

**Alternatives considered**:
- *Label each image with its ingredient name* — rejected: duplicates the adjacent text for
  VoiceOver users.
- *Scale the thumbnail with Dynamic Type* — rejected: at accessibility sizes the image would
  dominate the row and crowd out the text it is meant to support.
- *Circular crops* — rejected: the app's photo language is rounded rectangles everywhere else.
