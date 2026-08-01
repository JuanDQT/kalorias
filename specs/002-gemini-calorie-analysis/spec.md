# Feature Specification: Photo Calorie Analysis

**Feature Branch**: `002-gemini-calorie-analysis`

**Created**: 2026-07-24

**Status**: Draft

**Input**: User description: "Me gustaria que cuando se envie la foto, se nevia al a api de gemini para procesar y te diga las calorias, en formato json bien formado que tu lo puedas entender, y despues la app te diga el total que tiene"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See the calorie total for a food photo (Priority: P1)

As someone tracking what I eat, after I take a photo of my food and tap **Send**,
I want the app to analyze the photo and show me the **total calories** it
contains, so I get an instant estimate without weighing or looking anything up.

When the user taps Send on a captured photo, the app submits the photo to the
calorie-analysis service. While it works, the app shows a clear loading state.
When the analysis returns, the app shows the **total estimated calories** for the
whole photo, prominently, with its unit (kcal). The result comes from a
structured response the app parses reliably; the total shown is the sum of every
food the service detected.

**Why this priority**: This is the core value of Kalorias and the payoff of the
whole photo flow — a photo in, a calorie total out. Everything else builds on it.

**Independent Test**: Capture a photo of a plate of food, tap Send, and confirm a
loading state appears and is then replaced by a single, clearly labeled total
calorie figure that reflects the food in the photo.

**Acceptance Scenarios**:

1. **Given** a captured photo, **When** the user taps Send, **Then** a loading
   state is shown while the photo is analyzed.
2. **Given** the analysis succeeds, **When** the result is ready, **Then** the
   total estimated calories are shown prominently with a unit (e.g. "620 kcal").
3. **Given** a successful result with several detected foods, **When** the total
   is shown, **Then** the total equals the sum of the individual foods' calories.
4. **Given** the result is shown, **When** the user dismisses it, **Then** the app
   returns to the main screen with the bottom bar.

---

### User Story 2 - See what foods were detected (Priority: P2)

As a user who wants to trust the number, I want to see the **list of foods** the
analysis detected and how many calories each contributes, so I can sanity-check
the total and understand where it came from.

Alongside the total, the app shows an itemized breakdown: each detected food with
its name and estimated calories (and, when available, its protein / carbohydrate /
fat amounts).

**Why this priority**: The breakdown builds trust and usefulness, but the app is
already valuable with just the total (US1), so this is secondary.

**Independent Test**: With a photo containing more than one food, confirm the
result shows each detected food with its own calorie figure, and that the listed
items add up to the displayed total.

**Acceptance Scenarios**:

1. **Given** a successful analysis, **When** the result is shown, **Then** each
   detected food is listed with its name and estimated calories.
2. **Given** macro amounts are available for a food, **When** it is listed,
   **Then** its protein, carbohydrate, and fat amounts are shown.
3. **Given** the itemized list is shown, **When** the user reads it, **Then** the
   items' calories sum to the displayed total (US1 SC).

---

### User Story 3 - Recover when analysis can't be completed (Priority: P3)

As a user, when the analysis can't be completed — no connection, a timeout, a
service error, no food recognized, or an unusable response — I want a clear
message and the ability to retry or cancel, so I'm never stuck on a spinner or
shown a wrong number.

**Why this priority**: Networked AI analysis is fallible (per the product
overview); handling failure well protects trust, but it only matters once the
success path (US1) exists.

**Independent Test**: Trigger each failure condition (e.g. disable the network)
and confirm the app shows a clear, specific message with retry/cancel instead of
hanging or showing a fabricated total.

**Acceptance Scenarios**:

1. **Given** there is no network connection, **When** the user taps Send, **Then**
   a clear "no connection" message is shown with the option to retry or cancel.
2. **Given** the analysis takes too long, **When** the timeout is reached, **Then**
   a timeout message is shown with retry/cancel and no partial/false total.
3. **Given** the service reports an error or returns a response the app cannot
   understand, **When** that happens, **Then** a generic "couldn't analyze"
   message is shown with retry/cancel, and no calorie number is displayed.
4. **Given** no food is recognized in the photo, **When** the result returns,
   **Then** the app tells the user no food was detected and offers to retake or
   cancel, rather than showing 0 kcal as if it were a real meal.
5. **Given** an error message with a Retry action, **When** the user taps Retry,
   **Then** the same photo is analyzed again.

---

### Edge Cases

- **Empty / non-food photo** (wall, person, blank): handled as "no food detected"
  (US3 AS4), not a 0-calorie meal.
- **Partial response**: a response missing the total but listing items — the app
  derives the total from the items; a response missing both is treated as
  unusable (US3 AS3).
