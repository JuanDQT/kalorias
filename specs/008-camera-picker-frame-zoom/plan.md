# Implementation Plan: Camera — Library Picker, Send Framing & Zoom

**Branch**: `008-camera-picker-frame-zoom` | **Date**: 2026-07-26 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/008-camera-picker-frame-zoom/spec.md`

## Summary

Three additions to the camera screen:

1. **Library picker (US1)** — a bottom-left control opens SwiftUI's `PhotosPicker`. The chosen image
   enters the **existing** `.captured` state, so it reaches Send, analysis and storage through the
   path a captured photo already uses. No permission prompt is involved.
2. **Send framing (US2)** — a centred square frame is drawn over the preview, the area outside is
   dimmed, and a captured photo is **cropped to it** before it becomes `.captured`. Because the crop
   happens *before* entering that state, everything downstream — confirmation, analysis, storage,
   per-ingredient regions — needs no change and automatically agrees about what was sent.
3. **Zoom (US3)** — a pinch gesture drives the capture device's zoom factor, clamped to a supported
   range, with an indicator when it is not at the default.

Two findings make this smaller than it looks (see [research.md](./research.md)):

- **The frame→crop mapping must not be hand-rolled.** `AVCaptureVideoPreviewLayer` provides
  `metadataOutputRectConverted(fromLayerRect:)`, which converts a layer rect into normalized image
  coordinates *accounting for aspect-fill cropping and orientation* — exactly the two transforms the
  spec's checklist flagged as most likely to be got subtly wrong.
- **The crop itself already exists and is already tested.** Features 006/007 left `FoodRegion` (a
  validated unit rect) and an orientation-safe unit-rect crop with a test that catches
  `cgImage.cropping`. The send crop reuses both rather than adding a second implementation.

## Technical Context

**Language/Version**: Swift 6 (strict concurrency `complete`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).

**Primary Dependencies**: SwiftUI, **PhotosUI** (`PhotosPicker` — new to the project, an Apple
framework, needs no third-party justification and **no permission**), AVFoundation (existing session,
plus `videoZoomFactor` and `metadataOutputRectConverted`), UIKit (existing crop). Reuses `FoodRegion`
and the existing orientation-safe crop.

**Storage**: No change. No new field, no migration. The meal record is identical; only the pixels
sent differ.

**Testing**: XCTest in `KaloriasTests`. The 161 existing tests must stay green. New pure suites for
zoom clamping and frame geometry. The `metadataOutputRectConverted` call is a hardware/layer boundary
and is verified at runtime by the quickstart procedure, not by a unit test — stated explicitly rather
than faked.

**Target Platform**: iOS 26.5+.

**Project Type**: Native iOS app. New sources under `Kalorias/` auto-included; new test files need a
`project.pbxproj` entry.

**Performance Goals**: The picker must not block the screen; loading and downsizing a picked photo
runs off the main thread with a loading state (FR-027). Cropping happens once per capture.

**Constraints**: no permission prompt for the picker (FR-007); nothing outside the frame may reach the
analysis (FR-010); the crop must not be upscaled (FR-013); zoom clamped to the device's range
(FR-018); zoom and frame must compose (FR-021); camera reliability unchanged (FR-022); EN+ES for all
new copy.

**Scale/Scope**: 3 new pure types + 1 new loader + 1 type rename; 4 modified camera files; 2–3 new
test suites. No persistence, navigation, or analysis-contract change.

## Constitution Check

*GATE: evaluated against Kalorias Constitution v1.1.1. Re-checked after Phase 1 — see below.*

| Principle | Gate | Status |
|-----------|------|--------|
| I. Code Quality | Zoom clamping and frame geometry live in pure testable types, not view bodies. **One** crop implementation, not two — the existing cropper is generalized rather than copied. Existing `@unchecked Sendable` escapes in the session controller keep their documented invariants; the new device reference is mutated only on the session queue, documented in place. | ✅ |
| II. Testing (NON-NEG) | Pure suites for zoom clamping (normal, both limits, single-focal-length device) and frame geometry (square inset across aspect ratios). The reused crop keeps its orientation test. The layer-rect conversion is an untestable boundary and is **declared** as such, with runtime validation in quickstart (SC-011). | ✅ |
| III. UX Consistency | Picker opens from a bottom-left control balancing the existing bottom-right/centre chrome; picked photos reuse the existing confirm/send/back affordances rather than a parallel flow. Loading state for picked-photo preparation (FR-027). Frame and zoom indicator legible over live video. Existing failure messages unchanged. | ✅ |
| IV. Performance | Picker load + downsize off the main thread; one crop per capture; zoom is a device property set on the session queue. No main-thread image work added. | ✅ |
| V. Architecture (NON-NEG) | Swift 6 strict; MV — `CaptureSessionStore` remains the single owner of camera UI state and gains the zoom and picked-photo intents; AVFoundation stays inside `CameraSessionController`; Router untouched. | ✅ |
| VI. Localization & Appearance (NON-NEG) | New copy (library button label, zoom indicator, picked-photo failure) in EN+ES. The camera is a full-bleed photographic surface; its chrome stays white/black as today. | ⚠️ see Complexity Tracking |
| Tech Constraints | PhotosUI is an Apple framework; no third-party dependency; no new networked service. Gemini contract unchanged. Nothing new leaves the device beyond the image already being sent. | ✅ |
| Design System (governance) | No new token; the constitution's table is untouched. | ✅ |

**Result**: All gates pass. One clause needs an explicit justification rather than a silent pass —
the camera's chrome colours — recorded in Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/008-camera-picker-frame-zoom/
├── plan.md                  # This file
├── research.md              # Phase 0 — 8 resolved decisions
├── data-model.md            # Phase 1 — transient state only, no persistence change
├── quickstart.md            # Phase 1 — incl. the "crop is real" runtime check
├── contracts/
│   └── ui-contracts.md      # pure APIs, screen states, a11y ids, l10n keys
├── checklists/requirements.md
└── tasks.md                 # /speckit-tasks (not created here)
```

