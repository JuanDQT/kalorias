# Phase 0 Research: Camera — Library Picker, Send Framing & Zoom

**Feature**: `008-camera-picker-frame-zoom` | **Date**: 2026-07-26

All Technical Context unknowns are resolved. No `NEEDS CLARIFICATION` remains.

---

## R1 — The photo picker, and why it needs no permission (US1, FR-007)

**Decision**: SwiftUI's `PhotosPicker`, loading the selection with `loadTransferable(type: Data.self)`.

**Rationale**: `PhotosPicker` is backed by the out-of-process system picker. The app receives only the
items the user explicitly chose and never gains access to the library, so **no authorisation prompt
appears and no usage description is required**. Confirmed against the project: `Config/Info.plist`
declares only `NSCameraUsageDescription`, and that stays sufficient — FR-007 is satisfied by choosing
this API rather than by adding a permission flow.

PhotosUI is an Apple framework, so the constitution's "prefer Apple frameworks" constraint is met with
no third-party dependency.

**Alternatives considered**:
- *`UIImagePickerController`* — rejected: the older in-process picker **does** require
  `NSPhotoLibraryUsageDescription` and a permission prompt, directly violating FR-007, and it is
  deprecated in spirit for this use.
- *A custom picker over `PHAsset`* — rejected: requires full library authorisation, far more code, and
  a worse experience than the system UI.

**Failure path (FR-006)**: `loadTransferable` can return `nil` or throw for an item that cannot be
decoded (an unsupported format, an iCloud asset that fails to download). That maps to a clear message
and a return to the live preview — the existing failure vocabulary of the screen, not a new one.

---

## R2 — Where a picked photo enters the flow (US1, FR-002, FR-003)

**Decision**: a picked, downsized image is placed into the **existing** `CaptureState.captured(UIImage)`.

**Rationale**: the state machine already means "an image is ready to send" with a Send button, a
back-out path, and `startAnalysis` wired to it. Reusing it gets FR-002 and FR-003 for free and
guarantees a library photo cannot diverge from a captured one — there is only one send path to keep
correct.

This also means **no change to `CaptureState`**, to `startAnalysis`, to the analysis contract, to
storage, or to per-ingredient regions (which stay proportional to whatever image was sent).

**Alternatives considered**:
- *A separate `.picked(UIImage)` case* — rejected: every consumer would have to handle both, and the
  two would drift. The distinction has no user-visible meaning once the image is chosen.
- *Skipping the confirmation step and sending immediately* — rejected: FR-002 asks for the same
  confirmation, and sending without one removes the user's chance to notice a wrong pick.

**Size preparation (FR-008)**: a library photo can be far larger than a capture. It is downsized to a
comparable dimension before entering `.captured`, off the main thread with a loading state (FR-027),
so analysis cost and latency do not depend on the source.

---

## R3 — Mapping the on-screen frame to a crop of the photo (US2, FR-011) — **CORRECTED**

> **This decision was wrong on the first attempt and has been revised. The original text is kept
> below as the rejected alternative, because the failure mode is worth remembering.**

**Decision (revised)**: compute the mapping **purely**, in the captured image's own coordinate space,
via `SendFrame.imageRegion(previewSize:imageSize:)`. Do **not** use
`AVCaptureVideoPreviewLayer.metadataOutputRectConverted(fromLayerRect:)`.

**Why the first attempt failed — measured on device.** The original decision used
`metadataOutputRectConverted(fromLayerRect:)` on the reasoning that it handles the aspect-fill crop
*and* orientation. It does handle them — but its result lives in the **metadata output coordinate
space**, which is the sensor's *landscape buffer*, while the captured `UIImage` reports an
**orientation-corrected** (portrait) size. Feeding one into the other transposes the axes.

The runtime invariant caught it on the first real capture:

```
Assertion failed: Send-frame crop is not square (3563x6334).
```

`6334 / 3563 = 1.778` — exactly 16:9, with height and width swapped relative to the predicted 4:3.
Precisely the "transposing axes" case the assertion was written to name.

**Why the pure derivation is correct and simpler.** Two facts from the specification hold together:
the preview is **centred aspect-fill**, and the frame is a **centred square**. Therefore a centred
square of side `s` in the preview corresponds to a centred square of side `s / fillScale` in the
image, where `fillScale = max(previewW/imageW, previewH/imageH)`. There is no rotation to reason
about, because everything is expressed in the image's own space. Verified across devices and image
aspects:

| Preview | Image | Normalized rect | Crop pixels | Square |
|---|---|---|---|---|
| 430×932 | 6048×8064 (the failing device) | (0.2382, 0.3036, 0.5236, 0.3927) | 3167 × 3167 | ✅ |
| 430×932 | 3024×4032 | (0.2382, 0.3036, 0.5236, 0.3927) | 1583 × 1583 | ✅ |
| 440×956 | 3024×4032 | (0.2378, 0.3033, 0.5244, 0.3933) | 1586 × 1586 | ✅ |
| 430×932 | 4032×3024 (landscape) | (0.3527, 0.3036, 0.2945, 0.3927) | 1188 × 1188 | ✅ |

**The decisive benefit**: the mapping is now **unit-testable**, which the framework call never was.
`SendFrameTests` gained 6 cases covering exactly this, and they were confirmed to discriminate —
reintroducing the transposition makes **10 of 14** fail; the fix makes all pass.

**Assumption this introduces**: the still capture covers the same field of view as the preview. That
holds for the `.photo` preset on a single device. `CameraPreviewLayerView` documents that its
`resizeAspectFill` gravity is load-bearing for this geometry.

**Rejected alternative (the original decision)**: `metadataOutputRectConverted(fromLayerRect:)`. It
looked authoritative — a framework API for exactly this conversion — which is what made the bug
plausible. Its coordinate space is simply not the one a `UIImage` crop needs, and using it also left
the mapping untestable, so the error could only surface at runtime.

## R4 — Making the untestable boundary checkable anyway (Principle II)

**Decision**: accept that the layer conversion cannot be unit-tested (it needs a live preview layer),
and compensate with **a runtime invariant that a mapping bug violates**: a centred square frame must
produce a crop whose pixel dimensions are **equal**.

**Rationale**: derived numerically before committing to it. Under `resizeAspectFill`, for a centred
square of side `s` in a layer of size `L` over an image of size `I`:

| Layer | Image | Normalized rect | Crop in pixels | Square? |
|---|---|---|---|---|
| 440×956 | 3024×4032 (4:3) | (0.2266, 0.2950, 0.5467, 0.4100) | 1653.3 × 1653.3 | ✅ |
| 440×956 | 2160×3840 (16:9) | (0.1355, 0.2950, 0.7290, 0.4100) | 1574.6 × 1574.6 | ✅ |
| 375×667 | 3024×4032 (4:3) | (0.1732, 0.2549, 0.6537, 0.4903) | 1976.7 × 1976.7 | ✅ |
| 375×667 | 2160×3840 (16:9) | (0.0642, 0.2549, 0.8716, 0.4903) | 1882.6 × 1882.6 | ✅ |

The normalized rect is **not** square (widths and heights differ, because it is normalized against
different image dimensions), but the resulting **pixel** rect always is. That holds for any layer
aspect and any image aspect. So:

- A transposed mapping (x/y swapped) breaks it except in the accidental square case.
- A mapping that forgets the gravity crop breaks it.
- A mapping that applies the wrong orientation breaks it.

This is cheap to assert where the crop is produced, and it turns "we cannot test this" into "this
fails loudly if it is wrong". It does **not** catch a uniform offset that preserves the aspect, which
is why the quickstart also requires the physical check of placing food outside the frame (SC-011).

**Alternatives considered**:
- *Claim coverage from a weaker test* (e.g. asserting the modifier is applied) — rejected as exactly
  the kind of verification-that-cannot-fail that shipped a broken fix earlier in this project.
- *A UI test* — UI tests are off by default under Principle II.

---

## R5 — Reusing the existing crop rather than writing a second one (FR-010, FR-013)

**Decision**: rename `FoodThumbnailCropper` to `ImageCropper` and use it for the send crop, passing a
large maximum dimension so the crop is not downscaled.

**Rationale**: the type already crops a `UIImage` to a unit rect using `UIGraphicsImageRenderer` +
`draw(in:)`, which is orientation-safe, and it carries a test that specifically catches the
`cgImage.cropping(to:)` mistake. The send path needs precisely that. Copying it would create two
implementations of the subtlest code in the app; keeping the "thumbnail" name while it produces
full-size crops would misdescribe it.

`FoodRegion`'s validating initializer is reused unchanged for the normalized rect, so a degenerate or
out-of-bounds conversion result collapses to "no crop" instead of producing a distorted image.

