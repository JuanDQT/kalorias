# Phase 0 Research: Meal History & Local Persistence

No open `NEEDS CLARIFICATION` items. Decisions below lock the approach.

## R1. Persistence engine — SwiftData

- **Decision**: Use **SwiftData** (`@Model MealEntry`, `ModelContainer`, `@Query`).
  Foods are stored as a `[StoredFood]` value (a `Codable` struct) on the model;
  total, title, date, and image filename are stored columns.
- **Rationale**: The constitution names SwiftData/Core Data as the required native
  persistence; SwiftData integrates with SwiftUI/Observation, gives reactive lists
  via `@Query`, and supports in-memory containers for fast unit tests.
- **Alternatives considered**: Core Data (heavier boilerplate for the same result);
  Codable-to-JSON file (loses querying/sorting and reactive updates); no persistence
  (fails the whole feature).

## R2. Where the photo lives — files on disk, not DB blobs

- **Decision**: Store the captured photo as a **downsized JPEG file** in Application
  Support (`.../MealImages/<uuid>.jpg`); `MealEntry` keeps only the filename. An
  `ImageStore` handles downsizing (max ~1024px), writing, loading, and deletion.
- **Rationale**: Keeping large binaries out of the SwiftData store keeps queries and
  scrolling fast (SC-002, FR-012). A single moderate JPEG serves both the row
  thumbnail (downsampled on load) and the details view.
- **Alternatives considered**: `@Attribute(.externalStorage)` blob — workable but
  still couples image lifecycle to the store and complicates test isolation;
  full-resolution originals — unnecessary storage/scroll cost.

## R3. Threading for save — off-main image IO

- **Decision**: `MealHistoryRepository.record(...)` encodes + writes the JPEG off the
  main thread, then inserts the `MealEntry` on the main-actor `ModelContext`.
  SwiftData context work stays on the main actor; only the image encode/write is
  backgrounded.
- **Rationale**: JPEG encoding of a photo is the expensive part; doing it off-main
  satisfies FR-012/SC-006. The DB insert itself is cheap.
- **Alternatives considered**: doing everything on the main thread (janky on large
  photos); a background ModelContext/actor (added complexity not needed at this
  scale).

## R4. Recording on analysis success — a boundary, not coupling

- **Decision**: Introduce a `MealRecording` protocol
  (`func record(image:analysis:date:) async`). `CalorieAnalysisStore` calls it once
  when it reaches `.result`; `MealHistoryRepository` implements it. Feature 002 stays
  unaware of SwiftData. No-food/failed outcomes never call `record` (FR-003).
- **Rationale**: Keeps the camera/analysis code decoupled from persistence and keeps
  the "save exactly once per success" rule in one place; the recorder is injectable
  (nil in existing analysis tests, a mock elsewhere).
- **Alternatives considered**: saving from the result view (business logic in a
  view — violates Principle V); a global notification (harder to test/trace).

## R5. Title derivation — pure and testable

- **Decision**: `MealTitle.make(from foods:)` returns the single food's name when
  there is exactly one, otherwise a comma-joined ingredient list (FR-007). Computed
  once at save time and stored on the entry for cheap list rendering.
- **Rationale**: Pure function → trivially unit-tested; storing it avoids recomputing
  per row. A dedicated dish-name field could be added to the analysis later without
  changing this contract.
- **Alternatives considered**: deriving in the view each render (repeated work,
  untestable); requiring a dish name from Gemini now (out of scope for this feature).

## R6. List reads & details navigation

- **Decision**: `HistoryView` uses `@Query(sort: \.capturedAt, order: .reverse)` for a
  reactive, newest-first list; tapping a row calls a `Router` intent that appends to
  a history navigation path, and a single `navigationDestination` shows
  `MealDetailsView`. The tab is wrapped in a `NavigationStack(path:)` bound to the
  Router.
- **Rationale**: `@Query` is SwiftData's sanctioned reactive read path (new saves
  appear automatically); routing the drill-in through the Router keeps navigation
  state centralized (Principle V).
- **Alternatives considered**: fetching manually into a store property (loses
  automatic updates, more code); inline `NavigationLink` destinations (navigation not
  owned by the Router).

## R7. Empty state & missing images

- **Decision**: When `@Query` is empty, show a clear empty state (icon + message).
  When an image file is missing/unreadable, `ImageStore` returns nil and the
  row/details render a placeholder while still showing the text data (edge cases).
- **Rationale**: Directly satisfies FR-008 and the missing-image edge case; the UI
  never blanks or crashes on absent files.

## Resolved unknowns

None outstanding. Proceed to Phase 1.
