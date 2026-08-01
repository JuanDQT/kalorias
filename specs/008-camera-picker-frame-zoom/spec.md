# Feature Specification: Camera — Library Picker, Send Framing & Zoom

**Feature Branch**: `008-camera-picker-frame-zoom`

**Created**: 2026-07-26

**Status**: Draft

**Input**: User description: "Quiero que en la pantalla de la camara, haya un boton inferior izquierda que permite elegir una foto de la biblioteca para poder enviarla, como alternativa a la foto. Por otro lado, la captura de la imagen deberia tener o dibujar un recuadro de lo que se va a enviar. Ademas anadir opcion de hacer zoom a la camara."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Analyze a photo from the library (Priority: P1)

As someone who already photographed a meal, or who wants to analyze a picture taken earlier, I
want to pick an existing photo from my library instead of taking a new one, so the camera screen
is not the only way in.

The camera screen gains a button in its **bottom-left** corner. Tapping it opens the system photo
picker. Choosing a picture brings the user back to the camera screen with that picture ready to
send, in exactly the same confirmation step a freshly taken photo uses — same Send button, same
ability to back out. Cancelling the picker returns to the live camera with nothing changed.

**Why this priority**: It is the largest capability of the three, it unblocks meals whose photo was
taken outside the app, and it is independent of the other two.

**Independent Test**: Open the camera, tap the bottom-left button, choose a library photo, confirm
it appears in the same confirmation state as a captured photo, and send it for analysis
successfully.

**Acceptance Scenarios**:

1. **Given** the camera screen with a live preview, **When** the user taps the bottom-left button,
   **Then** the system photo picker opens.
2. **Given** the picker is open, **When** the user selects a photo, **Then** the camera screen
   shows that photo in the confirmation state with a Send action.
3. **Given** a library photo in the confirmation state, **When** the user sends it, **Then** it is
   analyzed and saved exactly as a captured photo would be.
4. **Given** the picker is open, **When** the user cancels, **Then** the live preview resumes with
   no photo selected and nothing sent.
5. **Given** a library photo in the confirmation state, **When** the user chooses to go back,
   **Then** the live camera resumes and the photo is discarded.
6. **Given** the camera hardware is unavailable, **When** the camera screen is shown, **Then** the
   library button is still usable — an unusable camera must not block picking a photo.
7. **Given** a picked item cannot be loaded as an image, **When** the failure occurs, **Then** a
   clear message is shown and the live preview resumes.
8. **Given** the picker has never been used before, **When** it opens, **Then** the user is not
   asked to grant access to their whole photo library.

---

### User Story 2 - See exactly what will be sent (Priority: P2)

As a user framing a meal, I want to see a frame showing precisely which part of what I see will be
sent for analysis, so the result is not based on an area I did not intend.

Today this is genuinely misleading: the live preview fills the screen by cropping, so the picture
that gets sent is **not** the same framing the user was looking at.

A frame is drawn over the preview marking a region tighter than the full screen, and the photo is
**cropped to that region** before being sent. Everything outside the frame is discarded. This gives
the user control over what the estimate is based on and keeps irrelevant background out of it.

**Why this priority**: It corrects a real mismatch between what the user sees and what the app
sends, but the app is usable today and the other two add capability rather than correcting it.

**Independent Test**: With the live preview showing, confirm a frame is drawn; take a photo, and
confirm the picture presented for confirmation matches the framed area rather than a wider or
differently-cropped view.

**Acceptance Scenarios**:

1. **Given** the live preview, **When** it is shown, **Then** a frame is drawn marking the region
   that will be sent, and the area outside it is visually de-emphasised so the distinction is
   obvious.
2. **Given** the user takes a photo, **When** the confirmation state appears, **Then** the photo
   shown is **cropped to the framed region** — the area outside the frame is not present.
3. **Given** the photo is sent, **When** it is analyzed, **Then** the analyzed picture is exactly
   the cropped region the user confirmed, with nothing from outside the frame.
4. **Given** a food item sits outside the frame, **When** the photo is analyzed, **Then** that item
   does not appear in the results — the crop is real, not cosmetic.
5. **Given** the frame is on screen, **When** the user looks at it, **Then** it is visible against
   both bright and dark scenes.
6. **Given** the frame is on screen, **When** using assistive technology, **Then** the frame's
   purpose is conveyed rather than existing only as a visual decoration.
7. **Given** a photo chosen from the library, **When** it reaches the confirmation state, **Then**
   what is shown is what will be sent (see Assumptions — library photos are not cropped).

---

### User Story 3 - Zoom the camera (Priority: P3)

As a user photographing a plate, I want to zoom in so a single dish fills the frame instead of the
whole table, making the estimate about the food I care about.

The camera screen allows zooming the live preview, and the photo that is sent reflects the zoom
that was applied.

**Why this priority**: A quality-of-life improvement that makes framing easier. The smallest of the
three, and dependent on nothing else.

