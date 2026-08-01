# Feature Specification: Meal History & Local Persistence

**Feature Branch**: `003-history-persistence`

**Created**: 2026-07-24

**Status**: Draft

**Input**: User description: "Podrias hacer que cada captura exitosa con sus calorias se guarden en history tab? haya una lista, izquierda pequena imagen tomada, a derecha nombre del plato tomado o ingredientes si no se puede encontrar, y debajo los datos de alimentacion. y a la derecha, la fecha tomada. con las calorias totales. cuando se haga click, se amplie en una pantalla nueva de details. toda esta informacion ha de estar persistida localmente"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Every analyzed meal is saved automatically (Priority: P1)

As someone tracking what I eat, I want each successful photo analysis to be saved
automatically, so my meals build up a history I can look back on without any extra
steps.

When a photo analysis succeeds (feature 002), the app stores a history entry
containing the captured photo, the detected foods with their calories and macros,
the computed total calories, and the date/time it was taken. The entry is kept on
the device and remains after the app is closed and reopened.

**Why this priority**: Without durable saving, there is no history to show. This
is the foundation the list and details screens read from, and it's the point of
the request ("cada captura exitosa … se guarden").

**Independent Test**: Analyze a photo successfully, fully close and relaunch the
app, and confirm the meal is still recorded (visible/countable) — proving the
data persisted locally.

**Acceptance Scenarios**:

1. **Given** a photo analysis that succeeds with a calorie total, **When** the
   result is produced, **Then** a history entry with the photo, foods, total, and
   date is saved locally.
2. **Given** a saved meal, **When** the app is force-closed and relaunched,
   **Then** the meal is still present.
3. **Given** an analysis that does not succeed (no food detected, or an error),
   **When** it ends, **Then** no history entry is created.
4. **Given** several successful analyses, **When** each completes, **Then** each
   produces its own distinct entry (no overwriting).

---

### User Story 2 - Browse the meal history list (Priority: P2)

As a user, I want the History tab to show my saved meals in a scannable list, so I
can review what I've eaten and its calories at a glance.

The History tab shows saved meals, newest first. Each row shows, on the left, a
small thumbnail of the captured photo; to its right, the meal's title (the dish
name, or the list of ingredients when no single dish name is available) with the
nutrition data below it; and on the right, the date it was taken together with the
total calories. When there are no saved meals, the tab shows a clear empty state.

**Why this priority**: The list is how the saved data becomes useful day-to-day.
It depends on US1 having stored entries.

**Independent Test**: With saved meals present, open the History tab and confirm
each meal appears as a row with thumbnail, title/ingredients, nutrition data, date,
and total calories, ordered newest first; with none present, confirm the empty
state.

**Acceptance Scenarios**:

1. **Given** saved meals, **When** the History tab is shown, **Then** each meal
   appears as a row with a thumbnail (left), title/ingredients and nutrition data
   (center), and date + total calories (right).
2. **Given** multiple saved meals, **When** the list is shown, **Then** they are
   ordered most-recent first.
3. **Given** a meal whose analysis found a single recognizable dish, **When** its
   row is shown, **Then** the title is that dish name.
4. **Given** a meal with multiple detected foods (no single dish name), **When**
   its row is shown, **Then** the title lists the ingredients.
5. **Given** no saved meals, **When** the History tab is shown, **Then** a clear
   empty state is displayed instead of a blank screen.

---

### User Story 3 - Open a meal's details (Priority: P3)

As a user, I want to tap a meal to see it in full on its own screen, so I can review
the photo larger and read the complete nutrition breakdown.

Tapping a row opens a new details screen showing the captured photo larger, the
full itemized breakdown (each food with calories and macros), the total calories,
and the date/time taken.

**Why this priority**: Details enrich the experience but the list (US2) already
delivers the core value; details build on it.

**Independent Test**: From the history list, tap a meal and confirm a new screen
opens showing the larger photo, the full food-by-food breakdown, the total, and
the date.

**Acceptance Scenarios**:

1. **Given** the history list, **When** the user taps a meal, **Then** a details
   screen for that meal opens.
2. **Given** the details screen, **When** it is shown, **Then** it displays the
   larger photo, the itemized foods with calories and macros, the total calories,
   and the date/time taken.
