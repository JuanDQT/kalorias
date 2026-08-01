# Quickstart & Validation: Camera — Library Picker, Send Framing & Zoom

**Feature**: `008-camera-picker-frame-zoom` | **Date**: 2026-07-26

Signatures in [contracts/ui-contracts.md](./contracts/ui-contracts.md); state and failure rules in
[data-model.md](./data-model.md); the reasoning and the numeric derivations in
[research.md](./research.md).

> **This feature has one part that cannot be unit-tested** — the frame→image rect conversion, which
> needs a live preview layer. Read §"Verifying the crop" before validating US2. It is verified by an
> invariant plus a physical check, not by a test that cannot fail.

---

## Prerequisites

- Xcode 26.6+, iOS 26.5 target, Swift 6 strict concurrency
- Scheme `Kalorias`
- **A physical device is required** for US2 and US3. The simulator has no camera: the screen will show
  its "unavailable" state, which is useful for one check (FR-005) but cannot validate framing or zoom.
- The simulator **can** validate US1 — add a few images to its photo library first
  (`xcrun simctl addmedia "iPhone 17 Pro Max" <file.jpg>`)
- A Gemini key in `Config/Secrets.xcconfig` for end-to-end sends

New `.swift` files under `Kalorias/` are auto-included; **new test files need a `project.pbxproj`
entry** or they silently never run — a test count that does not grow is the symptom.

---

## Build & test

```bash
xcodebuild -project Kalorias.xcodeproj -scheme Kalorias \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build 2>&1 | tail -20

xcodebuild -project Kalorias.xcodeproj -scheme Kalorias \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test 2>&1 | tail -30
```

**Expected**: `BUILD SUCCEEDED` with zero warnings; `TEST SUCCEEDED` with the **161** existing tests
still green plus the new suites. The renamed `ImageCropperTests` must keep the same case count as
`FoodThumbnailCropperTests` had — a rename must not quietly drop coverage.

---

## Required unit coverage

### `CameraZoomTests`

| Case | Asserts | Contract |
|---|---|---|
| Request below minimum | returns `1.0` | Z1 |
| Request above the usable ceiling | returns `5.0` | Z2 |
| Device maximum below the ceiling (e.g. `3.0`) | returns `3.0`, not `5.0` | Z3 |
| **Device maximum of `1.0`** (single focal length) | returns `1.0` for any request | Z4 |
| Zero / negative / NaN / infinite request | returns `1.0`, no crash | Z5 |
| A mid-range request within both limits | returned unchanged | Z1, Z2 |
| `isDefault` | true at `1.0`, false when zoomed | Z6 |

### `SendFrameTests`

| Case | Asserts | Contract |
|---|---|---|
| Tall container (440×956) | rect is **square**, centred | S1, S2 |
| Wide container (956×440) | rect is square, centred, sized from the **shorter** edge | S1, S3 |
| Exactly square container | rect is square and centred | S1 |
| Side length | equals `min(w, h) − 2 × inset` | S3 |
| Container smaller than twice the inset | still a positive-sized square, no crash | S4 |
| Determinism | same size ⇒ identical rect | S5 |

### `ImageCropperTests` *(renamed)*

Keep every existing case, including **the non-`.up` orientation test** that catches
`cgImage.cropping`. Add one:

| Case | Asserts | Contract |
|---|---|---|
| Large `maxDimension` on a big source | output is **not upscaled** and keeps native crop resolution | **C2 / FR-013** |

---

## Verifying the crop (US2) — the untestable part

### The invariant

> **A centred square frame must produce a crop whose pixel width equals its pixel height.**

Verified numerically across layer and image aspect ratios (research R4): 1653×1653, 1575×1575,
1977×1977, 1883×1883. Note the *normalized* rect is never square — only the pixel rect is.

Assert this where the crop is produced. A transposed mapping, a forgotten aspect-fill crop, or a wrong
orientation each break it and will surface immediately.

### What the invariant does **not** catch

A uniform offset that preserves the aspect ratio. That is why the physical check below is also
required — the two together cover the failure modes.

### ✅ The physical check (SC-011)

1. On a device, place **two distinguishable foods** on the table: one clearly **inside** the frame, one
   clearly **outside** it.
2. Capture and send.
3. **Expect**: only the inside food appears in the results. If the outside food appears, the crop is
   not being applied. If the *inside* food is missing but the outside one appears, the mapping is
   offset or transposed.