**Independent Test**: Open the camera, zoom in, confirm the preview magnifies, take a photo, and
confirm the captured photo shows the zoomed framing rather than the unzoomed scene.

**Acceptance Scenarios**:

1. **Given** the live preview, **When** the user performs the zoom gesture, **Then** the preview
   magnifies smoothly.
2. **Given** the user has zoomed in, **When** a photo is taken, **Then** the photo reflects the
   zoom level shown in the preview.
3. **Given** the user zooms out past the starting point, **When** the limit is reached, **Then**
   zoom stops at the widest the device supports rather than distorting.
4. **Given** the user zooms in past the maximum, **When** the limit is reached, **Then** zoom stops
   at a level that still produces an acceptable picture rather than degrading indefinitely.
5. **Given** the user has zoomed, **When** the current level is not the default, **Then** the level
   is indicated so the user knows they are zoomed.
6. **Given** the user has zoomed and then discards the photo, **When** the live preview resumes,
   **Then** the zoom behaves predictably (see Assumptions).
7. **Given** a device with only one usable focal length, **When** the user zooms, **Then** it still
   works within that device's supported range without error.

---

### Edge Cases

- **Camera unavailable but library available**: the library button still works; the user can analyze
  a picked photo without a working camera.
- **Picker cancelled**: live preview resumes, nothing sent.
- **Picked item unloadable** (corrupt, or an unsupported format): clear message, preview resumes.
- **Picked item is very large**: it is handled without stalling the screen, and is prepared for
  sending at the same size a captured photo would be.
- **Picked item is a screenshot or a non-food picture**: the existing "no food detected" outcome
  applies unchanged.
- **Extremely wide or tall library photo**: presented and sent without distortion.
- **Zoom at the device's limits**: clamps rather than erroring or degrading.
- **Zoom while a photo is already captured**: the zoom gesture does not alter an already-taken
  photo.
- **Zoom then pick from library**: the zoom level has no bearing on a library photo.
- **Food partly inside the frame**: whatever falls outside is cropped away, so a half-visible dish is
  analyzed only as the visible part — the crop is honest, not forgiving.
- **All the food outside the frame**: the crop legitimately contains no food, and the existing "no
  food detected" outcome applies.
- **Frame at maximum zoom**: the crop still has enough resolution to analyze; it is not upscaled to
  compensate.
- **Framing frame on an unusual aspect ratio**: the frame stays consistent with what is sent.
- **Rotating the device**: the frame and the zoom remain coherent with what will be sent.
- **Returning from analysis to retake**: the screen returns to a live preview with the frame drawn.

## Requirements *(mandatory)*

### Library picker (US1)

- **FR-001**: The camera screen MUST show a control in its **bottom-left** corner that opens the
  system photo picker.
- **FR-002**: Choosing a photo MUST bring the user to the **same confirmation state** a captured
  photo uses, with the same send and back-out actions.
- **FR-003**: A sent library photo MUST be analyzed and saved by exactly the same path as a
  captured photo, producing an equivalent meal record.
- **FR-004**: Cancelling the picker MUST resume the live preview with nothing selected and nothing
  sent.
- **FR-005**: The library control MUST remain usable when the camera hardware is unavailable.
- **FR-006**: A picked item that cannot be loaded as an image MUST produce a clear, actionable
  message and return to the live preview, never a silent failure.
- **FR-007**: Picking a photo MUST NOT require the user to grant access to their entire photo
  library.
- **FR-008**: A picked photo MUST be prepared for sending at a comparable size to a captured photo,
  so analysis cost and speed do not differ materially by source.

### Send framing (US2)

- **FR-009**: The camera screen MUST draw a frame over the live preview marking the region that will
  be sent, with the area outside it visually de-emphasised.
- **FR-010**: A captured photo MUST be **cropped to the framed region** before being sent. Content
  outside the frame MUST NOT reach the analysis.
- **FR-011**: The framed region MUST correspond to the same part of the scene the user saw inside the
  frame — accounting for the preview's aspect-fill cropping, so the frame cannot indicate one area
  while a different area is cropped.
- **FR-012**: The confirmation state MUST show the cropped image, so what is confirmed is what is
  sent.
- **FR-013**: The crop MUST preserve enough resolution for analysis to remain as reliable as it is
  today; it MUST NOT be upscaled or degraded to fit a fixed size.
- **FR-014**: The frame MUST remain visible against both bright and dark scenes.
- **FR-015**: The frame's purpose MUST be conveyed to assistive technology rather than existing only
  as a visual decoration.

### Zoom (US3)

- **FR-016**: The camera screen MUST allow the user to zoom the live preview.
- **FR-017**: The photo that is sent MUST reflect the zoom applied at the time of capture.
- **FR-018**: Zoom MUST be clamped to the range the device actually supports, both at the wide and
  the magnified end, without distortion or error.
