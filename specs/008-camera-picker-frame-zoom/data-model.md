# Phase 1 Data Model: Camera — Library Picker, Send Framing & Zoom

**Feature**: `008-camera-picker-frame-zoom` | **Date**: 2026-07-26

> **Nothing is persisted and nothing stored changes.** No new field, no migration, no store version
> bump, no change to the meal record or to the analysis contract. Everything below is **transient
> camera-screen state** or a **pure value**. The only thing that differs downstream is which pixels
> were sent.

---

## Unchanged types (stated so their stability is explicit)

| Type | Status | Note |
|---|---|---|
| `CaptureState` | **unchanged** | `.captured(UIImage)` already means "an image is ready to send". A picked photo and a cropped capture both enter it, so there is exactly one send path (research R2). |
| `MealEntry`, `StoredFood`, `FoodRegion` | **unchanged** | No persistence change. Per-ingredient regions stay proportional to whatever image was sent, so they remain correct for a cropped image. |
| `CalorieAnalysis`, the Gemini request | **unchanged** | Same contract; only the image bytes differ. |
| `Router` | **unchanged** | No new navigation. The picker is a sheet owned by the camera screen. |

---

## New pure value types

### `CameraZoom` — `Kalorias/Features/Camera/CameraZoom.swift`

Zoom clamping, with **no AVFoundation import** so it is testable without hardware.

| Member | Type | Meaning |
|---|---|---|
| `minimumFactor` | `CGFloat` | Always `1.0` — the configured wide-angle device cannot zoom out further |
| `maximumUsableFactor` | `CGFloat` | `5.0` — the quality ceiling from FR-018, not the device's raw maximum |
| `clamp(_:deviceMaximum:)` | `(CGFloat, CGFloat) -> CGFloat` | The requested factor, constrained to what is both supported and usable |

**Rules**

| # | Rule | Requirement |
|---|---|---|
| Z1 | Result is never below `1.0` | FR-018 |
| Z2 | Result never exceeds `min(deviceMaximum, 5.0)` | FR-018 |
| Z3 | A device whose maximum is below `5.0` clamps to the device's value | FR-018, edge case |
| Z4 | A device maximum of `1.0` (single focal length, no digital zoom) yields exactly `1.0` for any request | FR-018, edge case |
| Z5 | A non-finite or non-positive request yields `1.0` rather than propagating | Principle I |
| Z6 | `isDefault` is derivable, so the view can decide whether to show the indicator | FR-019 |

---

### `SendFrame` — `Kalorias/Features/Camera/SendFrame.swift`

Where the frame sits, given the space available. Pure geometry; **no AVFoundation, no UIKit view code**.

| Member | Type | Meaning |
|---|---|---|
| `inset` | `CGFloat` | Distance from the shorter screen edge |
| `rect(in:)` | `(CGSize) -> CGRect` | The centred square frame in the container's coordinate space |

**Rules**

| # | Rule | Requirement |
|---|---|---|
| S1 | The rect is **square** — equal width and height | FR-009, research R4 |
| S2 | The rect is centred in both axes | FR-009 |
| S3 | Side length is `min(width, height) - 2 × inset` | R8 |
| S4 | On a container too small for the inset, the rect degrades to a positive-sized square rather than a negative one | Principle I |
| S5 | Deterministic — the same size always yields the same rect | Principle II |

---

## New transient state on `CaptureSessionStore`

The store remains the single owner of camera UI state (Principle V). It gains:

| State | Type | Meaning | Lifetime |
|---|---|---|---|
| `zoomFactor` | `CGFloat` | Current magnification, already clamped | Reset to `1.0` whenever the live preview starts or restarts |
| `sendRegion` | `FoodRegion?` | The frame, converted to normalized image coordinates by the preview layer | Republished when the layer's bounds change; `nil` until the layer reports one |
| `isPreparingPickedPhoto` | `Bool` | Drives the loading state while a picked photo is loaded and downsized | Cleared on success or failure |
| `pickFailureMessage` | `String?` | Set when a picked item cannot be loaded | Cleared when the preview resumes |