### Source Code (repository root)

```text
Kalorias/
├── Features/Camera/
│   ├── CameraZoom.swift                  # NEW: pure zoom clamping (no AVFoundation)
│   ├── SendFrame.swift                   # NEW: pure frame geometry (centred square inset)
│   ├── LibraryPhotoLoader.swift          # NEW: PhotosPickerItem → sized UIImage, off-main
│   ├── CameraSessionController.swift     # MODIFIED: retain the device; setZoom; expose zoom range
│   ├── CameraPreviewLayerView.swift      # MODIFIED: convert the frame rect → normalized image rect
│   ├── CaptureSessionStore.swift         # MODIFIED: zoom state, picked-photo intent, crop-before-captured
│   └── CameraCaptureView.swift           # MODIFIED: library button, frame overlay, pinch, zoom indicator
├── Features/History/
│   ├── ImageCropper.swift                # RENAMED from FoodThumbnailCropper.swift — one crop impl
│   └── MealDetailsView.swift             # MODIFIED: call site of the renamed cropper only
└── Resources/
    └── Localizable.xcstrings             # MODIFIED: library button, zoom indicator, pick failure (EN+ES)

KaloriasTests/                            # new files need a project.pbxproj entry
├── CameraZoomTests.swift                 # NEW
├── SendFrameTests.swift                  # NEW
└── ImageCropperTests.swift               # RENAMED from FoodThumbnailCropperTests.swift
```

**Structure Decision**: The two pieces most likely to harbour a silent bug — zoom clamping and frame
geometry — are extracted as pure `nonisolated` types with **no AVFoundation import**, so they are
unit-testable without hardware. Everything that genuinely needs the capture layer stays behind the
existing `CameraSessionController` / `CameraPreviewLayerView` boundary. The crop is **not**
reimplemented: `FoodThumbnailCropper` is renamed to `ImageCropper` (its "thumbnail" name would be a
lie once it also produces full-size send crops) so one tested implementation serves both callers.

### Post-Design Constitution Re-Check

- **No new violations.** No third-party dependency, no new service, no migration, no new token, no
  ViewModel.
- **Principle I strengthened**: renaming the cropper avoids a second crop implementation, which was
  the alternative once the send path needed the same geometry.
- **Principle II honest about its limit**: the layer-rect conversion cannot be unit-tested. Rather
  than assert something weaker and call it covered, the plan names it a boundary and pushes its
  verification into a runtime check that can fail (food outside the frame must not appear — SC-011).
- **Principle V held**: `CaptureSessionStore` stays the only owner of camera UI state; zoom and the
  picked photo arrive as intents on it rather than as new state scattered in the view.
- **Risk accepted**: cropping reduces the pixels sent to the analysis. FR-013 forbids upscaling to
  compensate, so a heavily-zoomed tight crop yields a smaller image. Watched by the quickstart's
  quality check rather than designed away.

## Complexity Tracking

> No new violations. One clause needs stating rather than assuming, plus one deliberate rename.

| Item | Why Needed | Simpler Alternative Rejected Because |
|------|------------|-------------------------------------|
| The camera screen's chrome uses `.white` / `.black` rather than `AppColor` tokens (Principle VI mandates tokenized colour) | The camera is a full-bleed photographic surface that is always dark regardless of appearance. Adaptive tokens would make the frame and controls *less* legible — a light-appearance token would wash out over a bright scene. The new frame, scrim and zoom indicator follow the same convention the existing capture button and cancel button already use. | Adding camera-specific palette tokens was considered and rejected as ceremony: they would be fixed values that never adapt, which is what `.white`/`.black` already express. Revisit only if camera chrome ever needs theming. |
| `FoodThumbnailCropper` → `ImageCropper` (touches a feature-006 file and its test file) | The send crop needs the same orientation-safe unit-rect crop. Keeping the "thumbnail" name while producing full-size crops would misdescribe it, and copying it would create two implementations of the one thing whose orientation handling is subtle. | Calling `FoodThumbnailCropper.crop(..., maxDimension: 4096)` from the send path was rejected: it works, but leaves a type whose name actively misleads the next reader. A pure rename with one call site is cheaper than that debt. |
