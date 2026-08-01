# Feature Specification: Fix Analysis Reliability, Ingredient Thumbnails & Bottom-Bar Clearance

**Feature Branch**: `007-fix-scroll-and-boxes`

**Created**: 2026-07-26

**Status**: Draft

**Input**: User description: "No has corregido el tema del scroll en la pantalla de detalles. La bottom var sigue tapando la lista de ingredientes. Ademas, las imagenes de los ingredientes no se ven. la clave de gemini esta puesta en GEMINI_API_KEY"

**Context**: This is a defect-fix feature. Feature 006 claimed to deliver bottom-bar clearance and
ingredient thumbnails; neither works in the running app. Both root causes were reproduced and
identified before writing this spec, and both are recorded below so the fix targets mechanisms
rather than symptoms.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Photo analysis works reliably again (Priority: P1)

As someone logging a meal, I need the photo analysis to succeed and save my meal, every time it
did before. Right now it can fail outright, which is worse than any cosmetic problem — a failed
analysis means no calories are recorded at all.

Asking the analysis for optional per-food bounding boxes made it unreliable: for at least some
photos the model runs away, emitting a colossal malformed reply that exceeds its output budget and
cannot be read. When that happens the analysis errors and no meal is saved. Requesting the boxes
as a **required** part of the reply makes it behave normally again and, as a side effect, actually
return the boxes.

**Why this priority**: This is a regression in the app's core function, introduced by feature 006.
Losing a meal record is more damaging than a missing thumbnail or an obscured row, so it is fixed
first.

**Independent Test**: Analyze several photos, including one with multiple distinct foods. Every
analysis that would have succeeded before must succeed now, save its meal with correct calories,
and complete without an oversized or malformed reply.

**Acceptance Scenarios**:

1. **Given** a photo containing recognizable food, **When** it is analyzed, **Then** the analysis
   succeeds and the meal is saved with its foods, calories and macros.
2. **Given** a photo the analysis previously handled successfully, **When** it is analyzed after
   this fix, **Then** it still succeeds — no photo becomes newly unanalyzable.
3. **Given** any analysis, **When** the reply is produced, **Then** it is complete and well-formed
   rather than truncated for exceeding the output budget.
4. **Given** a reply that is nonetheless malformed or truncated, **When** it is processed, **Then**
   the user sees a clear, actionable error and the app remains usable.
5. **Given** an analysis reply, **When** it is inspected, **Then** every detected food carries the
   region information needed for its thumbnail.
6. **Given** a food the analysis cannot localize, **When** the meal is saved, **Then** the meal is
   still saved in full with correct calories — the region remains optional to the *app*, even
   though it is now demanded of the *reply*.

---

### User Story 2 - Ingredient thumbnails actually appear (Priority: P2)

As a user reading a meal's breakdown, I want to see the small picture of each ingredient that was
promised, instead of a placeholder on every row.

With US1 fixed, newly analyzed meals carry regions, so their ingredient rows show crops of the
user's own photo. Meals saved before regions existed keep showing placeholders — that part is
expected and permanent.

**Why this priority**: This is the visible half of the user's complaint, but it is a consequence of
US1: without regions there is nothing to crop. It cannot be fixed independently.

**Independent Test**: Analyze a new photo with several distinct foods, open its details, and confirm
each ingredient row shows a crop of that region of the photo rather than the placeholder.

**Acceptance Scenarios**:

1. **Given** a meal analyzed after this fix, **When** its details are opened, **Then** its
   ingredient rows show crops of the meal photo rather than placeholders.
2. **Given** a crop is shown, **When** compared with the photo, **Then** it corresponds to the part
   of the photo where that food actually is — top-left food, top-left crop.
3. **Given** a meal saved before regions existed, **When** its details are opened, **Then**
   placeholders are shown, the rows remain readable, and nothing is broken.
4. **Given** a meal whose photo is missing, **When** its details are opened, **Then** every row
   shows the placeholder and nothing crashes.
5. **Given** a food the analysis could not localize, **When** its row is shown, **Then** it shows
   the placeholder alongside rows that do have crops.

---

### User Story 3 - The bottom bar stops covering the ingredient list (Priority: P2)

As a user reading a meal's ingredients, I want to scroll to the end of the list and read the last
row. The floating bottom bar still covers it, exactly as before feature 006 — that fix did not work.

