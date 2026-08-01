# Phase 1 Data Model: Bottom Navigation & Camera Capture

This feature has **no persisted data**. The "model" is a set of in-memory,
`@MainActor`-isolated observable state machines owned by the Router and Stores
(constitution Principle V). All types are `@Observable` reference types unless
noted.

## AppTab (enum)

Selectable content tabs. The center camera is an action, not a member here.

| Case | Meaning |
|------|---------|
| `progress` | Progress placeholder screen (default) |
| `history` | History placeholder screen |

## Router (`@Observable @MainActor`)

Owns all navigation state (Principle V — navigation via Router).

| Property | Type | Notes |
|----------|------|-------|
| `selectedTab` | `AppTab` | Defaults to `.progress` (FR-003). Persists while camera cover is presented → enables return-to-prior-tab (FR-015/FR-016). |
| `isCameraPresented` | `Bool` | Drives the camera `fullScreenCover`. |

Intents: `select(_ tab: AppTab)`, `presentCamera()`, `dismissCamera()`.

## CameraPermissionStatus (enum)

Pure mapping of `AVCaptureDevice.authorizationStatus(for: .video)`.

| Case | Source status | Behavior on camera tap |
|------|---------------|------------------------|
| `notDetermined` | `.notDetermined` | Show rationale → "Continue" triggers native prompt |
| `authorized` | `.authorized` | Open camera directly (FR-011) |
| `denied` | `.denied` | Show rationale → "Continue" opens Settings (FR-010) |
| `restricted` | `.restricted` | Show rationale → "Continue" opens Settings (FR-010) |

Derived: `canRequestNatively` = (`notDetermined`); `isPermanentlyBlocked` =
(`denied` || `restricted`); `isAuthorized` = (`authorized`).

## CameraPermissionStore (`@Observable @MainActor`)

| Property | Type | Notes |
|----------|------|-------|
| `status` | `CameraPermissionStatus` | Current authorization. |

Intents:
- `refresh()` — re-read the system status (call on appear/foreground; covers the
  "granted in Settings while rationale open" edge case).
- `requestAccess() async` — when `notDetermined`, call
  `AVCaptureDevice.requestAccess(for: .video)`, then update `status`.
- `openSettings()` — deep-link to `UIApplication.openSettingsURLString`.

State transitions:
```
notDetermined --requestAccess--> authorized | denied
denied/restricted --openSettings--> (external) --refresh--> authorized | denied
any --refresh--> re-derived from system
```

## CaptureState (enum)

Drives the capture/Send button swap.

| Case | Meaning | Center control |
|------|---------|----------------|
| `previewing` | Live rear preview, no photo taken | **Capture** button (FR-013) |
| `captured(UIImage)` | A photo was taken | **Send** button (FR-014) |
| `unavailable(message)` | No usable camera / configuration failed | Error message + dismiss (FR-017) |

## CaptureSessionStore (`@Observable @MainActor`)

Owns the `AVCaptureSession`; session work runs on a private serial queue, UI
state is updated on the main actor (Principle IV).

| Property | Type | Notes |
|----------|------|-------|
| `captureState` | `CaptureState` | Starts `previewing`, or `unavailable` if no camera. |
| `session` | `AVCaptureSession` | Exposed only to the preview layer view. |

Intents:
- `start()` — configure rear input + photo output and `startRunning()` off-main;
  set `unavailable` on failure.
- `capturePhoto()` — trigger `AVCapturePhotoOutput`; on success transition
  `previewing → captured(image)`.
- `reset()` — discard captured image, return to `previewing` (single-photo rule).
- `stop()` — `stopRunning()`; called when the cover is dismissed.

State transitions:
```
start(): (no device) --> unavailable
         (device ok)  --> previewing
previewing --capturePhoto--> captured(image)
captured --reset--> previewing
captured/previewing --dismiss(Send or cancel)--> stop() + Router.dismissCamera()
```

## Relationships

- `Router.isCameraPresented` gates presentation of `CameraCaptureView`, which
  owns a `CaptureSessionStore`.
- The camera tap flows through `CameraPermissionStore.status`: authorized →
  `Router.presentCamera()`; otherwise present `CameraPermissionView`.
- No entity references another's persisted identity; everything is transient and
  rebuilt per presentation. The captured `UIImage` is held only until the cover
  is dismissed (upload/persistence is a later feature).
