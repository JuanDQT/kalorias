---

description: "Task list for Bottom Navigation & Camera Capture"
---

# Tasks: Bottom Navigation & Camera Capture

**Input**: Design documents from `/specs/001-bottom-nav-camera/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/ui-contracts.md, quickstart.md

**Tests**: Unit tests ARE included — the constitution (Principle II) mandates
unit tests for testable business logic; here that is the permission, capture,
and navigation state machines. **UI tests (XCUITest) are excluded** (off by
default per Principle II); accessibility identifiers are still added so flows
are UI-testable later.

**Organization**: Tasks are grouped by user story. Each story is an independently
testable increment.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 / US2 / US3
- All paths are repository-relative. The app target uses filesystem-synchronized
  Xcode groups, so new files under `Kalorias/` are picked up automatically.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and prerequisites shared by all stories.

- [x] T001 Add a `KaloriasTests` XCTest unit-test target to `Kalorias.xcodeproj` and enable it in the `Kalorias` scheme's Test action
- [x] T002 [P] Create `Kalorias/Resources/Localizable.xcstrings` with English + Spanish values for keys: `permission.title`, `permission.body`, `permission.continue`, `permission.openSettings`, `camera.capture`, `camera.send`, `camera.cancel`, `camera.unavailable`, `tab.progress`, `tab.history`
- [x] T003 [P] Set `INFOPLIST_KEY_NSCameraUsageDescription` (localized EN + ES) in the `Kalorias` target build settings
- [x] T004 [P] Create the feature source folders `Kalorias/App/`, `Kalorias/Features/Progress/`, `Kalorias/Features/History/`, `Kalorias/Features/Camera/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core navigation types every story depends on.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [x] T005 Create `AppTab` enum (`progress`, `history`) in `Kalorias/App/AppTab.swift`
- [x] T006 Create `Router` as an `@Observable @MainActor` type in `Kalorias/App/Router.swift` with `selectedTab: AppTab` (default `.progress`), `isCameraPresented: Bool`, and intents `select(_:)`, `presentCamera()`, `dismissCamera()` (depends on T005)

**Checkpoint**: Navigation foundation ready — user stories can begin.

---

## Phase 3: User Story 1 - Navigate the app through a bottom bar (Priority: P1) 🎯 MVP

**Goal**: Persistent bottom bar with Progress/History tabs and a prominent green center Camera action; Progress shown by default.

**Independent Test**: Launch app → 3 bar items visible, Progress shown; tapping Progress/History swaps their placeholder screens; center camera is brand-green and distinct. Verified in light and dark.

### Tests for User Story 1

- [x] T007 [US1] `RouterTests` in `KaloriasTests/RouterTests.swift`: default `selectedTab == .progress`; `select(.history)` switches; `presentCamera()`/`dismissCamera()` toggle `isCameraPresented` while leaving `selectedTab` unchanged

### Implementation for User Story 1

- [x] T008 [P] [US1] Create `ProgressPlaceholderView` (empty placeholder, `AppColor` tokens) in `Kalorias/Features/Progress/ProgressPlaceholderView.swift`
- [x] T009 [P] [US1] Create `HistoryPlaceholderView` (empty placeholder, `AppColor` tokens) in `Kalorias/Features/History/HistoryPlaceholderView.swift`
- [x] T010 [US1] Create the shared `BottomBar` helper in `Kalorias/DesignSystem/BottomBar.swift` using **native** Liquid Glass (`GlassEffectContainer` + `.glassEffect`): three items (Progress, Camera, History), center camera icon in `AppColor.brandPrimary` visually distinct; accessibility identifiers `tab.progress`, `tab.history`, `bottomBar.cameraButton`; exposes tab-select and camera-tap callbacks
- [x] T011 [US1] Create `RootView` in `Kalorias/App/RootView.swift`: renders content for `Router.selectedTab` (Progress/History placeholders) above the `BottomBar`; camera-tap callback wired to a placeholder no-op for now (full behavior added in US2)
- [x] T012 [US1] Update `Kalorias/KaloriasApp.swift` to create + inject `Router` into the environment and present `RootView`; remove the old `ContentView` sample usage

