# Quickstart & Validation: Meal History & Local Persistence

A run/validation guide. Implementation details live in `tasks.md` and the code.

## Prerequisites

- Features 001 (camera) and 002 (analysis) working; a Gemini key configured
  (`Config/Secrets.xcconfig`) for producing real successful analyses.
- A **physical device** for the end-to-end path (capture → analyze → save); unit
  tests need neither camera nor network.

## Build & unit tests (no camera/network)

```bash
xcodebuild -project Kalorias.xcodeproj -scheme Kalorias \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build

xcodebuild -project Kalorias.xcodeproj -scheme Kalorias \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test
```

Expected: zero warnings under Swift 6 strict concurrency; these suites pass:
- `MealTitleTests` — single food ⇒ dish name; multiple ⇒ ingredient list.
- `ImageStoreTests` — save→load round-trip in a temp dir; missing file ⇒ nil.
- `MealHistoryRepositoryTests` — with an **in-memory** `ModelContainer`: `record`
  inserts one entry (right foods/total/title); a second `record` adds a second entry
  (no overwrite); fetch is newest-first.

## Manual validation

### US1 — Auto-save (device)
1. Capture food → analysis succeeds → total shown.
2. **Force-close** and relaunch the app.
3. Open the History tab → the meal is there. (US1 AS1/AS2, SC-001)
4. Trigger a no-food or error analysis → no new entry appears. (US1 AS3, FR-003)

### US2 — List (device or seeded)
1. History tab shows saved meals, newest first, each with thumbnail (left),
   title + nutrition (center), date + total (right). (US2 AS1/AS2, FR-005/FR-006)
2. A single-food meal shows the dish name; a multi-food meal shows the ingredient
   list. (US2 AS3/AS4, FR-007)
3. With no meals, the empty state shows. (US2 AS5, FR-008)
   Verify light and dark.

### US3 — Details (device or seeded)
1. Tap a meal → a new details screen opens with the larger photo, full food
   breakdown (calories + macros), total, and date. (US3 AS1/AS2, FR-010)
2. Back returns to the list. (US3 AS3)

### Offline & performance
- Turn off the network → History and details still work. (FR-011, SC-005)
- With many entries, the list opens quickly and scrolls smoothly. (SC-002)

## Definition of done

- All unit suites green; build warning-free under Swift 6 strict concurrency.
- Successful analyses persist and survive relaunch; failures/no-food do not.
- Each entry's total equals its foods' sum.
- New strings present EN + ES; list/details verified light + dark.
- Colors from `AppColor`; surfaces use native Liquid Glass; photos stored as
  downsized files (not DB blobs); data stays on-device.
