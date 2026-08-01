# Implementation Plan: Bottom Navigation & Camera Capture

**Branch**: `001-bottom-nav-camera` | **Date**: 2026-07-24 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-bottom-nav-camera/spec.md`

## Summary

Deliver the app's navigational shell and its camera-capture entry point: a
persistent bottom bar with two content tabs (Progress, History — both empty
placeholders for now) and a prominent green center **Camera** action. Tapping
the camera gates on camera permission through a full-screen rationale screen
that drives the native OS prompt and repeats until access is granted, then opens
the rear camera full-screen with a capture button that becomes a **Send** button
after a shot (Send currently just closes the camera and returns to the prior
tab; real upload-to-Gemini is a later feature).

Technical approach: native SwiftUI + AVFoundation on iOS 26, following the
constitution's MV + Stores + Router architecture. A `Router` owns the selected
tab and the camera full-screen presentation; a `CameraPermissionStore` owns the
authorization state machine; a `CaptureSessionStore` owns the AVFoundation
session and capture-state machine (session work off the main thread, UI state on
`@MainActor`). The bottom bar and permission surfaces use Apple's **native
Liquid Glass** (`.glassEffect` / `GlassEffectContainer`) and system materials,
with all color from the tokenized `AppColor` palette. No persistence and no
network in this feature.

## Technical Context

**Language/Version**: Swift 6 (language mode, `SWIFT_STRICT_CONCURRENCY = complete`)

**Primary Dependencies**: SwiftUI, Observation, AVFoundation (`AVCaptureSession`,
`AVCapturePhotoOutput`, `AVCaptureVideoPreviewLayer`), UIKit interop
(`UIViewRepresentable` for the preview layer), `UIApplication.openSettingsURLString`
for the Settings deep link. No third-party packages. Gemini is **not** used in
this feature (Send is a stub).

**Storage**: N/A. The captured photo is held transiently in memory by
`CaptureSessionStore`; nothing is persisted.

**Testing**: XCTest unit tests (a `KaloriasTests` unit-test target must be
added — none exists yet). UI tests (XCUITest) are OFF by default per constitution
Principle II and are not part of this feature; accessibility identifiers are
still added so flows are UI-testable later.

**Target Platform**: iOS 26.5+ (Liquid Glass, deployment target already 26.5).

**Project Type**: Native iOS mobile app (single SwiftUI app target, filesystem-
synchronized Xcode groups — new files are picked up automatically).

**Performance Goals**: Cold launch < 2s to first interactive frame; tab switches
perceived instant; camera button → live rear preview < 2s (SC-002); sustained
60fps preview.

**Constraints**: AVFoundation session configuration and start MUST run off the
main thread (Principle IV); native Liquid Glass only, no imitations (Principle
III); all colors from `AppColor` tokens; every user-facing string localized
EN+ES; correct in light and dark (Principle VI); no force-unwraps outside tests.

**Scale/Scope**: ~5 screens/surfaces (root shell + bottom bar, Progress
placeholder, History placeholder, full-screen permission rationale, camera
capture), 2 stores + 1 router, ~17 functional requirements. Small.

## Constitution Check

*GATE: evaluated against Kalorias Constitution v1.1.0. Must pass before Phase 0
and re-checked after Phase 1.*

| Principle | Gate | Status |
|-----------|------|--------|
| I. Code Quality | Zero warnings; no force-unwrap/cast/try outside tests; camera/permission/navigation logic lives in Stores/Router, not view bodies. No nutrition math in this feature. | ✅ Pass — logic placed in `CameraPermissionStore` / `CaptureSessionStore` / `Router`. |
| II. Testing (NON-NEG) | Unit tests for the testable state machines (permission status mapping, capture-state transitions, return-tab logic) written alongside implementation. UI tests off by default; accessibility identifiers added for later. | ✅ Pass — see contracts/ui-contracts.md + data-model.md; no UI-test tasks planned. |
| III. UX Consistency | HIG; native Liquid Glass for bottom bar + surfaces; system materials where fitting; brand-green camera via `AppColor.brandPrimary`; loading/error state for camera-unavailable; Dynamic Type + VoiceOver + a11y ids. | ✅ Pass — bottom bar/permission built on `.glassEffect`/`GlassEffectContainer`; error path in FR-017. |
| IV. Performance | Session config/start off main thread; preview 60fps; camera open < 2s. | ✅ Pass — dedicated session queue; `@MainActor` only for UI state. |
| V. Architecture (NON-NEG) | Swift 6 strict concurrency; MV + Stores + Router; no MVVM; navigation via Router. | ✅ Pass — `Router` (nav), `CameraPermissionStore` + `CaptureSessionStore` (state); views thin. |
| VI. Localization & Appearance (NON-NEG) | All strings in `Localizable.xcstrings` EN+ES; Dark Mode; tokenized colors. | ✅ Pass — strings catalog to be added; colors from `AppColor`. |
| Tech Constraints | iOS + SwiftUI only; Apple frameworks; no Gemini/network here. | ✅ Pass. |

**Result**: All gates pass. No violations → Complexity Tracking is empty.

## Project Structure

### Documentation (this feature)

```text
specs/001-bottom-nav-camera/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── ui-contracts.md  # Phase 1 output (store intents + accessibility ids + screen states)
├── checklists/
│   └── requirements.md  # From /speckit-specify
└── tasks.md             # /speckit-tasks output (NOT created here)
```

### Source Code (repository root)

```text
Kalorias/                          # app target (filesystem-synchronized group)
├── KaloriasApp.swift              # @main; injects Router + Stores into the environment
├── App/
│   ├── RootView.swift             # shell: current tab content + custom bottom bar + camera fullScreenCover
│   ├── Router.swift               # @Observable @MainActor: selectedTab, isCameraPresented
│   └── AppTab.swift               # enum AppTab { progress, history }
├── Features/
│   ├── Progress/
│   │   └── ProgressPlaceholderView.swift
│   ├── History/
│   │   └── HistoryPlaceholderView.swift
│   └── Camera/
│       ├── CameraPermissionStore.swift    # @Observable @MainActor: authorization state machine
│       ├── CameraPermissionView.swift      # full-screen rationale (continue / open Settings)
│       ├── CaptureSessionStore.swift       # @Observable @MainActor: AVCaptureSession owner + capture state
│       ├── CameraCaptureView.swift         # full-screen preview + capture/Send controls + error state
│       └── CameraPreviewLayerView.swift    # UIViewRepresentable wrapping AVCaptureVideoPreviewLayer
├── DesignSystem/
│   ├── AppColor.swift             # existing color tokens
│   └── BottomBar.swift            # native Liquid Glass bottom bar + prominent green camera button (shared helper)
├── Resources/
│   └── Localizable.xcstrings      # EN + ES strings (new)
└── Assets.xcassets/…              # existing palette

KaloriasTests/                     # new unit-test target
├── CameraPermissionStoreTests.swift
├── CaptureSessionStateTests.swift
└── RouterTests.swift
```

**Structure Decision**: Single native iOS app target using SwiftUI, organized by
`App/` (shell + navigation), `Features/<Area>/` (per-screen views and their
Stores), and `DesignSystem/` (shared tokens + the native-glass bottom bar
helper). This matches the constitution's MV + Stores + Router split and keeps the
camera stack isolated. A new `KaloriasTests` XCTest target hosts the unit tests
for the state machines. `Info.plist` camera usage description is provided via the
`INFOPLIST_KEY_NSCameraUsageDescription` build setting (localized).

## Complexity Tracking

> No constitution violations. Section intentionally empty.
