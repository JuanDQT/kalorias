---

description: "Task list for Camera — Library Picker, Send Framing & Zoom"
---

# Tasks: Camera — Library Picker, Send Framing & Zoom

**Input**: Design documents from `/specs/008-camera-picker-frame-zoom/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/ui-contracts.md](./contracts/ui-contracts.md), [quickstart.md](./quickstart.md)

**Tests**: Unit tests are **REQUIRED** for the two pure types. Constitution Principle II mandates them
for logic that computes or converts values — zoom clamping and frame geometry both qualify. The
frame→image rect conversion **cannot** be unit-tested (it needs a live preview layer); it is covered by
a runtime invariant plus a physical check instead, and that is stated rather than papered over.
**UI tests stay OFF** (Principle II).

**Organization**: Tasks are grouped by user story so each can be implemented and shipped independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1 / US2 / US3 from spec.md
- Exact file paths are in every task

## Path Conventions

Sources under `Kalorias/`, tests under `KaloriasTests/`. New sources are auto-included; **new test
files need a `project.pbxproj` entry**, and a **renamed** test file needs its existing entries updated
(4 references), or it silently stops running.

⚠️ **US2 and US3 require a physical device.** The simulator has no camera and will show the
"unavailable" state — useful for one US1 check (FR-005) but incapable of validating framing or zoom.

---

## Phase 1: Setup

- [X] T001 Capture the green baseline: `xcodebuild -project Kalorias.xcodeproj -scheme Kalorias -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test` — expect **161 tests, 0 failures**. Record the case count of `FoodThumbnailCropperTests` specifically, so T003's rename can be checked for dropped coverage
- [X] T002 Load a few images into the simulator's photo library for US1 validation: `xcrun simctl addmedia "iPhone 17 Pro Max" <some.jpg>` (repeat for 2–3 files). Confirm a physical device is available for US2/US3, since the simulator cannot validate framing or zoom

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: One mechanical refactor, done in isolation before any behaviour changes.

**Honest scoping note**: this phase blocks **US2 only** — US1 and US3 do not touch the cropper. It is
placed here deliberately anyway: a pure rename mixed into feature work is far harder to review, and
doing it alone lets the test suite prove no coverage was lost *before* any behaviour changes land.

- [X] T003 Rename `Kalorias/Features/History/FoodThumbnailCropper.swift` to `ImageCropper.swift` and the type `FoodThumbnailCropper` to `ImageCropper`, updating its one production call site in `Kalorias/Features/History/MealDetailsView.swift`. The API, behaviour and doc comments are otherwise **unchanged**. Rationale: once this also produces full-size send crops, "thumbnail" would misdescribe it, and copying it would create two implementations of the app's subtlest geometry (orientation-safe cropping)
- [X] T004 Rename `KaloriasTests/FoodThumbnailCropperTests.swift` to `ImageCropperTests.swift` and the test class to match, updating every `FoodThumbnailCropper.` reference inside it. **Keep every existing case** — especially the non-`.up` orientation test that catches `cgImage.cropping`
- [X] T005 Update the renamed test file's registration in `Kalorias.xcodeproj/project.pbxproj`: there are **4 references** to `FoodThumbnailCropperTests.swift` (PBXBuildFile, PBXFileReference, the group's `children`, the target's `Sources` phase). All four must point at the new filename, then `plutil -lint Kalorias.xcodeproj/project.pbxproj`
- [X] T006 Move the private `downsized(_:maxDimension:)` helper out of `Kalorias/Features/History/ImageStore.swift` and into `ImageCropper` as an internal function, updating `DiskImageStore` to call it. US1 needs to downsize a picked photo, and a second downsizer would duplicate this one (Principle I). Behaviour must be identical — `DiskImageStore`'s existing tests must still pass unchanged
- [X] T007 Build and run the full suite (`xcodebuild ... test`); confirm zero warnings, **161 tests still passing**, and that `ImageCropperTests` reports the **same case count** recorded in T001. A lower count means the rename dropped coverage

**Checkpoint**: One canonical image-geometry utility, verified to have lost nothing — user stories can begin

---

## Phase 3: User Story 1 - Analyze a photo from the library (Priority: P1) 🎯 MVP

**Goal**: A bottom-left control opens the system photo picker; the chosen photo reaches Send, analysis and storage through the path a captured photo already uses.

**Independent Test**: Open the camera, tap the bottom-left button, choose a library photo, confirm it appears in the same confirmation state as a captured photo, and send it for analysis successfully. Validatable **on the simulator**.

### Implementation for User Story 1

- [X] T008 [P] [US1] Add the US1 localization keys to `Kalorias/Resources/Localizable.xcstrings` with EN + ES and translator comments: `camera.library` (`Choose from library` / `Elegir de la biblioteca`), `camera.library.failed` (`That photo could not be opened. Try another one.` / `No se pudo abrir esa foto. Prueba con otra.`), `camera.preparing` (`Preparing photo…` / `Preparando foto…`)
- [X] T009 [US1] Create `Kalorias/Features/Camera/LibraryPhotoLoader.swift`: loads a `PhotosPickerItem` via `loadTransferable(type: Data.self)`, decodes it, and downsizes it through `ImageCropper`'s shared helper (T006) to a dimension comparable to a capture (FR-008). Runs **off the main thread**. Returns `nil` rather than throwing for an item that cannot be decoded, so the caller can show the failure message (FR-006) (depends on T006)
- [X] T010 [US1] Extend `Kalorias/Features/Camera/CaptureSessionStore.swift` with the picked-photo intent and its two pieces of transient state: `isPreparingPickedPhoto` (drives the loading state, FR-027) and `pickFailureMessage` (FR-006). On success the image enters the **existing** `CaptureState.captured(_:)` — do **not** add a new case, and do **not** crop a picked photo (spec Assumption); only downsizing applies. On failure, set the message and return to `.previewing` (depends on T009)
- [X] T011 [US1] Add the picker UI to `Kalorias/Features/Camera/CameraCaptureView.swift`: a **bottom-left** control using SwiftUI's `PhotosPicker` (PhotosUI), balancing the existing centre capture button; the top-left Cancel and the Send button are untouched. Give it the `camera.libraryButton` accessibility identifier and a label, since it is icon-only. Show the loading state while preparing and the failure message on failure. Chrome colours follow the screen's existing `.white`/`.black` convention (depends on T010)
- [X] T012 [US1] Make the library control available in the **`.unavailable`** state too, in `Kalorias/Features/Camera/CameraCaptureView.swift` — an unusable camera must not block picking a photo (FR-005). This is the one path the simulator validates best
- [X] T013 [US1] Build and run the full suite (`xcodebuild ... test`); confirm zero warnings and 161 tests still green
- [ ] T014 [US1] Validate quickstart.md **V1** on the simulator: bottom-left control present; **no permission prompt ever**, including first use (FR-007); picked photo reaches the same confirmation state; sending saves a normal meal visible in History; cancel and back-out both return cleanly; a large photo shows a loading state; and with the camera unavailable the control still works

**Checkpoint**: The largest capability ships independently, validatable without a device

---

## Phase 4: User Story 2 - See exactly what will be sent (Priority: P2)

**Goal**: A centred square frame is drawn, the outside is dimmed, and a captured photo is cropped to it before it becomes `.captured`.

**Independent Test**: On a device, confirm the frame is drawn; capture, and confirm the confirmation image is cropped to the frame; then place one food inside the frame and one outside, send, and confirm only the inside food appears.

### Geometry first

- [X] T015 [P] [US2] Create `Kalorias/Features/Camera/SendFrame.swift`: a pure `nonisolated struct` with an `inset` and `rect(in: CGSize) -> CGRect` returning a **centred square** of side `min(width, height) − 2 × inset`. **No AVFoundation, no UIKit view code.** A container too small for the inset must still yield a positive-sized square rather than a negative one
- [X] T016 [US2] Create `KaloriasTests/SendFrameTests.swift` covering the 6 cases in quickstart.md §"SendFrameTests": square rect on a tall container, on a wide container (sized from the **shorter** edge), on an exactly-square container; side length formula; a container smaller than twice the inset; and determinism
- [X] T017 [US2] Register `SendFrameTests.swift` in `Kalorias.xcodeproj/project.pbxproj` and `plutil -lint` it

### The layer boundary

- [X] T018 [US2] In `Kalorias/Features/Camera/CameraPreviewLayerView.swift`, convert the frame's rect in layer coordinates to a normalized image rect using `AVCaptureVideoPreviewLayer.metadataOutputRectConverted(fromLayerRect:)`, and publish it to the store as a validated `FoodRegion`. **Do not hand-roll this transform** — it must account for `resizeAspectFill` cropping *and* image orientation, which is the pair the specification flagged as most likely to produce a plausible-but-offset bug (research R3). Republish when the layer's bounds change, so rotation stays correct. A degenerate result becomes `nil` via `FoodRegion`'s validating initializer
- [X] T019 [US2] In `Kalorias/Features/Camera/CaptureSessionStore.swift`, hold the published `sendRegion` and crop each capture through `ImageCropper` **before** it enters `CaptureState.captured(_:)`. Pass a generous `maxDimension` so the crop keeps native resolution — the cropper scales down only, which is what FR-013 requires. Because the crop happens before `.captured`, nothing downstream changes and confirmation automatically shows what will be sent (FR-012)
- [X] T020 [US2] Assert the square-pixel invariant where the crop is produced in `Kalorias/Features/Camera/CaptureSessionStore.swift`: **a centred square frame must yield a crop whose pixel width equals its pixel height** (research R4, verified numerically at 1653², 1575², 1977², 1883²). Note the *normalized* rect is deliberately **not** square — only the pixel rect is. This is the substitute for the unit test that T018 cannot have: a transposed mapping, a forgotten gravity crop, or a wrong orientation each break it
- [X] T021 [US2] Handle the "no region" case in `Kalorias/Features/Camera/CaptureSessionStore.swift` per data-model.md's failure rules: if `sendRegion` is `nil` or the crop returns `nil`, **do not silently send an uncropped photo**. Either refuse the capture with a clear message, or fall back to the full image **and show that full image in confirmation**, so what the user confirms is always what is sent (FR-010, FR-012)

### The overlay

- [X] T022 [P] [US2] Add the US2 localization key to `Kalorias/Resources/Localizable.xcstrings` with EN + ES and a comment: `camera.sendFrame.label` (`Only what is inside this frame will be analyzed` / `Solo se analizará lo que esté dentro de este recuadro`). The wording states the crop's **consequence** rather than describing a rectangle — a user who cannot see the frame needs to know content outside it is discarded (FR-015)
- [X] T023 [US2] Draw the overlay in `Kalorias/Features/Camera/CameraCaptureView.swift` while `.previewing`: the `SendFrame` rect as a visible border with the area outside dimmed by a scrim, legible against both bright and dark scenes (FR-014). Add the `camera.sendFrame` identifier and the `camera.sendFrame.label` accessibility label — the frame is **not** decorative (FR-015). Chrome follows the screen's existing `.white`/`.black` convention (depends on T015)
- [X] T024 [US2] Build and run the full suite (`xcodebuild ... test`); confirm zero warnings and 161 tests green plus the new `SendFrameTests`
- [ ] T025 [US2] Validate quickstart.md **V2 on a physical device**: frame drawn and legible in bright and dark scenes; the confirmation image is cropped to the frame; rotation keeps frame and crop coherent
- [ ] T026 [US2] Run the **physical crop check** (SC-011, see quickstart.md) on a device, exercising the crop path in `Kalorias/Features/Camera/CaptureSessionStore.swift`: place one distinguishable food **inside** the frame and one **outside**, capture and send. **Expect only the inside food in the results.** If the outside food appears, the crop is not applied; if the inside one is missing while the outside appears, the mapping is offset or transposed. This is the check the square-pixel invariant cannot make — the invariant misses a uniform offset

**Checkpoint**: What the user frames is genuinely what gets analyzed

---

## Phase 5: User Story 3 - Zoom the camera (Priority: P3)

**Goal**: Pinch zooms the live camera, the sent photo reflects it, and the level is clamped and indicated.

**Independent Test**: On a device, zoom in, confirm the preview magnifies, capture, and confirm the photo shows the zoomed framing rather than the unzoomed scene.

### Implementation for User Story 3

- [X] T027 [P] [US3] Create `Kalorias/Features/Camera/CameraZoom.swift`: a pure `nonisolated enum` with `minimumFactor = 1.0`, `maximumUsableFactor = 5.0`, `clamp(_:deviceMaximum:)` and `isDefault(_:)`. **No AVFoundation import** — this is arithmetic and must be testable without hardware. The ceiling is 5× rather than the device's raw maximum, which is mostly digital upscaling and stops producing a picture worth analyzing (FR-018). Non-finite, zero or negative requests yield `1.0`
- [X] T028 [US3] Create `KaloriasTests/CameraZoomTests.swift` covering the 7 cases in quickstart.md §"CameraZoomTests", including the two edge devices: a device maximum **below** the 5× ceiling must clamp to the device's value, and a device maximum of **exactly 1.0** (single focal length, no digital zoom) must yield `1.0` for any request
- [X] T029 [US3] Register `CameraZoomTests.swift` in `Kalorias.xcodeproj/project.pbxproj` and `plutil -lint` it
- [X] T030 [US3] In `Kalorias/Features/Camera/CameraSessionController.swift`, retain the `AVCaptureDevice` (currently discarded — it is a local inside `configureAndStart`), expose its `maxAvailableVideoZoomFactor`, and add a `setZoom(_:)` that writes `videoZoomFactor`. Mutate the device **only on the existing session queue**, consistent with the file's already-documented `@unchecked Sendable` invariant, and extend that comment to cover the new stored reference (Principle V)
- [X] T031 [US3] In `Kalorias/Features/Camera/CaptureSessionStore.swift`, hold `zoomFactor` and route every change through `CameraZoom.clamp` before it reaches the device — the raw gesture value must never be written. Reset to `1.0` whenever the live preview starts or restarts, so a zoom left from a previous meal cannot silently frame the next one (spec Assumption). Ignore zoom changes while a photo is already captured (FR-020) (depends on T027, T030)
- [X] T032 [P] [US3] Add the US3 localization keys to `Kalorias/Resources/Localizable.xcstrings` with EN + ES and comments: `camera.zoom.indicator` (`%@×` in both — the multiplication sign is universal; the argument is the formatted factor) and `camera.zoom.label` (`Zoom` / `Zoom`)
- [X] T033 [US3] Add the pinch gesture and the indicator to `Kalorias/Features/Camera/CameraCaptureView.swift`: a magnification gesture driving the store's zoom, and an indicator with the `camera.zoomIndicator` identifier shown **only** when the factor is not the default (FR-019). Chrome follows the screen's `.white`/`.black` convention (depends on T031)
- [X] T034 [US3] Provide an **accessible alternative to pinching** in `Kalorias/Features/Camera/CameraCaptureView.swift` — an adjustable-trait control or discrete zoom steps — so zoom is usable by someone who cannot perform a two-finger gesture (FR-025). A pinch-only implementation makes the feature unavailable to those users
- [X] T035 [US3] Build and run the full suite (`xcodebuild ... test`); confirm zero warnings and 161 tests green plus `CameraZoomTests`
- [ ] T036 [US3] Validate quickstart.md **V3 on a physical device**: smooth magnification; indicator appears away from the default and disappears at 1×; a zoomed capture reflects the zoom; both limits clamp without distortion; zoom resets after discarding a photo; zoom is ignored once a photo is captured; and at maximum zoom record a judgement on crop quality (FR-013 forbids upscaling to hide the reduced pixel count)

**Checkpoint**: All three stories independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T037 Clean build with zero warnings: `xcodebuild -project Kalorias.xcodeproj -scheme Kalorias -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath /tmp/kal-008 clean build`
- [X] T038 Run the full suite (`xcodebuild ... test`): the **161** prior tests green plus `SendFrameTests` and `CameraZoomTests`, and `ImageCropperTests` at its original case count plus the new no-upscale case
- [X] T039 [P] Confirm exactly **one** crop implementation exists: grep `Kalorias/` for `UIGraphicsImageRenderer` and for any second `downsized`/crop helper — `ImageCropper` must be the only one, with `DiskImageStore` and both new callers going through it (Principle I)
- [X] T040 [P] Confirm no persistence change: `Kalorias/Features/History/MealEntry.swift` has no new stored property and no migration machinery was added anywhere; the Gemini request in `Kalorias/Features/Analysis/GeminiCalorieService.swift` is unchanged apart from nothing (FR-026)
- [X] T041 [P] Confirm no new colour token was added and `.specify/memory/constitution.md`'s token table is untouched; the camera's new chrome uses the screen's existing `.white`/`.black` convention as justified in plan.md's Complexity Tracking
- [ ] T042 Validate quickstart.md **V4** (failure paths): an undecodable picked item gives a clear message and resumes the preview; denied camera permission behaves exactly as before; airplane mode gives the existing analysis error; and no capture ever sends an image the user did not see in confirmation, including when the frame region is unavailable
- [ ] T043 Validate quickstart.md **V5**: VoiceOver reads the library control's label, conveys that only the frame's interior is sent (not "rectangle"), and announces the zoom value when present; zoom is operable without pinching; both languages show no raw key strings; Dynamic Type does not clip the new text
- [X] T044 Audit `Kalorias/Resources/Localizable.xcstrings`: all 6 new keys have EN + ES with translator comments, and no key was added and left unused (Principle I)
- [ ] T045 Walk the Definition of Done checklist at the end of quickstart.md and check off every box

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies
- **Foundational (Phase 2)**: blocks **US2 only** (see that phase's note), but sequenced first so the rename is reviewable and verifiable in isolation
- **US1 (Phase 3)**: depends on T006 (the shared downsizer) only
- **US2 (Phase 4)**: depends on Phase 2 (the renamed cropper)
- **US3 (Phase 5)**: depends on nothing in Phase 2 — fully independent
- **Polish (Phase 6)**: depends on all desired stories

### User Story Dependencies

All three are independent in substance. The coupling is **file-level**: all three edit
`CameraCaptureView.swift`, and US2 and US3 both edit `CaptureSessionStore.swift`. One developer should
carry them sequentially, or coordinate carefully on those two files.

**US1 is the MVP** and the only story validatable **without a physical device**, which makes it the
natural first slice.

### Within each story

- Pure types before the views that use them (`SendFrame` before the overlay; `CameraZoom` before the gesture)
- Each new test file immediately followed by its `project.pbxproj` registration
- Localization keys before the view that references them
- The layer boundary (T018) before the crop that consumes its output (T019)
- Story validated before starting the next priority

### Parallel Opportunities

- **T008** (catalog) alongside T009's loader work
- **T015** (`SendFrame`) and **T027** (`CameraZoom`) are `[P]` — unrelated pure files, and could be
  written by different people at any time
- **T022** and **T032** (catalog additions) are `[P]` with their stories' view work
- **T039, T040, T041** are `[P]` — read-only verification passes

---

## Parallel Example: the two pure types

```bash
# Independent files, no AVFoundation, testable without hardware — launch together:
Task: "Create Kalorias/Features/Camera/SendFrame.swift with a centred-square rect(in:)"
Task: "Create Kalorias/Features/Camera/CameraZoom.swift with clamp(_:deviceMaximum:)"

