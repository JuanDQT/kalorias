# UI Contracts: Bottom Navigation & Camera Capture

This is a native SwiftUI app with no network/API surface in this feature. The
"contracts" are therefore the **store intents**, the **screen states**, and the
**accessibility identifiers** that later UI tests will rely on (constitution
Principle II — identifiers added during implementation even though UI tests are
off by default).

## Store / Router intent contracts

### Router
- `select(_ tab: AppTab)` → sets `selectedTab`; content area reflects it.
- `presentCamera()` → sets `isCameraPresented = true`.
- `dismissCamera()` → sets `isCameraPresented = false`; `selectedTab` unchanged.

### CameraPermissionStore
- `refresh()` → `status` reflects current system authorization.
- `requestAccess() async` → only meaningful when `status == .notDetermined`;
  ends in `.authorized` or `.denied`.
- `openSettings()` → opens system Settings (no state change until `refresh()`).

### CaptureSessionStore
- `start()` → `captureState` becomes `.previewing` or `.unavailable(message)`.
- `capturePhoto()` → on success `.previewing → .captured(image)`.
- `reset()` → `.captured → .previewing`.
- `stop()` → session stops (state irrelevant afterward).

## Screen state contracts

### Root shell (`RootView`)
- Always shows the bottom bar with exactly 3 items (FR-001).
- Content area shows the `selectedTab` screen; `progress` on launch (FR-003).

### Camera tap behavior (per `CameraPermissionStore.status`)
| status | Result |
|--------|--------|
| authorized | `Router.presentCamera()` → camera opens (FR-011) |
| notDetermined / denied / restricted | present `CameraPermissionView` (FR-007/FR-009) |

### Permission screen (`CameraPermissionView`)
- Full-screen; shows rationale copy.
- Primary button: "Continue" → `requestAccess()` if notDetermined, else
  `openSettings()` (FR-008/FR-010).
- On appear/foreground calls `refresh()`; if it becomes authorized, proceeds to
  the camera (edge case: granted in Settings while open).

### Camera screen (`CameraCaptureView`) by `captureState`
| captureState | Center control | Other |
|--------------|----------------|-------|
| previewing | **Capture** button | live rear preview; Cancel/dismiss available (FR-012/FR-013/FR-016) |
| captured | **Send** button | shows the still; Send → `stop()` + `Router.dismissCamera()` (FR-014/FR-015) |
| unavailable | — | clear error message + dismiss (FR-017) |

## Accessibility identifiers (stable, for future UI tests)

| Identifier | Element |
|------------|---------|
| `tab.progress` | Progress bottom-bar item |
| `tab.history` | History bottom-bar item |
| `bottomBar.cameraButton` | Center green camera action |
| `permission.screen` | Full-screen permission container |
| `permission.continueButton` | Continue / Open-Settings primary button |
| `camera.screen` | Camera capture container |
| `camera.preview` | Live preview surface |
| `camera.captureButton` | Capture button (previewing) |
| `camera.sendButton` | Send button (captured) |
| `camera.cancelButton` | Cancel/dismiss control |
| `camera.unavailableMessage` | Camera-unavailable error text |

## Localization keys (EN + ES required)

`permission.title`, `permission.body`, `permission.continue`,
`permission.openSettings`, `camera.capture`, `camera.send`, `camera.cancel`,
`camera.unavailable`, `tab.progress`, `tab.history`. Both language values must
ship in the same change (Principle VI).