**Checkpoint**: Bottom bar navigation is fully functional and independently testable.

---

## Phase 4: User Story 2 - Grant camera access before first capture (Priority: P2)

**Goal**: Full-screen rationale gates the camera, drives the native prompt, repeats until granted, and offers Settings when permanently denied.

**Independent Test**: With permission not granted, tapping the camera shows the rationale; Continue triggers the native prompt; after denial the rationale reappears instead of the camera; when permanently denied, Continue offers Open Settings.

### Tests for User Story 2

- [x] T013 [US2] `CameraPermissionStoreTests` in `KaloriasTests/CameraPermissionStoreTests.swift`: verify the status mapping and derived flags `canRequestNatively` (notDetermined), `isPermanentlyBlocked` (denied/restricted), `isAuthorized` (authorized)

### Implementation for User Story 2

- [x] T014 [P] [US2] Create `CameraPermissionStatus` enum (`notDetermined`, `authorized`, `denied`, `restricted`) with derived flags in `Kalorias/Features/Camera/CameraPermissionStatus.swift`
- [x] T015 [US2] Create `CameraPermissionStore` (`@Observable @MainActor`) in `Kalorias/Features/Camera/CameraPermissionStore.swift`: `status`, `refresh()` (read `AVCaptureDevice.authorizationStatus`), `requestAccess() async` (`AVCaptureDevice.requestAccess`), `openSettings()` (`UIApplication.openSettingsURLString`) (depends on T014)
- [x] T016 [US2] Create `CameraPermissionView` (full-screen) in `Kalorias/Features/Camera/CameraPermissionView.swift`: localized rationale copy, primary button that calls `requestAccess()` when notDetermined else `openSettings()`, `refresh()` on appear/foreground (handles granted-in-Settings edge case), native glass/material surfaces + `AppColor` tokens, accessibility ids `permission.screen` / `permission.continueButton`
- [x] T017 [US2] Wire the camera tap in `Kalorias/App/RootView.swift`: consult `CameraPermissionStore.status` → `authorized` calls `Router.presentCamera()`, otherwise present `CameraPermissionView` (and open the camera automatically if it becomes authorized); inject `CameraPermissionStore` into the environment in `Kalorias/KaloriasApp.swift`

**Checkpoint**: Permission gate works end-to-end; camera never opens until granted.

---

## Phase 5: User Story 3 - Capture a photo of food (Priority: P3)

**Goal**: Rear camera full-screen with a capture button that becomes Send after a shot; Send/cancel closes the camera and returns to the prior tab.

**Independent Test**: With permission granted, tapping the camera shows the rear preview + centered capture button; capture swaps it to Send; Send closes the camera and returns to the previous tab; cancel before capture returns with no photo.

### Tests for User Story 3

- [x] T018 [US3] `CaptureSessionStateTests` in `KaloriasTests/CaptureSessionStateTests.swift`: capture-state transitions `previewing → captured(image)` on capture, `captured → previewing` on reset, and the `unavailable(message)` path

### Implementation for User Story 3