# Then each story's boundary + view work proceeds sequentially on the shared camera files.
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1 Setup — baseline 161, seed the simulator's library
2. Phase 2 Foundational — the rename and the shared downsizer, verified to lose no coverage
3. Phase 3 US1 — the picker
4. **STOP and VALIDATE**: V1 on the simulator, especially **no permission prompt** and the
   camera-unavailable path
5. Shippable: a second way into the app that works even with no usable camera

### Incremental Delivery

1. Setup + Foundational → one canonical image-geometry utility
2. + US1 → library picker → validate on the simulator → **MVP**
3. + US2 → send framing → validate **on a device**, including the physical crop check
4. + US3 → zoom → validate **on a device**
5. Phase 6 Polish → warnings, failure paths, accessibility, wording

### Notes

- Commit after each task or logical group — **manually**; the constitution forbids automated tooling
  from running `git commit`/`git push` or offering to
- Do **not** author or run UI tests (Principle II)
- **No persistence change, no migration, no new colour token.** `CaptureState` gains no case
- **US2 and US3 cannot be validated on the simulator.** Do not mark their validation tasks done from a
  simulator run
- The three tasks that keep this honest are **T020** (the square-pixel invariant, standing in for a
  unit test that cannot exist), **T026** (the physical check, catching the offset the invariant misses),
  and **T021** (never silently sending an uncropped photo when the region is unavailable)

