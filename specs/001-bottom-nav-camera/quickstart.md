# Quickstart & Validation: Bottom Navigation & Camera Capture

A run/validation guide for this feature. Implementation details live in
`tasks.md` (after `/speckit-tasks`) and the code itself.

## Prerequisites

- Xcode 26+ with an iOS 26.5 simulator, plus a **physical iPhone** for the
  actual capture step (the Simulator has no camera → exercises the
  "unavailable" path only).
- `INFOPLIST_KEY_NSCameraUsageDescription` set (localized) — required before the
  app may request camera access.

## Build & unit tests

```bash
# Build for simulator
xcodebuild -project Kalorias.xcodeproj -scheme Kalorias \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build

# Unit tests (state machines) — requires the new KaloriasTests target
xcodebuild -project Kalorias.xcodeproj -scheme Kalorias \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Expected: build succeeds with **zero warnings** under Swift 6 strict
concurrency; `CameraPermissionStoreTests`, `CaptureSessionStateTests`, and
`RouterTests` pass.

## Manual validation (maps to acceptance scenarios)

### US1 — Bottom bar (Simulator OK)
1. Launch → bottom bar shows 3 items; **Progress** is selected. (US1 AS1, FR-003)
2. Tap **History** → History placeholder shows, bar stays visible. (US1 AS2)
3. Tap **Progress** → Progress placeholder returns. (US1 AS3)
4. Center item is a **green** camera, visually distinct. (US1 AS4, FR-006)
   Verify in both light and dark appearance (Principle VI).

### US2 — Permission gate (Simulator OK)
1. First tap on the camera (permission not granted) → full-screen rationale.
   (US2 AS1, FR-007)
2. Tap **Continue** → native OS prompt appears. (US2 AS2, FR-008)
3. Deny it, tap the camera again → rationale reappears, camera does NOT open.
   (US2 AS3, FR-009)
4. In Settings, permanently deny → on the rationale, **Continue** offers Open
   Settings. (US2 AS5, FR-010)

### US3 — Capture (physical device)
1. With access granted, tap the camera → rear live preview + centered capture
   button in < 2s. (US3 AS1, SC-002, FR-012/FR-013)
2. Tap **Capture** → still shown, button becomes **Send**. (US3 AS2, FR-014)
3. Tap **Send** → camera closes, returns to the tab shown before opening.
   (US3 AS3, FR-015, SC-004)
4. Reopen, cancel before capturing → returns to prior tab, no photo. (US3 AS4,
   FR-016)

### Edge cases
- On the **Simulator** (no camera), opening the camera shows the clear
  "camera unavailable" message, not a blank/frozen frame. (FR-017)
- Grant permission in Settings while the rationale is open → next attempt opens
  the camera (no re-prompt).

## Definition of done for this feature

- All manual scenarios above pass on the stated targets.
- Build is warning-free under Swift 6 strict concurrency; unit tests green.
- All new strings present in EN + ES; UI verified in light and dark.
- All colors sourced from `AppColor`; glass surfaces use native `.glassEffect` /
  `GlassEffectContainer` (no imitations).
- `Send` remains a stub (closes camera); no network/Gemini call yet.
