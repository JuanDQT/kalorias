# Feature Specification: Bottom Navigation & Camera Capture

**Feature Branch**: `001-bottom-nav-camera`

**Created**: 2026-07-24

**Status**: Draft

**Input**: User description: "Vamos a crear una bottombar inferior, con 3 iconos. la primera sera con un icono de progreso, estara vacia por defecto. La el boton del medio sera de una camara en color verde, y cuando se haga clic la primera vez, preguntara mediante una pantalla full screen sobre conceder permiso, si da a si, entonces preguntar al usuario nativamente, de lo contrario, ese boton mostrara esa pantalla hasta que el usuario conceda permiso. Una vez se apcete el permiso, abirrala camara trasera, y tendra un boton en el medio para tomar, y cuando le de, ese boton se cambiara por otro que diga enviar. el evento de este boton lo definimos mas adelante, de momento cerrara la camara y volvera a la anterior ui y botonera inferior. la 3ra pestana sera de historial, estara en blanco por defecto, luego la definiremos."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Navigate the app through a bottom bar (Priority: P1)

As a person using Kalorias, I want a persistent bottom bar with three
destinations so I always know where I am and can move between my progress, the
camera, and my history from anywhere in the app.

The bottom bar shows three items: a **Progress** destination on the left (a
progress icon), a prominent **Camera** action in the center (a camera icon in
the app's brand green), and a **History** destination on the right. Progress and
History are the two selectable tabs; the center camera is an action button, not
a content tab. On first launch the Progress tab is selected and shown.

**Why this priority**: The bottom bar is the app's navigational skeleton.
Without it, none of the other flows are reachable. It is the smallest slice that
puts a usable, demonstrable shell in a user's hands.

**Independent Test**: Launch the app; confirm three items appear in the bottom
bar with the center camera visually emphasized in brand green, that Progress is
shown by default, and that tapping Progress and History switches between their
(placeholder) screens while the bar stays visible.

**Acceptance Scenarios**:

1. **Given** the app is freshly launched, **When** it finishes loading, **Then**
   a bottom bar with exactly three items (Progress, Camera, History) is visible
   and the Progress screen is shown.
2. **Given** any tab is shown, **When** the user taps the History item, **Then**
   the History screen is shown and the bottom bar remains visible with History
   marked as selected.
3. **Given** the History screen is shown, **When** the user taps the Progress
   item, **Then** the Progress screen is shown again.
4. **Given** the bottom bar is visible, **When** the user views the center
   item, **Then** it is a camera icon rendered in the app's brand green and
   visually distinguished from the two side tabs.

---

### User Story 2 - Grant camera access before first capture (Priority: P2)

As a first-time user, when I tap the camera button I want a clear explanation of
why Kalorias needs my camera before the system asks, so I understand the request
and am not surprised by the OS prompt.

The first time the user taps the center camera button (and every time until
camera access is actually granted), a **full-screen permission screen** is
presented explaining why the camera is needed and offering to continue. If the
user chooses to continue, the app triggers the **native OS camera-permission
prompt**. If access is not granted, tapping the camera button again re-presents
this full-screen screen — the camera is never opened until permission is
granted.

**Why this priority**: Camera access is a hard gate for the core value of
Kalorias (photo → calories). A clear, repeatable rationale screen keeps users
from getting stuck and maximizes the chance they grant access.

**Independent Test**: With camera permission not yet granted, tap the camera
button and confirm the full-screen rationale appears; choose to continue and
confirm the native prompt appears; deny it, tap the camera button again, and
confirm the full-screen rationale reappears instead of the camera.

**Acceptance Scenarios**:

1. **Given** camera permission has never been requested, **When** the user taps
   the camera button, **Then** a full-screen permission screen explaining the
   camera need is presented.
2. **Given** the full-screen permission screen is shown, **When** the user
   chooses to continue, **Then** the native OS camera-permission prompt is
   presented.
3. **Given** the native prompt was shown and the user did not grant access,
   **When** the user taps the camera button again, **Then** the full-screen
   permission screen is presented again and the camera does not open.
4. **Given** camera access has been granted, **When** the user taps the camera
   button, **Then** the full-screen permission screen is skipped and the camera
   opens directly.
5. **Given** camera access was permanently denied at the OS level, **When** the
   user is on the full-screen permission screen and chooses to continue, **Then**
   the user is offered a way to open the system Settings to enable access.

---

### User Story 3 - Capture a photo of food (Priority: P3)

As a user with camera access granted, I want to open the rear camera, take a
photo of my food, and confirm it, so I can (later) get its calorie estimate.

Once permission is granted, tapping the camera button opens the **rear (back)
camera** full-screen with a live preview. A **capture button** sits in the
center of the controls. After the user taps it and a photo is taken, the capture
button is replaced by a **Send** button. For now, tapping Send simply closes the
camera and returns to the previously shown tab and bottom bar (the actual send
behavior is defined in a later feature).

**Why this priority**: This is the star interaction, but it depends on the shell
(US1) and the permission gate (US2) being in place first. It delivers the
"take a photo" half of the product's core loop.

**Independent Test**: With permission granted, tap the camera button, confirm
the rear camera preview appears with a centered capture button; tap capture and
confirm the button becomes a Send button; tap Send and confirm the camera closes
and the previously shown tab with the bottom bar is restored.

**Acceptance Scenarios**:

1. **Given** camera access is granted, **When** the user taps the camera button,
   **Then** the rear camera opens full-screen with a live preview and a centered
   capture button.
2. **Given** the camera preview is shown, **When** the user taps the capture
   button, **Then** a photo is captured and the capture button is replaced by a
   Send button.
3. **Given** a photo has been captured and the Send button is shown, **When** the
   user taps Send, **Then** the camera closes and the app returns to the tab that
   was shown before the camera opened, with the bottom bar visible.
4. **Given** the camera is open, **When** the user dismisses/cancels it before
   capturing, **Then** the camera closes and the previously shown tab with the
   bottom bar is restored, with no photo taken.

---

### Edge Cases

- **Permanently denied permission**: If the user selected "Don't Allow" at the
  native prompt (so it will not appear again) or disabled the camera in Settings,
  the full-screen permission screen must offer a path to the system Settings
  rather than silently doing nothing.
- **No available/usable camera** (e.g. hardware unavailable): the app surfaces a
  clear, actionable message instead of a blank preview or a crash.
- **Permission granted while the full-screen screen is open** (changed in
  Settings in the background): the next continue/attempt opens the camera rather
  than re-prompting.
- **App backgrounded during capture**: returning to the app leaves the user in a
  coherent state (either the live preview or the captured-photo state), never a
  frozen frame.
- **Rapid repeated taps** on the camera or capture button do not open multiple
  cameras or capture multiple photos.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The app MUST present a persistent bottom bar with exactly three
  items: Progress (left), Camera (center), and History (right).
- **FR-002**: Progress and History MUST be selectable tabs whose content
  replaces the main area; the center Camera MUST be an action that does not
  behave as a persistent content tab.
- **FR-003**: On first launch the Progress tab MUST be selected and shown.
- **FR-004**: The Progress tab MUST show an empty placeholder screen by default
  (its content is defined in a later feature).
- **FR-005**: The History tab MUST show an empty/blank placeholder screen by
  default (its content is defined in a later feature).
- **FR-006**: The center Camera item MUST be a camera icon rendered in the app's
  brand green and visually distinguished from the two side tabs.
- **FR-007**: When camera access is not granted, tapping the Camera button MUST
  present a full-screen permission screen explaining why the camera is needed.
- **FR-008**: From the full-screen permission screen, choosing to continue MUST
  trigger the native OS camera-permission prompt (when the OS will still show
  it).
- **FR-009**: While camera access remains not granted, tapping the Camera button
  MUST re-present the full-screen permission screen and MUST NOT open the camera.
- **FR-010**: When camera access is permanently denied at the OS level, the
  full-screen permission screen MUST offer a way to open the system Settings.
- **FR-011**: Once camera access is granted, tapping the Camera button MUST skip
  the full-screen permission screen and open the camera directly.
- **FR-012**: When the camera opens, it MUST use the rear (back) camera with a
  live preview shown full-screen.
- **FR-013**: The camera view MUST show a centered capture button while no photo
  has been taken.
- **FR-014**: After a photo is captured, the capture button MUST be replaced by a
  Send button.
- **FR-015**: Tapping Send MUST (for now) close the camera and return to the tab
  that was shown before the camera opened, with the bottom bar visible. The
  actual send/upload behavior is intentionally out of scope for this feature.
- **FR-016**: The user MUST be able to dismiss/cancel the camera before capturing;
  doing so returns to the previously shown tab with the bottom bar and takes no
  photo.
- **FR-017**: The app MUST surface a clear, actionable message when the camera is
  unavailable or cannot be opened, rather than failing silently.

### Key Entities *(include if feature involves data)*

- **Navigation selection**: which of the two content tabs (Progress / History)
  is currently shown, and which tab to restore to after the camera closes.
- **Camera permission state**: whether camera access is not-yet-requested,
  granted, denied (can re-prompt), or permanently denied (needs Settings).
- **Capture session state**: whether the camera is showing the live preview
  (capture available) or a captured photo (Send available). The captured photo
  itself is held transiently for this feature; persistence/upload is out of
  scope here.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From a cold launch, a user can reach the camera permission screen
  in a single tap on the camera button.
- **SC-002**: A user who grants access can go from tapping the camera button to a
  live rear-camera preview in under 2 seconds.
- **SC-003**: 100% of taps on the camera button while permission is not granted
  result in the full-screen permission screen (never a blank or opened camera).
- **SC-004**: After tapping Send (or cancelling), the user is returned to exactly
  the tab they were on before opening the camera in 100% of attempts.
- **SC-005**: Switching between the Progress and History tabs is perceived as
  instant (no visible loading) for the placeholder screens.
- **SC-006**: A first-time user can complete "tap camera → grant permission →
  capture a photo → return" without external guidance.

## Assumptions

- **Platform**: iOS + SwiftUI only, consistent with the project constitution;
  Android/other platforms are out of scope.
- **Center camera is an action, not a tab**: tapping it presents the permission
  screen or the camera full-screen (modally) rather than swapping in persistent
  tab content; the two selectable tabs are Progress and History.
- **Default tab**: Progress is the selected tab on launch and the default tab to
  return to after the camera closes if no other tab was previously shown.
- **Placeholder screens**: Progress and History are intentionally empty in this
  feature; their real content is specified later.
- **Send is a stub**: the Send button's real behavior (uploading the photo to
  Gemini for a calorie estimate, per the product overview) is defined in a later
  feature; here it only closes the camera and returns to the previous tab.
- **Permission rationale copy** is localized (English + Spanish) per the
  constitution, and both the permission screen and camera controls use the
  tokenized color palette and native system surfaces.
- **Single captured photo**: capturing replaces any prior in-session photo; there
  is no multi-shot gallery in this feature.
- **Camera hardware**: the target devices have a functional rear camera; the
  no-camera path is an error/edge case, not the primary flow.
