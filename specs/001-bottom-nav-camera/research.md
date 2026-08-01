# Phase 0 Research: Bottom Navigation & Camera Capture

All Technical Context items were resolvable from the constitution and standard
Apple frameworks; there are no open `NEEDS CLARIFICATION` items. The decisions
below lock the technical approach.

## R1. Bottom bar with a center action (not a tab)

- **Decision**: Build a **custom bottom bar** as a shared helper
  (`DesignSystem/BottomBar.swift`) using Apple's native Liquid Glass
  (`GlassEffectContainer` + `.glassEffect(...)`). It hosts two selectable
  segments (Progress, History) and a prominent circular **Camera** action in the
  center rendered in `AppColor.brandPrimary`. `RootView` swaps the tab content
  above the bar and presents the camera as a `fullScreenCover`.
- **Rationale**: The spec requires the center item to be an *action*, not a
  persistent content tab, and to be visually prominent and green — which the
  standard `TabView`/`Tab` model does not express. A custom bar built on the
  **native** glass APIs satisfies both the spec and constitution Principle III
  ("native Liquid Glass, no imitations"; surfaces drawn through a shared helper).
- **Alternatives considered**: (a) `TabView` with 2 tabs + a floating overlay
  button — rejected: overlay hit-testing over the native tab bar is fiddly and
  the button wouldn't feel part of the bar. (b) Hand-rolled blur+gradient bar —
  rejected: forbidden imitation of Liquid Glass.

## R2. Camera permission state machine

- **Decision**: Model permission with `AVCaptureDevice.authorizationStatus(for:
  .video)` mapped to `notDetermined | authorized | denied | restricted`.
  `CameraPermissionStore` exposes `refresh()` (re-reads status, e.g. on
  foreground) and `requestAccess()` (calls `AVCaptureDevice.requestAccess`).
  Tapping the camera routes through the store: `authorized` → open camera;
  anything else → present `CameraPermissionView`. From that screen, "Continue"
  calls `requestAccess()` when `notDetermined`; when `denied`/`restricted`
  (permanent) it deep-links to Settings via `UIApplication.openSettingsURLString`.
- **Rationale**: Directly satisfies FR-007…FR-011 and the permanently-denied
  edge case. Keeping the mapping pure makes it unit-testable without a device.
- **Alternatives considered**: Requesting access immediately on first tap without
  a rationale screen — rejected: the spec mandates the full-screen rationale
  before the native prompt.

## R3. Capture session & preview

- **Decision**: `CaptureSessionStore` owns an `AVCaptureSession` with the rear
  `AVCaptureDevice` (`.builtInWideAngleCamera`, `.back`) input and an
  `AVCapturePhotoOutput`. All `configure()`/`startRunning()`/`stopRunning()` work
  runs on a dedicated serial `DispatchQueue` (never the main thread); observable
  UI state (`captureState`, `capturedImage`, `errorMessage`) is mutated back on
  `@MainActor`. The preview is a `UIViewRepresentable`
  (`CameraPreviewLayerView`) wrapping `AVCaptureVideoPreviewLayer`.
- **Rationale**: Standard, robust AVFoundation pattern; honors Principle IV
  (session work off the main thread, 60fps preview). Photo capture output feeds
  the capture-state transition (idle → captured) that flips the button to Send.
- **Alternatives considered**: `UIImagePickerController` (`.camera`) — rejected:
  no control over the custom capture→Send button swap the spec requires, and
  weaker styling control. `PhotosPicker`/`AVCaptureVideoDataOutput` — rejected:
  wrong tool (library picker / raw frame processing) for a single still capture.

## R4. Navigation & return-to-previous-tab

- **Decision**: `Router` (`@Observable @MainActor`) holds `selectedTab: AppTab`
  and `isCameraPresented: Bool`. The camera is a `fullScreenCover(isPresented:)`.
  Because the selected tab persists while the cover is up, dismissing the cover
  (Send or cancel) returns to exactly the prior tab with no extra bookkeeping.
- **Rationale**: Satisfies FR-015/FR-016 and SC-004 with the simplest correct
  mechanism; navigation state lives in the Router per Principle V.
- **Alternatives considered**: Manually snapshotting/restoring the tab — rejected
  as unnecessary; SwiftUI already preserves it behind the cover.

## R5. Localization & Info.plist

- **Decision**: Add `Resources/Localizable.xcstrings` with EN + ES for all
  permission copy, button titles ("Continue", "Open Settings", "Send"), and the
  camera-unavailable error. Provide the camera usage description via the
  `INFOPLIST_KEY_NSCameraUsageDescription` build setting (localized), since the
  project uses a generated Info.plist.
- **Rationale**: Principle VI requires EN+ES for every user-facing string; iOS
  requires `NSCameraUsageDescription` before `requestAccess`, or the app crashes.
- **Alternatives considered**: Hardcoded strings — rejected (violates VI).

## R6. Camera unavailability / simulator

- **Decision**: When no usable rear device exists (e.g. Simulator, hardware
  fault), `CaptureSessionStore` sets `errorMessage` and `CameraCaptureView` shows
  a clear, actionable message with a way to dismiss — never a blank/frozen frame
  (FR-017, edge case).
- **Rationale**: The iOS Simulator has no camera, so this path is also what makes
  the flow demoable there; capture itself is validated on a real device.
- **Alternatives considered**: Assuming a camera always exists — rejected;
  violates FR-017 and crashes/blanks on Simulator.

## Resolved unknowns

None outstanding. Proceed to Phase 1.