**Invariants**

1. `zoomFactor` is only ever assigned a value that passed `CameraZoom.clamp` — the raw gesture value
   never reaches the device (Z1–Z5).
2. `zoomFactor` returns to `1.0` on preview (re)start, so a leftover zoom cannot frame the next meal
   (spec Assumption).
3. A capture entering `.captured` has **already** been cropped to `sendRegion`. Nothing downstream
   crops, and nothing downstream needs to know a crop happened (FR-012).
4. A **picked** photo entering `.captured` is **not** cropped — only downsized (spec Assumption). The
   frame is a camera-framing tool, not a library editor.
5. `sendRegion` being `nil` (layer not yet laid out, or a degenerate conversion) MUST NOT silently send
   an uncropped photo — see the failure rule below.

---

## Derivation flow

```text
                      ┌─ pinch gesture ─► CameraZoom.clamp(request, deviceMaximum:)
                      │                        │  Z1–Z5
                      │                        ▼
                      │            device.videoZoomFactor  (session queue)
                      │                        │
                      │        affects BOTH preview and capture ─► FR-017, FR-021
                      ▼
   SendFrame.rect(in: size)  ──►  frame drawn + scrim (view)
            │
            │ same rect, in layer coordinates
            ▼
   AVCaptureVideoPreviewLayer.metadataOutputRectConverted(fromLayerRect:)   ← R3
            │   handles aspect-fill crop AND orientation
            ▼
   FoodRegion(clampingX:y:width:height:)   ← reused, validates; nil ⇒ no crop
            │
            ▼
   capture ──► ImageCropper.crop(photo, to: region, maxDimension: large)    ← R5, scale-down only
            │        INVARIANT: pixel width == pixel height (R4)
            ▼
   CaptureState.captured(croppedImage) ──► existing Send ──► existing analysis ──► existing storage


   PhotosPicker ──► loadTransferable(Data) ──► downsize (off-main) ──► CaptureState.captured(image)
                          │ failure                                        (no crop — Assumption)
                          ▼
                    pickFailureMessage ──► live preview resumes
```

---

## Failure rules

| Situation | Behaviour | Requirement |
|---|---|---|
| Picked item cannot be decoded | Clear message, live preview resumes, nothing sent | FR-006 |
| Picker cancelled | Live preview resumes, nothing selected | FR-004 |
| Camera unavailable | Library control still usable; a picked photo can still be analyzed | FR-005 |
| `sendRegion` is `nil` at capture time | Do **not** send an uncropped photo silently. Either the capture is refused with a clear message, or the frame is treated as the whole image **and the user is shown the full image in confirmation** so what is confirmed is still what is sent (FR-012) | FR-010, FR-012 |
| Crop returns `nil` (degenerate region) | Same rule as above — never send something the user did not confirm | FR-010 |
| Zoom request outside the supported range | Clamped, no error | FR-018 |
| Zoom gesture while a photo is already captured | Ignored | FR-020 |

---

## Validation rules summary

| Rule | Source | Enforced by |
|---|---|---|
| No permission prompt for picking | FR-007 | choice of `PhotosPicker` (R1) |
| Picked photo uses the same send path | FR-002, FR-003 | reuses `CaptureState.captured` |
| Nothing outside the frame is sent | FR-010 | crop applied **before** `.captured` |
| Confirmation shows what is sent | FR-012 | `.captured` holds the final image |
| Crop is not upscaled | FR-013 | existing cropper scales down only |
| Frame maps correctly through aspect-fill + orientation | FR-011 | AVFoundation conversion (R3) + square-pixel invariant (R4) |
| Zoom reaches the photo | FR-017 | device zoom, not view zoom |
| Zoom and frame compose | FR-021 | crop taken from the already-zoomed photo |
| Zoom clamped | FR-018 | `CameraZoom` (Z1–Z5) |
| Nothing persisted changes | FR-026 | no model, schema or contract touched |
