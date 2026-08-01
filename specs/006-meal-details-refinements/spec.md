# Feature Specification: Meal Details Refinements — Clearance, Colour Consistency & Ingredient Thumbnails

**Feature Branch**: `006-meal-details-refinements`

**Created**: 2026-07-26

**Status**: Draft

**Input**: User description: "En la pantalla de detalles, el color del numero de kcal deberia ser el mismo que el de la lista. Ademas, me gustaria que en los ingredientes listados, aparezca una minicaptura o thumbnail de lo que es cada cosa. Por ultimo, la bottom bar tapa los ingredientes, incluso haciendo scroll hacia abajo"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Read the whole ingredient list without the bottom bar in the way (Priority: P1)

As someone reviewing a saved meal, I want to be able to scroll to the end of the ingredient
list and actually read the last item, so the bottom navigation bar never hides data I came to
see.

On the meal details screen the floating bottom bar sits above the content. Today the content
cannot scroll far enough to clear it, so the last ingredient stays partially or fully covered
no matter how far the user scrolls. After this change, scrolling to the bottom brings the last
ingredient fully into view, clear of the bar.

**Why this priority**: This is a defect that hides information the user explicitly opened the
screen to read. A wrong colour is cosmetic; unreadable data is not. It is also the smallest and
most certain of the three changes.

**Independent Test**: Open a meal with enough ingredients to require scrolling, scroll to the
very bottom, and confirm the last ingredient row is fully visible and not overlapped by the
bottom bar.

**Acceptance Scenarios**:

1. **Given** a meal whose details do not fit on one screen, **When** the user scrolls to the
   bottom, **Then** the last ingredient row is fully visible above the bottom bar.
2. **Given** a meal with a single ingredient that fits without scrolling, **When** the details
   screen is shown, **Then** no content is overlapped by the bottom bar.
3. **Given** a meal with many ingredients, **When** the user scrolls, **Then** content passes
   behind the bar as it moves (the bar stays translucent and floating) but comes to rest clear
   of it at the end of the scroll.
4. **Given** any scrollable screen reachable behind the bottom bar, **When** it is scrolled to
   its end, **Then** its final element is fully readable.

---

### User Story 2 - The calorie total is coloured the same as in the list (Priority: P2)

As a user moving between the history list and a meal's details, I want the big calorie number
on the details screen to be the same colour it was in the list row I just tapped, so the colour
carries a consistent meaning instead of changing between screens.

In the history list, a meal's calorie figure is coloured on the green → yellow → orange → red
scale relative to the other meals in its week. On the details screen the same figure is
currently shown in the brand colour, so tapping a red row opens a green number. After this
change the details screen shows the same colour as the row.

**Why this priority**: A visible inconsistency that undermines the colour scale's meaning, but
it does not hide or misstate any number. Smaller than US3 and independent of it.

**Independent Test**: In the history list note the colour of a meal's calorie figure, tap into
its details, and confirm the large figure uses that same colour — repeated for a meal at the
low end (green) and one at the high end (red) of the same week.

**Acceptance Scenarios**:

1. **Given** a meal shown in red in the list, **When** the user opens its details, **Then** the
   large calorie figure is red.
2. **Given** a meal shown in green in the list, **When** the user opens its details, **Then**
   the large calorie figure is green.
3. **Given** two meals from the same week at opposite ends of that week's range, **When** each
   is opened, **Then** each details screen matches its own row's colour.
4. **Given** a week with a single meal, **When** its details are opened, **Then** the figure is
   green, matching the list's behaviour for a single-meal week.
5. **Given** any details screen, **When** the figure is shown in light or dark appearance,
   **Then** it remains legible against the background.
6. **Given** the calorie figure is coloured, **When** read by assistive technology, **Then** the
   number is still announced as text — the colour is never the only carrier of meaning.

---

### User Story 3 - See what each ingredient is at a glance (Priority: P3)

As a user reading a meal's breakdown, I want a small picture next to each ingredient so I can
tell at a glance what each line refers to, instead of reading names only.

Each row in the ingredient list gains a small leading image representing that ingredient.

**Why this priority**: The most valuable of the three visually, but also the largest and the
only one whose data source does not exist yet (see the clarification below). Keeping it last
means US1 and US2 ship regardless of how it is resolved.

**Independent Test**: Open a meal with several detected ingredients and confirm each row shows
a distinct leading image that plausibly corresponds to that ingredient, with a graceful
placeholder where none can be produced.

**Acceptance Scenarios**:

1. **Given** a meal with several ingredients, **When** its details are shown, **Then** each
   ingredient row displays a small leading image.
2. **Given** an ingredient for which no image can be produced, **When** its row is shown,
   **Then** a neutral placeholder appears and the row's text remains fully readable.
3. **Given** a meal saved before this feature existed, **When** its details are shown, **Then**
   every row still renders correctly, with placeholders if necessary — no blank rows, no crash.