**FR-013 (no upscaling)**: the existing cropper scales **down only** — it already refuses to upscale a
small crop. Passing a generous maximum dimension therefore yields the crop at native resolution, which
is what FR-013 requires.

**Alternatives considered**:
- *Call it with the thumbnail name* — works, leaves a misleading type name (recorded in the plan's
  Complexity Tracking).
- *A new send-specific cropper* — rejected: two implementations of orientation-safe cropping is how the
  orientation bug comes back.

---

## R6 — Zoom: what to drive, and what to clamp to (US3, FR-016 … FR-018)

**Decision**: drive `AVCaptureDevice.videoZoomFactor`, set on the existing session queue, clamped to
`1.0 ... min(device.maxAvailableVideoZoomFactor, 5.0)`. Clamping lives in a pure `CameraZoom` type with
no AVFoundation import.

**Rationale**:
- `videoZoomFactor` affects the preview **and** the capture from the same device, so FR-017 ("the sent
  photo reflects the zoom") holds by construction rather than by a second code path.
- The session is configured with `.builtInWideAngleCamera`, whose minimum factor is `1.0` — there is no
  ultra-wide to zoom out into, so the wide end clamps at 1.0 (FR-018).
- The magnified end is capped at **5×** rather than the device maximum. `maxAvailableVideoZoomFactor`
  can be very large and is mostly digital upscaling; beyond roughly 5× the picture stops being worth
  analyzing, which is exactly what FR-018's "still produces an acceptable picture" asks for.
- Clamping as a pure function makes both limits and the single-focal-length device testable without
  hardware.

**Implementation note**: `CameraSessionController` currently discards its `AVCaptureDevice` after
configuring — it is a local in `configureAndStart`. Zoom needs it retained. It must be mutated only on
the session queue, consistent with the file's existing documented `@unchecked Sendable` invariant.

**Alternatives considered**:
- *Switch to `.builtInDualWideCamera` for a 0.5× wide end* — genuinely nicer, but it changes the device
  the whole capture path is built on, risks the existing "camera unavailable" behaviour on devices
  without it, and FR-022 forbids making the camera less reliable. Out of scope; noted as a follow-up.
- *Crop the image to fake zoom* — rejected: it would double-crop with the send frame and lose
  resolution, and the preview would not match.
- *Expose the device maximum* — rejected per FR-018's quality clause.

**Zoom reset (spec Assumption)**: the factor returns to 1.0 whenever the live preview (re)starts, so a
zoom left over from a previous meal cannot silently frame the next one.

---

## R7 — How zoom and the frame compose (FR-021)

**Decision**: zoom is applied by the device, so the preview *and* the captured photo are already
zoomed; the crop is then taken from that zoomed photo using the same frame mapping.

**Rationale**: because both features act at different stages — zoom at capture, crop after — they
compose without special handling, and the frame keeps meaning "the part of what you see that will be
sent" at any zoom level. This is the reason to use device zoom rather than a view-level magnification:
a view-level zoom would change what the user sees **without** changing the photo, and the frame would
then be mapped from a transform the capture never had.

**Consequence, accepted**: zoom-in plus a tight frame yields a smaller pixel crop. FR-013 forbids
upscaling to hide that, so the quickstart includes a quality check at maximum zoom rather than a
silent compensation.

---

## R8 — Frame shape and where its geometry lives (US2, FR-009)

**Decision**: a **centred square**, inset from the shorter screen edge, computed by a pure `SendFrame`
type from the available size. The area outside is dimmed with a scrim.

**Rationale**:
- A square sidesteps any aspect negotiation between the screen (tall), the sensor (4:3) and the crop,
  and it matches how the image is later displayed — the history thumbnail and the ingredient
  thumbnails are already square-ish rounded rects, so what the user frames is close to what they will
  see afterwards.
- The square is also what makes R4's invariant available: equal pixel sides are a cheap, meaningful
  self-check.
- Keeping the geometry pure (a size in, a rect out) makes the frame's placement testable across screen
  aspect ratios without a camera.

**Alternatives considered**:
- *Match the sensor's 4:3* — would crop almost nothing and largely defeat the purpose.
- *Full-width, shorter height (16:9-ish)* — plausible, but food is rarely wide; a square wastes less on
  tablecloth.
- *A user-draggable frame* — the spec explicitly set this aside as a follow-up.
- *Putting the geometry in the view body* — rejected by Principle I; it is arithmetic and belongs in a
  testable type.