---

## Validation record

**Build**: clean, **zero warnings** under Swift 6 strict concurrency, for both the simulator and the
**physical device** (signed with a valid Apple Development identity).

**Tests**: **178 passing, 0 failures** — 161 baseline + 8 `SendFrameTests` + 9 `CameraZoomTests`.
`ImageCropperTests` reports **11 cases**, exactly the count recorded in T001 before the rename, so no
coverage was lost.

**Verification passes (T039–T041, T044)**

| Check | Result |
|---|---|
| One crop implementation | ✅ `ImageCropper` is the only `UIGraphicsImageRenderer` site and the only `downsized` definition |
| No persistence change | ✅ no migration machinery; `MealEntry` still has its 6 stored properties; Gemini schema untouched |
| No new colour token | ✅ 13 `AppColor` tokens, 13 colorsets — unchanged |
| Localization | ✅ all 6 new keys have EN + ES with translator comments |

**US1 verified on the simulator**: with the camera unavailable, the library control **is present and
usable** (FR-005) — screenshotted. This is the path the simulator tests best, and it is the whole point
of having a second image source.

**Deployed to a real device** (iPhone 15 Pro Max, iOS 26.5.2): installs and launches cleanly.

### Not verified — interactive, needs a person

| Task | Why |
|---|---|
| T014 (rest of V1) | Tapping through picker → confirm → send cannot be scripted |
| T025, T026 (V2 on device) | `simctl`/`devicectl` cannot drive the camera or take screenshots of a physical device |
| T036 (V3 on device) | Pinch gesture cannot be scripted |
| T042, T043, T045 | Failure paths, VoiceOver, appearance, language — all interactive |