- **Extremely large or implausible values**: the app still displays what was
  returned but must not crash or misformat; sanity limits are a later concern.
- **User leaves during analysis**: if the user dismisses/cancels while analysis is
  in flight, the in-flight work is abandoned and no result is forced onto a later
  screen.
- **Slow network**: the loading state must remain responsive and cancellable; the
  main UI never freezes.
- **Repeated Send taps**: a single analysis runs per captured photo; rapid taps do
  not launch multiple concurrent analyses.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: When the user taps Send on a captured photo, the app MUST submit the
  photo to the calorie-analysis service for processing.
- **FR-002**: While analysis is in progress, the app MUST show a loading state and
  MUST allow the user to cancel it.
- **FR-003**: The app MUST request and consume a **structured** result (a
  well-formed, schema-conformant payload) and MUST NOT rely on free-form text.
- **FR-004**: The app MUST validate the structured result; any response that does
  not conform to the expected schema MUST be treated as an analysis failure
  (FR-011), never shown as a calorie total.
- **FR-005**: On success, the app MUST display the **total estimated calories**
  for the photo prominently, with a unit.
- **FR-006**: The displayed total MUST equal the sum of the individual detected
  foods' calories.
- **FR-007**: The app MUST display an itemized breakdown of detected foods, each
  with a name and estimated calories.
- **FR-008**: When the service provides them, the app MUST display each food's
  protein, carbohydrate, and fat amounts.
- **FR-009**: The calorie total and any aggregation MUST be computed in dedicated,
  testable logic (not inside view code), per the project constitution.
- **FR-010**: All analysis work MUST run off the main thread so the UI never
  freezes; the user MUST be able to interact with the loading/cancel controls
  throughout.
- **FR-011**: On any failure (no connection, timeout, service error, unusable
  response), the app MUST show a clear, specific, actionable message with **Retry**
  and **Cancel**, and MUST NOT display a fabricated or partial calorie total.
- **FR-012**: When no food is recognized, the app MUST communicate that distinctly
  (not as 0 kcal) and offer to retake or cancel.
- **FR-013**: Retry MUST re-analyze the same captured photo.
- **FR-014**: Only one analysis MUST run at a time per captured photo; repeated
  Send taps MUST NOT start concurrent analyses.
- **FR-015**: Dismissing the result or cancelling MUST return the user to the main
  screen with the bottom bar; abandoning an in-flight analysis MUST discard it.
- **FR-016**: All user-facing text in this flow (loading, result labels, errors)
  MUST be localized in English and Spanish.

### Key Entities *(include if data involved)*

- **Food photo**: the image captured in the camera flow, submitted for analysis;
  held transiently for the duration of the request.
- **Calorie analysis**: the structured result — a total calorie figure plus the
  list of detected foods; also carries a status (success / no-food / failure).
- **Detected food**: one recognized food item — name, estimated calories, and
  optional protein / carbohydrate / fat amounts.
- **Analysis failure**: the reason an analysis could not produce a total —
  no-connection, timeout, service-error, unusable-response, or no-food — used to
  choose the message and available actions.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After tapping Send, 90% of analyses of a typical single-plate photo
  return a calorie total within 10 seconds.
- **SC-002**: The displayed total always equals the sum of the listed foods'
  calories (0 mismatches).
- **SC-003**: 100% of failed or unusable analyses result in a clear message with
  Retry/Cancel — never a spinner that hangs or a fabricated number.
- **SC-004**: Photos with no recognizable food are reported as "no food detected"
  rather than "0 kcal" in 100% of cases.
- **SC-005**: A first-time user can go from tapping Send to reading their total
  without any external guidance.
- **SC-006**: The main UI remains responsive (no freeze) throughout analysis,
  including on a slow connection.

## Assumptions

- **Continuation of feature 001**: this feature defines the behavior of the
  **Send** button that feature 001 (Bottom Navigation & Camera Capture) left as a
  stub; the capture flow and its photo are the input here.
- **Service**: the calorie-analysis service is **Google Gemini**, the approved
  external dependency named in the project constitution; it is asked to return a
  structured (JSON) result the app can parse deterministically.
- **Primary output is the total**: the headline result is the total calories for
  the whole photo; the itemized breakdown (US2) and macros are supporting detail.
- **No persistence in this feature**: showing the result does not save it to
  Progress or History — those tabs remain later features. The analysis and its
  result are transient for now.
- **One photo at a time**: analysis operates on the single most recently captured
  photo; batch/multi-photo analysis is out of scope.
- **Estimates**: calorie and macro values are model estimates, not exact
  measurements, and are presented as such.
- **Credentials**: any API key/credentials for the service are configured out of
  band and are never committed to the repository (per the constitution).