Repeat once at maximum zoom — zoom and the frame must compose (FR-021).

---

## Manual validation

### V1 — Library picker (US1) — simulator is sufficient

1. Add images to the simulator's library, launch, open the camera.
2. **Expect** a control in the **bottom-left**. Tap it → the system picker opens.
3. **Expect no permission prompt**, ever, including the first time (FR-007).
4. Select a photo → the camera screen shows it in the **same** confirmation state as a capture, with
   the same Send and back-out actions.
5. Send it → analyzed and saved like any meal. Check the History tab shows it normally.
6. Reopen the picker and **cancel** → live preview resumes, nothing selected, nothing sent.
7. Pick a photo, then go back → live camera resumes, photo discarded.
8. **On the simulator**, where the camera is unavailable: **expect the library control still works**
   and a picked photo can still be analyzed (FR-005). This is the one check the simulator does best.
9. Pick a very large photo → **expect** a loading state and no frozen screen (FR-027).

### V2 — Send framing (US2) — device required

1. **Expect** a centred square frame with the area outside it dimmed.
2. **Expect** the frame legible against both a bright scene (white plate, sunlight) and a dark one.
3. Capture → **expect** the confirmation image is **cropped to the frame**; the surroundings are gone.
4. Send → **expect** the analysis reflects only the framed content.
5. Run the physical check above.
6. Rotate the device → **expect** the frame and the crop stay coherent.

### V3 — Zoom (US3) — device required

1. Pinch to zoom in → **expect** the preview magnifies smoothly.
2. **Expect** a zoom indicator appears once away from the default, and disappears at `1×` (FR-019).
3. Capture while zoomed → **expect** the photo reflects the zoom, not the unzoomed scene (FR-017).
4. Pinch out past the start → **expect** it stops at `1×`, no distortion.
5. Pinch in hard → **expect** it stops at the usable ceiling rather than degrading indefinitely.
6. Zoom, discard the photo, return to preview → **expect** zoom back at `1×` (spec Assumption).
7. Zoom while a photo is already captured → **expect** nothing changes (FR-020).
8. At maximum zoom, check the crop still has usable quality — FR-013 forbids upscaling to hide the
   reduced pixel count, so this is a judgement call to record, not a pass/fail.

### V4 — Failure paths

1. Pick an item that cannot be decoded (e.g. an unusual format) → **expect** a clear message and the
   live preview resuming, nothing sent (FR-006).
2. Deny camera permission → **expect** the existing permission behaviour, unchanged (FR-022).
3. Airplane mode, send a picked photo → **expect** the existing analysis error, unchanged.
4. Confirm no capture ever sends an image the user did not see in confirmation (FR-012) — including
   the case where the frame region is unavailable (see data-model failure rules).

### V5 — Accessibility, appearance, language

1. VoiceOver: the library control is labelled; the frame conveys **that only its interior is sent**
   rather than being announced as a rectangle (FR-015); the zoom value is announced when present.
2. **Zoom without pinching**: confirm an accessible alternative exists for users who cannot perform the
   gesture (FR-025).
3. Both languages: no raw key strings; the new copy reads sensibly.
4. Dynamic Type on the new text-bearing controls: no clipping.

---

## Definition of done

- [ ] `BUILD SUCCEEDED`, zero warnings under Swift 6 strict concurrency
- [ ] `TEST SUCCEEDED` — 161 existing tests green, plus `CameraZoomTests` and `SendFrameTests`
- [ ] `ImageCropperTests` retains every case the old `FoodThumbnailCropperTests` had, plus the no-upscale case
- [ ] New test files registered in `project.pbxproj` (test count grew)
- [ ] V1 passed, including **no permission prompt** and the camera-unavailable case
- [ ] V2 passed on a **device**, including the **physical crop check** (food outside the frame absent)
- [ ] The square-pixel invariant is asserted in the crop path
- [ ] V3 passed on a **device**, both zoom limits and the reset-on-restart behaviour
- [ ] Zoom is reachable without a pinch gesture
- [ ] A picked photo is **not** cropped, only downsized
- [ ] Only one crop implementation exists in the codebase (`ImageCropper`)
- [ ] No new colour token; no persistence change; no migration
- [ ] All new copy has EN + ES with translator comments
