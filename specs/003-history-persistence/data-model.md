# Phase 1 Data Model: Meal History & Local Persistence

Persisted with SwiftData. The photo is a file on disk referenced by name; foods are
stored as a `Codable` value on the model. Reuses feature 002's `FoodItem` for
mapping but persists a lightweight `StoredFood` to avoid coupling the DB schema to
UI types.

## StoredFood (Codable, Sendable value)

Persisted per-food snapshot (independent of feature 002's `FoodItem`).

| Field | Type | Notes |
|-------|------|-------|
| `name` | `String` | Food name. |
| `calories` | `Int` | ≥ 0. |
| `protein` | `Double?` | Optional macro. |
| `carbs` | `Double?` | Optional macro. |
| `fat` | `Double?` | Optional macro. |

Mapping: `StoredFood(from: FoodItem)` and back for display.

## MealEntry (`@Model`)

One saved meal.

| Field | Type | Notes |
|-------|------|-------|
| `id` | `UUID` | Stable identifier (also names the image file). |
| `capturedAt` | `Date` | When taken; list sort key (reverse). |
| `title` | `String` | Derived at save (dish name or ingredient list, FR-007). |
| `totalCalories` | `Int` | = Σ `foods.calories` (FR-013), stored for fast rows. |
| `foods` | `[StoredFood]` | The detected foods (Codable value column). |
| `imageFileName` | `String` | Basename of the JPEG in the image directory. |

Validation / invariants:
- `totalCalories == foods.reduce(0){$0+$1.calories}` at creation.
- Created only from a successful analysis with a non-empty `foods` (FR-001/FR-003).

## MealTitle (pure, testable)

- `make(from foods: [FoodItem]) -> String`:
  - exactly one food ⇒ that food's `name` (the "dish").
  - more than one ⇒ comma-joined names (the "ingredients").
  - empty ⇒ empty string (never persisted — success requires foods).
- Unit-tested: single, multiple, ordering preserved.

## ImageStore (protocol + disk impl)

- `save(_ image: UIImage, id: UUID) async throws -> String` — downsize (~1024px max),
  JPEG-encode + write off-main to `Application Support/MealImages/<id>.jpg`, return
  the filename.
- `loadImage(named: String) -> UIImage?` — nil when missing/unreadable (placeholder).
- `delete(named: String)` — remove the file (used if an entry is ever removed).
- Unit-tested against a temp directory: save→load round-trip; missing ⇒ nil.

## MealRecording (protocol — the success boundary)

```
func record(image: UIImage?, analysis: CalorieAnalysis, date: Date) async
```

- Real impl: `MealHistoryRepository`.
- Called once by `CalorieAnalysisStore` on `.result` (FR-001/FR-004); never on
  no-food/failed (FR-003).

## MealHistoryRepository (`@MainActor`, conforms to `MealRecording`)

Owns the `ModelContext` and `ImageStore`.

| Intent | Behavior |
|--------|----------|
| `record(image:analysis:date:)` | write image via `ImageStore` (off-main), build `MealEntry` (title via `MealTitle`, total from analysis, `StoredFood` mapping), insert + save on the main-actor context. |
| `entries()` | fetch all, `capturedAt` descending (used by tests; the view uses `@Query`). |

Unit-tested with an in-memory `ModelContainer`: record inserts one entry with the
right foods/total/title; a second record makes a second entry (no overwrite,
FR-004); fetch is newest-first (FR-005).

## Navigation (Router additions)

| Property / intent | Purpose |
|-------------------|---------|
| `historyPath: [MealEntry.ID]` (or `[MealEntry]`) | NavigationStack path for the History tab. |
| `openMeal(_:)` | append an entry to the history path (row tap → details, FR-009). |
| `popHistory()` / binding | back to the list. |

## Relationships

- `CameraCaptureView` builds `CalorieAnalysisStore(..., recorder: repository)`; on
  `.result`, the store calls `recorder.record(...)`.
- `HistoryView` (`@Query`) lists `MealEntry` newest-first; a row tap → `Router.openMeal`
  → `navigationDestination` → `MealDetailsView(entry:)`.
- `MealRowView` / `MealDetailsView` load the photo via `ImageStore.loadImage`.
- Nothing here touches the network; all data stays on-device (FR-015).