The bar is drawn over the content and the scrollable area does not extend past it, so the final
ingredient cannot be brought into view no matter how far the user scrolls.

**Why this priority**: The same severity as US2 — it hides information the user opened the screen to
read — but it is independent of the analysis work, so it can proceed in parallel.

**Independent Test**: Open a meal with enough ingredients to require scrolling, scroll to the very
end, and confirm the last ingredient row is fully readable and not overlapped by the bar. **The
verification must involve actually scrolling to the end** — see FR-014.

**Acceptance Scenarios**:

1. **Given** a meal whose details require scrolling, **When** the user scrolls to the very end,
   **Then** the last ingredient row is fully visible above the bottom bar.
2. **Given** the user is scrolling, **When** content moves past the bar, **Then** it passes behind
   the translucent bar — the bar does not become opaque and does not move.
3. **Given** details that fit without scrolling, **When** shown, **Then** no content is overlapped.
4. **Given** the History list scrolled to its last row, **When** at rest, **Then** that row is
   fully visible above the bar.
5. **Given** the Progress tab scrolled to its end, **When** at rest, **Then** its last widget is
   fully visible, and there is no excessive empty gap above the bar from double insetting.
6. **Given** any screen behind the bar, **When** scrolled to its end, **Then** its final element is
   fully readable.

---

### Edge Cases

- **A food the model cannot localize**: the meal still saves; that row shows the placeholder.
- **A reply that is still malformed**: a clear error is surfaced; the app stays usable; no partial
  or corrupted meal is saved.
- **A reply that exceeds the output budget**: treated as a failure with an actionable message, not
  a hang or a silent no-op.
- **Meals saved before regions existed**: placeholders forever; not an error state.
- **A region that is degenerate or outside the image**: placeholder rather than a distorted crop.
- **Meal with one ingredient**: details fit without scrolling; nothing overlapped.
- **Meal with many ingredients**: scrolls fully clear of the bar.
- **Very long ingredient name**: wraps or truncates without pushing the calorie figure off-screen.
- **Largest Dynamic Type sizes**: rows grow taller; the last row still clears the bar.
- **Landscape orientation**: the last row still clears the bar.
- **The details screen reached and left repeatedly**: clearance and thumbnails behave identically
  each time.

## Requirements *(mandatory)*

### Analysis reliability (US1)

- **FR-001**: The analysis MUST request per-food region information as a **required** part of the
  reply rather than an optional one.
- **FR-002**: The analysis MUST NOT be less reliable than it was before regions were introduced —
  no photo that previously produced a successful analysis may now fail.
- **FR-003**: The analysis MUST bound how much reply it will accept, so a runaway reply fails
  quickly and predictably instead of consuming the entire output budget.
- **FR-004**: A truncated, oversized or malformed reply MUST surface a clear, actionable error to
  the user, MUST NOT save a partial meal, and MUST leave the app usable.
- **FR-005**: Region information being absent or unusable for a given food MUST NOT prevent that
  meal from being saved with its full calorie and macro data.
- **FR-006**: The requirement in FR-001 (demanded of the reply) and the tolerance in FR-005
  (accepted by the app) MUST both hold simultaneously — asking firmly and failing softly are
  separate concerns and MUST NOT be conflated again.

### Ingredient thumbnails (US2)

- **FR-007**: Meals analyzed after this fix MUST show a crop of the meal photo on each ingredient
  row for which a region was reported.
- **FR-008**: Each crop MUST correspond to the region of the photo where that food was reported,
  with no transposition of horizontal and vertical axes.
- **FR-009**: Rows without a usable region MUST show the existing placeholder and remain fully
  readable.
- **FR-010**: Meals saved before regions existed MUST continue to open correctly, showing
  placeholders.

### Bottom-bar clearance (US3)

- **FR-011**: On every screen that scrolls behind the bottom bar, the scrollable area MUST extend
  far enough that the final element can be brought fully into view above the bar.
- **FR-012**: Content that fits without scrolling MUST NOT be overlapped by the bar.
- **FR-013**: The bar MUST remain floating and translucent, in its current position, with content
  passing behind it while scrolling. The fix MUST NOT make it opaque, move it, or remove it.