- **FR-019**: When the zoom is not at its default, the current level MUST be indicated to the user.
- **FR-020**: The zoom gesture MUST NOT alter a photo that has already been captured.
- **FR-021**: Zoom and the send frame MUST compose correctly: zooming changes what falls inside the
  frame, and the crop MUST be taken from the zoomed image, so the two features cannot disagree about
  what is sent.

### Cross-cutting

- **FR-022**: The camera screen MUST NOT become less reliable: an unusable camera, a denied
  permission, or a failed capture MUST behave as they do today.
- **FR-023**: All new user-facing text MUST be localized in English and Spanish.
- **FR-024**: All new colours MUST come from the design-system palette and remain legible in light
  and dark appearances, over a live camera image.
- **FR-025**: New controls MUST be reachable and usable with assistive technology and MUST support
  Dynamic Type where they carry text.
- **FR-026**: This feature MUST NOT change how meals are stored, the history list, the progress
  screen, or the analysis contract beyond the source and framing of the image sent.
- **FR-027**: Opening the picker, applying zoom, and preparing a picked photo MUST NOT block the
  screen; anything with observable latency MUST show a loading state.

### Key Entities *(include if data involved)*

- **Image to send**: the picture that goes to analysis, now originating from either the camera or
  the library, and now defined by the framed area rather than the full sensor frame. Downstream —
  storage, analysis, per-ingredient regions — treats both sources identically.
- **Zoom level**: the current magnification of the live camera, bounded by what the device
  supports. Transient; not persisted.
- **Send frame**: the region indicated to the user and used for what is sent. A presentation
  concept, not stored data.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can go from the camera screen to a sent library photo in under 15 seconds
  without external guidance.
- **SC-002**: 100% of sent library photos produce a meal record equivalent to one from a captured
  photo (same fields populated).
- **SC-003**: 0 occurrences of the picker requiring full photo-library access.
- **SC-004**: A captured photo is cropped to the framed region in 100% of sends — 0 sends include
  content from outside the frame.
- **SC-005**: 0 cases where the confirmation state shows a different area than what is analyzed.
- **SC-011**: With a food item deliberately placed outside the frame, it appears in 0% of results —
  confirming the crop is real rather than cosmetic.
- **SC-006**: Zoom is applied to the sent photo in 100% of zoomed captures.
- **SC-007**: 0 crashes or errors when zooming to either device limit.
- **SC-008**: An unusable camera still allows a library photo to be analyzed in 100% of attempts.
- **SC-009**: All new controls and text are correct and legible in both languages and both
  appearances, and reachable with assistive technology.
- **SC-010**: Opening the picker and preparing a picked photo never freeze the screen; any wait over
  a moment shows a loading state.

## Assumptions

- **Builds on features 001–007**: the camera screen, its capture/confirm state machine, the analysis
  flow and the meal record already exist. This feature adds a second image source, corrects the
  framing, and adds zoom.
- **The frame crops (decided during specification).** Of the two readings of "un recuadro de lo que se
  va a enviar", the chosen one is that the frame defines a **tighter region and the image is cropped
  to it**. The alternative — a frame merely marking the full captured area, cropping nothing — was
  rejected: it would fix the honesty problem but give the user no control over what the estimate is
  based on. A third option, a frame the user can drag and resize, was set aside as disproportionate
  for now; the frame is fixed, and making it adjustable would be a follow-up.
- **A real mismatch is being corrected, not invented.** The live preview currently fills the screen
  by cropping, so what the user frames is already not what gets sent. FR-010 exists because a frame
  that merely decorates a mismatched preview would make the problem worse, not better.
- **The picker is the system one**, so it exposes only the pictures the user chooses and needs no
  library-wide permission (FR-007). This also means no new permission prompt and no new usage
  description.
- **Library photos are sent as chosen**, with no in-app cropping, rotating or editing step. Only
  size preparation happens, to match a captured photo (FR-008). An editing step would be a separate
  feature.
- **Zoom applies to the live camera only.** It is not a way to crop a library photo, and it is not
  persisted between sessions.
- **Zoom resets to the default when the live preview restarts** (for example after discarding a
  photo or returning to retake), so a forgotten zoom cannot silently affect the next meal.
- **Zoom is bounded by the device**, not by an app-chosen number, so devices with different lenses
  each behave sensibly (FR-016). The magnified limit stops where picture quality would stop being
  acceptable rather than allowing unlimited digital magnification.
- **A single photo per analysis**, unchanged: the picker selects one picture, matching the existing
  one-shot flow. Multi-select and batch analysis are out of scope.
- **No change to what is stored or how**: same meal record, same per-ingredient regions, which stay
  proportional to whatever image was sent.
- **Out of scope**: front camera, flash/torch, grid overlays beyond the send frame, manual focus or
  exposure, editing picked photos, multi-photo analysis, and re-analysing existing meals.