4. **Given** ingredient images are shown, **When** read by assistive technology, **Then** the
   ingredient name and calories are still announced; the image adds no essential information.
5. **Given** a meal with many ingredients, **When** the list is scrolled, **Then** scrolling
   stays smooth.
6. **Given** the details screen is opened without a network connection, **When** it renders,
   **Then** it still works. *(This constrains how FR-013 may be resolved.)*

Each thumbnail is a **crop of the meal's own photo**, taken from the region of the photo where
that ingredient was detected. The analysis is asked to report where in the image each food sits,
that region is saved with the food, and the details screen crops the stored photo to it.

Meals saved before this feature have no recorded regions, so their rows show the neutral
placeholder instead — permanently, since the regions cannot be recovered without re-analyzing.

---

### Edge Cases

- **Meal with one ingredient**: details fit without scrolling; nothing is overlapped.
- **Meal with many ingredients**: the list scrolls fully clear of the bottom bar.
- **Very long ingredient name**: the row wraps or truncates gracefully without pushing the
  calorie figure off-screen or colliding with the leading image.
- **Meal whose photo is missing or unreadable**: the header photo already falls back to a
  placeholder; ingredient rows must degrade the same way rather than failing — with no photo there
  is nothing to crop.
- **Meals saved before this feature**: render placeholders, permanently, since no regions were
  recorded.
- **Analysis returns regions for only some foods**: those foods get crops, the rest get
  placeholders, in the same list.
- **Analysis returns no regions at all**: the meal still saves normally with its calories and
  macros; every row shows a placeholder.
- **Region that is degenerate or out of bounds** (zero width/height, negative, or extending past
  the image edge): treated as no region → placeholder, never a stretched or empty crop.
- **Two ingredients whose regions overlap heavily**: both crops render; they may look similar,
  which is acceptable — the name remains the authoritative label.
- **A region covering nearly the whole photo**: the crop is effectively the whole meal; acceptable,
  and still preferable to a placeholder.
- **Ingredient with no macro data**: the row shows name, calories and image without an empty
  macro strip.
- **Large Dynamic Type sizes**: the image does not squeeze the text into illegibility; rows
  grow instead of clipping.
- **A week where all meals share the same total**: the details figure is green, matching the
  list.
- **Details opened for the only meal ever saved**: green figure, and the screen scrolls clear.

## Requirements *(mandatory)*

### Functional Requirements

#### Bottom-bar clearance (US1)

- **FR-001**: The meal details screen MUST allow its content to scroll far enough that the last
  element is fully visible above the floating bottom bar.
- **FR-002**: Content that fits without scrolling MUST NOT be overlapped by the bottom bar.
- **FR-003**: The bottom bar MUST remain floating and translucent — the fix MUST NOT be achieved
  by making it opaque or by removing it.
- **FR-004**: Any other scrollable screen that sits behind the bottom bar MUST likewise be able
  to scroll its final element fully into view.

#### Calorie colour consistency (US2)

- **FR-005**: The meal details screen's calorie figure MUST use the same colour step as that
  meal's figure in the history list.
- **FR-006**: That colour MUST be derived from the same relative scale the list uses — a meal's
  position between the lowest and highest totals of its own week — so the two screens cannot
  disagree.
- **FR-007**: The colour MUST come from the design-system palette and MUST remain legible in
  both light and dark appearances.
- **FR-008**: The calorie number MUST remain readable as text so the colour is never the sole
  carrier of information.

#### Ingredient thumbnails (US3)

- **FR-009**: Each ingredient row in the details breakdown MUST display a small leading image
  representing that ingredient.
- **FR-010**: When no image can be produced for an ingredient, the row MUST show a neutral
  placeholder and remain fully readable.
- **FR-011**: Meals saved before this feature MUST continue to render correctly, using
  placeholders where per-ingredient images are unavailable.
- **FR-012**: Ingredient images MUST NOT prevent the row's name, calories or macros from being
  read, at any supported Dynamic Type size.
- **FR-013**: Each ingredient's image MUST be a crop of that meal's own stored photo, taken from
  the region of the image where the ingredient was detected.
- **FR-014**: The analysis MUST be asked to report, for each detected food, the region of the
  image it occupies, and that region MUST be saved alongside the food so the crop can be produced
  later without re-analyzing.
- **FR-015**: A reported region that is missing, malformed, or falls outside the image MUST be
  treated as "no region" and yield the placeholder — it MUST NOT produce a distorted crop, an
  empty image, or a crash.
- **FR-016**: Cropping MUST work entirely from data already on the device, so the details screen
  remains fully functional with no network connection.
- **FR-017**: Adding regions MUST be additive: meals saved without them MUST remain valid and
  openable, and no existing calorie or macro value may change.
- **FR-018**: Displaying ingredient images MUST NOT make the details screen slower to open or
  less smooth to scroll than it is today, and image work MUST NOT block the screen from
  appearing.

#### Cross-cutting