- **FR-014**: The clearance fix MUST be verified by scrolling each affected screen to its end. A
  verification that cannot distinguish "content is inset" from "content happens to be short enough
  to fit" does NOT satisfy this requirement.
- **FR-015**: No screen may be inset twice, producing a conspicuous empty gap above the bar.

### Cross-cutting

- **FR-016**: This fix MUST NOT change saved calorie or macro values, the history list's grouping
  and ordering, or the weekly colour scale.
- **FR-017**: Meals already saved MUST remain valid and openable; no data may be invalidated.
- **FR-018**: The details screen MUST remain fully usable with no network connection.
- **FR-019**: Any new user-facing text MUST be localized in English and Spanish.
- **FR-020**: All colours MUST come from the design-system palette and remain legible in light and
  dark appearances.

### Key Entities *(include if data involved)*

- **Analysis reply**: what the analysis returns per photo — the detected foods with calories,
  macros, and now a **required** region per food. Its size and well-formedness are themselves
  requirements (FR-003, FR-004), not just its contents.
- **Food region**: where in the photo a food sits, stored proportionally. Unchanged in shape from
  feature 006; what changes is that the reply is now obliged to provide it.
- **Meal history entry**: unchanged. Still saves with correct calories whether or not regions
  arrived.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 0 photos that previously analyzed successfully fail to analyze after this fix.
- **SC-002**: 0 analyses end with a truncated or unreadable reply across a set of at least 5 varied
  food photos.
- **SC-003**: For a newly analyzed meal with multiple distinct foods, at least 80% of ingredient
  rows show a crop rather than a placeholder.
- **SC-004**: 0 crops show a region transposed between the horizontal and vertical axes, verified
  with a photo whose foods sit in clearly different corners.
- **SC-005**: On every scrollable screen, scrolling to the end leaves 100% of the final element
  visible and unobstructed — 0 cases of overlap.
- **SC-006**: 0 screens show a visible double inset above the bar.
- **SC-007**: 100% of meals saved before this fix still open and render correctly.
- **SC-008**: Every analysis failure presents an actionable message; 0 silent failures or hangs.
- **SC-009**: All affected screens are correct and legible in both languages and both appearances.

## Assumptions

- **Root cause of the analysis failure is established, not guessed.** Three variants of the same
  request were sent to the real analysis service with the same photo: with the region field
  **optional** (what feature 006 shipped) the reply ran away — it hit the output-token ceiling and
  returned tens of thousands of characters of malformed digits, unusable; **without** the region
  field it replied cleanly; with the region field **required** it also replied cleanly *and*
  returned a region for every food. Making the field optional is therefore the defect.
- **Why optional was chosen, and why that was wrong.** Feature 006 made the field optional to
  guarantee that a missing region could never block a meal from being saved. That goal is right,
  but it was pursued in the wrong place: strictness of the *request* and tolerance of the *parser*
  are independent. FR-006 now states both must hold together.
- **The region format itself is correct.** Real replies returned regions whose positions matched
  where the foods actually were in the photo, confirming the top/left interpretation already
  implemented. No coordinate change is expected.
- **Root cause of the clearance failure is understood; the exact remedy is not yet chosen.**
  Feature 006 moved the bar into a safe-area inset, but the inset does not reach the scrolling
  content of a details screen pushed inside the History tab's navigation, so the scrollable area
  still stops short. Which mechanism to use instead is a design decision for planning; FR-011 to
  FR-015 constrain the outcome rather than the technique.
- **Feature 006's verification was inadequate, and that is treated as a defect in its own right.**
  Clearance was checked with content short enough to fit on one screen, which cannot distinguish a
  working inset from content that simply ends early. FR-014 exists so the same mistake is not
  repeated.
- **The API key is correctly configured.** It is present as `GEMINI_API_KEY` and reaches the app
  through the generated Info.plist; this was verified and is **not** a cause of either symptom.
- **Existing meals will never gain crops.** Regions cannot be recovered without re-analyzing, so
  meals saved earlier show placeholders permanently. A backfill remains out of scope.
- **Region accuracy is still the model's best guess.** Loose or occasionally wrong boxes are
  acceptable; the thumbnail is a visual aid, not evidence.
- **No new external service and no schema migration.** The region field already exists on saved
  data; this fix changes how it is requested and how the layout insets, not what is stored.
