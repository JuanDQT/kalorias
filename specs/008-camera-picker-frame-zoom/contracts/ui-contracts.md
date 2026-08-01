# Phase 1 Contracts: Camera — Library Picker, Send Framing & Zoom

**Feature**: `008-camera-picker-frame-zoom` | **Date**: 2026-07-26

The app exposes no network or CLI surface. The contracts that matter are the **pure APIs**, the
**camera-layer boundary** (the one thing that cannot be unit-tested), the **screen states**, the
**accessibility identifiers** and the **localization keys**.

---

## 1. Pure logic APIs

### 1.1 `CameraZoom` — `Kalorias/Features/Camera/CameraZoom.swift`

```swift
nonisolated enum CameraZoom {
    static let minimumFactor: CGFloat = 1.0
    /// Quality ceiling from FR-018 — NOT the device's raw maximum, which is
    /// mostly digital upscaling.
    static let maximumUsableFactor: CGFloat = 5.0

    /// The requested factor constrained to what is both supported and usable.
    static func clamp(_ requested: CGFloat, deviceMaximum: CGFloat) -> CGFloat

    /// Whether a factor is the un-zoomed default (drives the indicator).
    static func isDefault(_ factor: CGFloat) -> Bool
}
```

**No AVFoundation import** — this is arithmetic, and it must be testable without a camera.

| # | Guarantee | Requirement |
|---|---|---|
| Z1 | Never returns below `1.0` | FR-018 |
| Z2 | Never exceeds `min(deviceMaximum, 5.0)` | FR-018 |
| Z3 | `deviceMaximum < 5.0` clamps to the device's value | FR-018 |
| Z4 | `deviceMaximum == 1.0` yields exactly `1.0` for any request | edge case |
| Z5 | Non-finite, zero or negative requests yield `1.0` | Principle I |
| Z6 | `isDefault(1.0) == true`; a zoomed factor is `false` | FR-019 |

### 1.2 `SendFrame` — `Kalorias/Features/Camera/SendFrame.swift`

```swift
nonisolated struct SendFrame {
    let inset: CGFloat
    /// The centred square frame within a container of `size`.
    func rect(in size: CGSize) -> CGRect
}
```

| # | Guarantee | Requirement |
|---|---|---|
| S1 | The rect is **square** (`width == height`) | FR-009, research R4 |
| S2 | Centred in both axes | FR-009 |
| S3 | Side is `min(size.width, size.height) - 2 × inset` | R8 |
| S4 | A container too small for the inset still yields a positive-sized square | Principle I |
| S5 | Deterministic for a given size | Principle II |

### 1.3 `ImageCropper` — `Kalorias/Features/History/ImageCropper.swift` *(renamed)*

Renamed from `FoodThumbnailCropper`; the API is otherwise **unchanged**, including its
orientation-safety guarantees and its existing tests.

| # | Guarantee | Requirement |
|---|---|---|
| C1 | Crops via `UIGraphicsImageRenderer` + `draw(in:)`, never `cgImage.cropping` | FR-011 (orientation) |
| C2 | Scales **down only** — never upscales a small crop | **FR-013** |
| C3 | Preserves the region's aspect ratio | FR-010 |
| C4 | Returns `nil` for a degenerate source or region | failure rules |

> Renaming is deliberate: once this also produces full-size send crops, "thumbnail" would misdescribe
> it. One implementation, two callers — not two implementations of the app's subtlest geometry.

---

## 2. The camera-layer boundary (declared untestable)

### 2.1 Frame → normalized image rect

```
AVCaptureVideoPreviewLayer.metadataOutputRectConverted(fromLayerRect: CGRect) -> CGRect
```

Owned by `CameraPreviewLayerView`, which holds the layer. It publishes the converted rect to the store
as a validated `FoodRegion`.

| # | Guarantee | Requirement |
|---|---|---|
| B1 | Accounts for `resizeAspectFill` cropping **and** image orientation | FR-011 |
| B2 | Republished when the layer's bounds change (rotation, layout) | FR-011 |
| B3 | The result passes through `FoodRegion`'s validating initializer; a degenerate rect becomes `nil` | failure rules |
| B4 | **Cannot be unit-tested** — it requires a live preview layer. This is stated, not worked around | Principle II |

### 2.2 The invariant that substitutes for a unit test

> **A centred square frame must produce a crop whose pixel width equals its pixel height.**

Derived numerically across layer and image aspect ratios before being adopted:

| Layer | Image | Normalized rect | Crop pixels | Square |
|---|---|---|---|---|
| 440×956 | 3024×4032 | (0.2266, 0.2950, 0.5467, 0.4100) | 1653 × 1653 | ✅ |
| 440×956 | 2160×3840 | (0.1355, 0.2950, 0.7290, 0.4100) | 1575 × 1575 | ✅ |
| 375×667 | 3024×4032 | (0.1732, 0.2549, 0.6537, 0.4903) | 1977 × 1977 | ✅ |
| 375×667 | 2160×3840 | (0.0642, 0.2549, 0.8716, 0.4903) | 1883 × 1883 | ✅ |

Note the **normalized** rect is not square — only the pixel rect is. A transposed mapping, a forgotten
gravity crop, or a wrong orientation each break the invariant. A uniform offset does not, which is why
the physical check in quickstart (food outside the frame must not appear) is also required.

### 2.3 Device zoom

```
AVCaptureDevice.videoZoomFactor  // set on the existing session queue
AVCaptureDevice.maxAvailableVideoZoomFactor  // feeds CameraZoom.clamp
```

| # | Guarantee | Requirement |
|---|---|---|
| B5 | Only clamped values are written | FR-018 |
| B6 | Mutated only on the session queue, per the file's existing documented `@unchecked Sendable` invariant | Principle V |
| B7 | Affects preview **and** capture from one device, so no second code path is needed | FR-017, FR-021 |
| B8 | Reset to `1.0` when the preview (re)starts | spec Assumption |

---

## 3. Screen state contract — `CameraCaptureView`

`CaptureState` gains **no case**. What changes is what fills `.captured` and what is drawn while
previewing.

| State | Additions |
|---|---|
| `.previewing` | Frame + scrim overlay; bottom-left library control; pinch gesture; zoom indicator when not at default |
| `.captured` | **Unchanged UI.** Holds the final image — a cropped capture or a downsized picked photo |
| `.unavailable` | **Library control remains usable** (FR-005). The existing message and Cancel are unchanged |
| Preparing a picked photo | Loading state while the item is loaded and downsized (FR-027) |
| Pick failed | Clear message, return to `.previewing` (FR-006) |

**Layout**: the library control sits **bottom-left**, balancing the existing centre capture button; the
existing top-left Cancel and the Send button are untouched.

**Unchanged**: `startAnalysis`, the analysis sheet, retake, `router.dismissCamera()`, the unavailable
view.

---

## 4. Accessibility contract

Existing identifiers are preserved: `camera.screen`, `camera.preview`, `camera.captureButton`,
`camera.sendButton`, `camera.cancelButton`, `camera.unavailableMessage`.

| New identifier | Element |
|---|---|
| `camera.libraryButton` | bottom-left picker control |
| `camera.sendFrame` | the frame overlay |
| `camera.zoomIndicator` | current zoom, shown only when not at default |

**Requirements**

- The frame is **not** decorative: its purpose must be conveyed (FR-015), so it carries a label
  describing that only its interior is sent — not merely a drawn rectangle.
- The library control carries a label, since it is icon-only.
- The zoom indicator's value is announced when present.
- The pinch gesture must not be the only way to change zoom for users who cannot pinch — provide an
  accessible alternative (adjustable trait or discrete controls) (FR-025).

---

## 5. Localization contract — `Kalorias/Resources/Localizable.xcstrings`

Existing `camera.*` keys (`camera.cancel`, `camera.capture`, `camera.send`, `camera.unavailable`) are
unchanged. New keys, EN + ES, each with a translator comment:

| Key | `en` | `es` |
|---|---|---|
| `camera.library` | `Choose from library` | `Elegir de la biblioteca` |
| `camera.sendFrame.label` | `Only what is inside this frame will be analyzed` | `Solo se analizará lo que esté dentro de este recuadro` |
| `camera.zoom.indicator` | `%@×` | `%@×` |
| `camera.zoom.label` | `Zoom` | `Zoom` |
| `camera.library.failed` | `That photo could not be opened. Try another one.` | `No se pudo abrir esa foto. Prueba con otra.` |
| `camera.preparing` | `Preparing photo…` | `Preparando foto…` |

**Wording note**: `camera.sendFrame.label` states the crop's consequence rather than describing a
rectangle. That is deliberate — the frame's meaning is what needs conveying (FR-015), and a user who
cannot see it needs to know that content outside it is discarded.

---

## 6. Design-system contract

**No new token; the constitution's table is untouched.**

The camera is a full-bleed photographic surface that is always dark, so its chrome — the existing
capture button, Cancel, and now the frame, scrim, library control and zoom indicator — uses `.white` /
`.black` rather than the adaptive `AppColor` palette, continuing the convention already in this screen.
This is recorded as a justified exception in the plan's Complexity Tracking rather than passed over:
adaptive tokens would make the frame *less* legible over a bright scene.