3. **Given** the details screen, **When** the user goes back, **Then** they return
   to the history list.

---

### Edge Cases

- **Empty history**: the tab shows an informative empty state, not a blank screen.
- **Missing/unreadable image**: if a saved photo can't be loaded, the row/details
  still render the textual data with a placeholder image rather than failing.
- **Long titles / many ingredients**: the row truncates gracefully; details show
  the full list.
- **Large history**: the list stays responsive as entries accumulate (hundreds+).
- **Storage pressure**: saving a very large photo does not block the UI; images
  are stored at a reasonable size for the thumbnail and details.
- **Same meal analyzed twice**: two separate entries are created (no dedup).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: On every successful analysis (a calorie total was produced), the app
  MUST create and persist a history entry containing: the captured photo, the
  detected foods (name, calories, and macros when available), the total calories,
  and the date/time taken.
- **FR-002**: Persistence MUST be local and on-device, and entries MUST survive app
  termination and relaunch.
- **FR-003**: A failed or no-food analysis MUST NOT create a history entry.
- **FR-004**: Each successful analysis MUST create a distinct entry; existing
  entries MUST NOT be overwritten.
- **FR-005**: The History tab MUST list saved entries ordered most-recent first.
- **FR-006**: Each list row MUST show a small photo thumbnail (left), the meal
  title and nutrition data (center), and the date taken and total calories (right).
- **FR-007**: The row title MUST be the dish name when a single recognizable dish
  is available, otherwise the list of detected ingredients.
- **FR-008**: When there are no entries, the History tab MUST show a clear empty
  state.
- **FR-009**: Tapping a row MUST open a separate details screen for that entry.
- **FR-010**: The details screen MUST show the larger photo, the full itemized
  breakdown (each food with calories and macros), the total calories, and the
  date/time taken.
- **FR-011**: Viewing history and details MUST work fully offline (no network).
- **FR-012**: Saving and image handling MUST NOT block the main thread; browsing
  the list MUST remain smooth as entries accumulate.
- **FR-013**: Each entry's displayed total MUST equal the sum of its foods'
  calories (consistent with feature 002).
- **FR-014**: All user-facing text in this flow MUST be localized in English and
  Spanish.
- **FR-015**: Stored meal data (photos and nutrition) MUST remain on the device and
  MUST NOT be transmitted anywhere as part of this feature.

### Key Entities *(include if data involved)*

- **Meal history entry**: one saved analysis — a stable identifier, the date/time
  taken, the captured photo, the list of detected foods, the total calories, and a
  derived title (dish name or ingredient list).
- **Detected food**: a food within an entry — name, calories, and optional protein
  / carbohydrate / fat amounts (as produced by feature 002).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of successful analyses appear in the History tab and remain
  after force-closing and relaunching the app.
- **SC-002**: Opening the History tab shows the list within 1 second and scrolls
  smoothly with at least 1,000 saved entries.
- **SC-003**: Each entry's shown total equals the sum of its foods' calories (0
  mismatches).
- **SC-004**: Tapping a meal opens its details screen within 1 second.
- **SC-005**: History and details are fully usable with no network connection.
- **SC-006**: A first-time user can find a previously analyzed meal and open its
  details without external guidance.

## Assumptions

- **Builds on feature 002**: the input is a successful analysis (photo + foods +
  total). This feature also gives the History tab (an empty placeholder from
  feature 001) its real content.
- **Automatic save**: every successful analysis is saved automatically; there is no
  separate "save" button or confirmation step.
- **Title derivation**: a "dish name" is used when the analysis yields a single
  recognizable food; otherwise the title is the comma-separated ingredient list.
  (A dedicated dish-name field from the analysis could be added later; for now the
  title is derived from the detected foods.)
- **Nutrition data shown per row**: the row's "datos de alimentación" are the
  entry's macros/summary (e.g. protein/carbs/fat totals); the full per-food
  breakdown lives on the details screen.
- **Delete/edit out of scope**: removing or editing saved meals is not part of this
  feature and can be added later.
- **On-device only**: no accounts, sync, export, or backup — data lives solely on
  the device (privacy by default).
- **Image sizing**: photos are stored at a reasonable size for a thumbnail and a
  details view rather than full-resolution originals, to keep storage and scrolling
  efficient.
