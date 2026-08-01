# UI Contracts: Meal History & Local Persistence

Repository/store intents, screen states, accessibility identifiers, and
localization keys. (UI tests are off by default per Principle II; identifiers are
added now so a future maintainer-triggered UI-test pass has stable hooks.)

## Intent contracts

### MealRecording (injected into CalorieAnalysisStore)
- `record(image:analysis:date:) async` — persist one meal; called once on `.result`.

### MealHistoryRepository
- `record(...)` → writes image file + inserts a `MealEntry`.
- `entries()` → newest-first fetch (view uses `@Query` instead).

### Router
- `openMeal(_ entry)` → push the details screen for that entry.
- history path binding → drives the History `NavigationStack`.

## Screen state contracts

### History tab (`HistoryView`)
| Condition | Shows |
|-----------|-------|
| entries present | list of `MealRowView`, newest-first (FR-005) |
| no entries | empty state (icon + message, FR-008) |

### Meal row (`MealRowView`) — layout (FR-006)
- **Left**: small photo thumbnail (placeholder if the file is missing).
- **Center**: title (dish/ingredients, FR-007) with nutrition data (macros) below.
- **Right**: date taken and total calories.

### Meal details (`MealDetailsView`) — (FR-010)
- Larger photo, full itemized foods (name + calories + macros), total calories,
  and the date/time taken. Back returns to the list (FR-009 AS3).

## Accessibility identifiers (stable)

| Identifier | Element |
|------------|---------|
| `history.list` | The meal list |
| `history.empty` | Empty-state container |
| `history.row` | A meal row (with the entry id available for tests) |
| `history.row.title` | Row title |
| `history.row.total` | Row total calories |
| `history.row.date` | Row date |
| `mealDetails.screen` | Details container |
| `mealDetails.total` | Details total |
| `mealDetails.foodList` | Details itemized list |

## Localization keys (EN + ES required — FR-014)

`history.title`, `history.empty.title`, `history.empty.message`,
`history.kcalUnit`, `history.macro.protein`, `history.macro.carbs`,
`history.macro.fat`, `mealDetails.title`, `mealDetails.totalLabel`,
`mealDetails.takenAt`. (Reuse feature 002's `analysis.macro.*` where equivalent to
avoid duplication.)