- **FR-019**: All user-facing text added by this feature MUST be localized in English and
  Spanish.
- **FR-020**: This feature MUST NOT change which meals are saved, their calorie or macro values,
  or the history list's own behaviour. The only change to the analysis flow is the additive
  per-food region required by FR-014.
- **FR-021**: If the analysis fails to return regions, or returns them for only some foods, the
  meal MUST still be saved with its calories and macros exactly as it is today — regions are an
  enhancement and MUST NOT become a condition for saving a meal.
- **FR-022**: All images shown MUST have an accessibility treatment appropriate to their role —
  decorative images hidden from assistive technology, informative ones labelled.

### Key Entities *(include if data involved)*

- **Meal history entry**: unchanged in substance — the saved meal with its photo, detected
  foods, total calories and date. This feature reads its total (for the colour) and its foods
  (for the rows).
- **Detected food / ingredient**: a food within a meal — name, calories, optional macros, and
  now an **optional image region**: where in the meal's photo this food was found, expressed
  independently of the photo's pixel size so it survives the photo being stored at a different
  scale. Optional by design — meals saved before this feature have none, and a failed or partial
  analysis may still omit it.
- **Calorie colour step**: the existing four-step scale position (green → yellow → orange →
  red) computed from a meal's total relative to its week. Currently used only by the list; this
  feature makes the details screen use the same value.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On any meal, scrolling to the bottom leaves 100% of the last ingredient row
  visible and unobstructed (0 cases of overlap).
- **SC-002**: For any meal, the calorie colour on the details screen matches the colour on its
  list row (0 mismatches across a week's meals).
- **SC-003**: Every ingredient row displays either an image or a deliberate placeholder — 0 rows
  render blank or broken.
- **SC-004**: 100% of meals saved before this feature still open and render correctly, showing
  placeholders rather than failing.
- **SC-005**: The details screen opens within 1 second and scrolls smoothly for a meal with at
  least 15 ingredients.
- **SC-006**: The details screen is fully usable with no network connection.
- **SC-007**: For newly analyzed meals, a thumbnail appears for the majority of detected
  ingredients, and 0 ingredients render a distorted, empty or broken crop.
- **SC-008**: An analysis that returns no regions still results in a fully saved meal with correct
  calories and macros (0 meals lost or altered because regions were unavailable).
- **SC-009**: All text, colours and images are correct and legible in both English and Spanish
  and in both light and dark appearance (0 illegible or untranslated elements).
- **SC-010**: A user can identify what each ingredient row refers to without reading its name,
  in the cases where a meaningful image is available.

## Assumptions

- **Builds on features 003 and 004**: the details screen, the saved meal data, and the four-step
  relative calorie scale already exist. This feature changes presentation, plus whatever
  additive data FR-013's resolution requires.
- **US1 is a defect fix, not a redesign.** The bottom bar stays where it is and stays
  translucent; only the scrollable content's bottom inset changes. Hiding the bar entirely while
  viewing details would also solve the symptom but is a navigation change and is out of scope.
- **The clearance problem is probably not unique to this screen.** The bottom bar is drawn over
  whatever the selected tab renders, so any screen with content near the bottom is a candidate.
  FR-004 covers this deliberately; the history list should be checked as part of the work.
- **The colour must come from the same computation as the list, not a re-derivation.** The list
  colours a meal relative to its own week's lowest and highest totals. Any independent
  calculation on the details screen risks drifting from the list's answer, so the two must share
  one source of truth.
- **A consequence worth stating**: because the scale is relative to the week, a meal's colour can
  change over time as other meals are added to that week. The details screen will show whatever
  the list currently shows, which is the consistency the user asked for.
- **Thumbnails are crops of the user's own photo** (decided during specification). The
  alternatives — generic category icons keyed off the food name, or a third-party image lookup —
  were rejected: the first is not a picture of the user's food, and the second would add a
  networked external service, which the constitution restricts and which would break the offline
  requirement (SC-006).
- **Already-saved meals will never show crops.** Regions cannot be reconstructed after the fact
  without re-analyzing the photo, so every meal saved before this feature permanently shows
  placeholders. This is accepted rather than mitigated; a backfill (re-analyzing old photos) would
  spend network and quota on data the user already has and is out of scope.
- **Region accuracy is the analysis's best guess, not ground truth.** The model may place a box
  loosely, overlap two foods, or omit one. The feature is designed to degrade to a placeholder
  rather than to insist on a crop, and a slightly loose crop is treated as acceptable — the
  thumbnail is a visual aid, not evidence.
- **Regions are stored proportionally**, not in pixels, so they stay correct even though the photo
  is saved at a reduced size (feature 003 stores a downsized JPEG rather than the original).
- **No new external service**: the app's only approved external service remains the calorie
  analysis, and meal data stays on the device.
- **Editing and deleting remain out of scope**, as in feature 003.
- **The header photo is unchanged**: this feature does not alter the large meal photo, the date
  line, or the total's label.