- [x] T019 [P] [US3] Create `CaptureState` enum (`previewing`, `captured(UIImage)`, `unavailable(String)`) in `Kalorias/Features/Camera/CaptureState.swift`
- [x] T020 [P] [US3] Create `CameraPreviewLayerView` (`UIViewRepresentable` wrapping `AVCaptureVideoPreviewLayer`) in `Kalorias/Features/Camera/CameraPreviewLayerView.swift`
- [x] T021 [US3] Create `CaptureSessionStore` (`@Observable @MainActor`) in `Kalorias/Features/Camera/CaptureSessionStore.swift`: owns `AVCaptureSession` (rear `.builtInWideAngleCamera`/`.back` input + `AVCapturePhotoOutput`); `start()`/`stop()`/`capturePhoto()`/`reset()` with all session configuration and running work on a private serial queue (never main thread), UI state updated on the main actor, `unavailable` set when no usable camera (depends on T019, T020)
- [x] T022 [US3] Create `CameraCaptureView` in `Kalorias/Features/Camera/CameraCaptureView.swift`: full-screen `CameraPreviewLayerView`; center control shows Capture (previewing) then Send (captured); Cancel control; clear localized message for `unavailable`; accessibility ids `camera.screen`, `camera.preview`, `camera.captureButton`, `camera.sendButton`, `camera.cancelButton`, `camera.unavailableMessage`; `AppColor` tokens + native surfaces (depends on T021)
- [x] T023 [US3] Present `CameraCaptureView` as a `fullScreenCover(isPresented:)` bound to `Router.isCameraPresented` in `Kalorias/App/RootView.swift`; Send and Cancel call `CaptureSessionStore.stop()` + `Router.dismissCamera()`, returning to the prior tab

**Checkpoint**: Full photo-capture flow works on a physical device; returns to the correct tab.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Constitution-gate verification across all stories.

- [x] T024 [P] Verify every new screen renders correctly in both light and dark appearances (Principle VI)
- [x] T025 [P] Verify Dynamic Type and VoiceOver labels for all new screens and controls; confirm accessibility identifiers match `contracts/ui-contracts.md`
- [x] T026 Confirm the build succeeds with zero warnings under Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete`)
- [x] T027 Confirm English + Spanish values exist for every key in `Kalorias/Resources/Localizable.xcstrings`
- [~] T028 Run the `quickstart.md` validation scenarios — US1 validated on Simulator (light+dark screenshots) and all 11 unit tests green; US2 permission flow, camera-unavailable, and US3 capture remain a manual/on-device step (no CLI tap tooling / UI tests are off by default)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately.
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories.
- **User Stories (Phase 3–5)**: All depend on Foundational. US2 builds on US1's `RootView`; US3 opens via US2's gate. Recommended order P1 → P2 → P3.
- **Polish (Phase 6)**: After the desired stories are complete.

### User Story Dependencies

- **US1 (P1)**: After Foundational. No dependency on other stories (MVP).
- **US2 (P2)**: After US1 (extends `RootView`'s camera-tap wiring). Independently testable via the permission flow.
- **US3 (P3)**: After US2 (opens through the granted gate). Independently testable with permission pre-granted.

### Within Each User Story

- Write the unit test task first, watch it fail, then implement.
- Enums/models before stores; stores before views; view wiring last.
- Story complete and validated before moving to the next priority.

### Parallel Opportunities

- Setup: T002, T003, T004 in parallel.
- US1: T008 and T009 in parallel (different placeholder files).
- US2: T014 in parallel with US1 polish (different file).
- US3: T019 and T020 in parallel (different files).
- Polish: T024 and T025 in parallel.

---

## Parallel Example: User Story 1

```bash
# After T007 (RouterTests) is written and failing, build the placeholders together:
Task: "Create ProgressPlaceholderView in Kalorias/Features/Progress/ProgressPlaceholderView.swift"
Task: "Create HistoryPlaceholderView in Kalorias/Features/History/HistoryPlaceholderView.swift"
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1 Setup → 2. Phase 2 Foundational → 3. Phase 3 US1 → **STOP & VALIDATE**
   the bottom bar independently (tabs switch, green camera, light/dark). Demoable MVP.

### Incremental Delivery

1. Setup + Foundational → foundation ready.
2. US1 → test → demo (MVP: navigation shell).
3. US2 → test → demo (permission gate).
4. US3 → test on device → demo (capture flow).
5. Polish → constitution gates green.

---

## Notes

- [P] = different files, no dependencies.
- UI tests are intentionally absent (off by default, Principle II); a11y ids are
  added now so a future maintainer-triggered UI-test pass has stable hooks.
- `Send` is a stub in this feature (closes camera); the Gemini upload/estimate is
  a later feature.
- Commit after each task or logical group (commits remain a manual human action
  per the constitution).