**The build on your phone is a Debug build, which matters**: the square-pixel assertion in
`CaptureSessionStore.assertSquarePixels` is live. If the frame→image mapping is transposing axes,
ignoring the aspect-fill crop, or applying the wrong orientation, **taking a photo will trap with a
message naming the cause** rather than silently producing an offset crop. That converts the one
untestable boundary into something that fails loudly the first time you use it.

The physical crop check (T026) is still the one thing worth doing deliberately: put one food inside the
frame and one outside, send, and confirm only the inside one comes back. The assertion cannot catch a
uniform offset; that check can.

---

## Correction after device testing

The first implementation of the frame→crop mapping was **wrong**, the runtime invariant caught it, and
the fix removed the untestable boundary altogether.

**What happened**: T018 used `metadataOutputRectConverted(fromLayerRect:)`. Its result is in the
sensor's landscape buffer space; the captured `UIImage` reports an orientation-corrected size. Mixing
them transposed the axes. On device, the first capture tripped T020's assertion:

```
Assertion failed: Send-frame crop is not square (3563x6334).
```

`6334/3563 = 1.778` — 16:9, axes swapped relative to the predicted 4:3.

**The fix**: the mapping moved into `SendFrame.imageRegion(previewSize:imageSize:)`, computed purely in
the image's own coordinate space. It works because the preview is centred aspect-fill and the frame is
a centred square, so a square of side `s` in the preview is a centred square of side `s / fillScale` in
the image — no rotation involved. `CameraPreviewLayerView` no longer converts anything.

**What this bought**: the boundary T018 declared untestable **no longer exists**. `SendFrameTests`
gained 6 mapping cases, and they were verified to discriminate — reintroducing the transposition fails
**10 of 14**, the fix passes all 14. The runtime assertion is kept as a cheap belt-and-braces guard.

**Reflection worth keeping**: the plan chose the framework API precisely *because* it looked
authoritative for this conversion, and that is what made the bug plausible enough to ship. The
invariant designed to compensate for an untestable boundary is what turned a silently-offset crop into
a loud, self-describing failure on the very first capture. Both halves of that design earned their
keep — but the better outcome was not needing the boundary at all.
