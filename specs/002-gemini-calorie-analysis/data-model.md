# Phase 1 Data Model: Photo Calorie Analysis

No persistence. All types are transient, `Sendable` value types (models) or a
`@MainActor` store. Domain models are decoupled from the Gemini wire format:
`GeminiCalorieService` decodes wire DTOs and maps them into these domain types.

## FoodItem (Sendable, value type)

One recognized food.

| Field | Type | Notes |
|-------|------|-------|
| `name` | `String` | Localized-ish display name from the model (shown as-is). |
| `calories` | `Int` | Estimated kcal for this item (≥ 0). |
| `proteinGrams` | `Double?` | Optional macro (FR-008). |
| `carbsGrams` | `Double?` | Optional macro. |
| `fatGrams` | `Double?` | Optional macro. |

## CalorieAnalysis (Sendable, value type)

A successful, food-bearing result.

| Field | Type | Notes |
|-------|------|-------|
| `items` | `[FoodItem]` | Non-empty for a success (empty ⇒ `noFood` outcome). |
| `totalCalories` | `Int` | **Derived** via `CalorieAggregator` = Σ `items.calories` (FR-006). Not taken from the wire `total`. |

## AnalysisOutcome (Sendable)

The result of one analysis attempt.

| Case | Meaning | UI |
|------|---------|----|
| `success(CalorieAnalysis)` | Foods detected | total + breakdown |
| `noFood` | Valid response, no identifiable food | "no food detected" + Retake/Cancel (FR-012) |

(Failures are thrown as `AnalysisError`, not part of `AnalysisOutcome`.)

## AnalysisError (Sendable, Error)

| Case | Source | Message intent |
|------|--------|----------------|
| `noConnection` | `URLError.notConnectedToInternet` / `.networkConnectionLost` | "No internet connection" |
| `timeout` | `URLError.timedOut` / request deadline | "Took too long" |
| `serviceError` | non-2xx / API error body | "Service problem" |
| `invalidResponse` | decode/schema mismatch, missing fields | "Couldn't read the result" |

All map to a localized message + **Retry** + **Cancel** (FR-011). None ever
yields a displayed calorie number.

## CalorieAnalyzing (protocol, Sendable)

The boundary that hides Gemini (Principle V).

```
func analyze(imageData: Data) async throws -> AnalysisOutcome
```

- Real impl: `GeminiCalorieService`.
- Test impl: a mock returning canned outcomes/errors.

## CalorieAggregator (pure, testable — Principle I/II)

- `total(of items: [FoodItem]) -> Int` = Σ `calories`.
- `make(from items: [FoodItem]) -> AnalysisOutcome` = `items.isEmpty ? .noFood : .success(CalorieAnalysis(items:, totalCalories: total))`.
- Unit-tested: multi-item sum, single item, empty ⇒ `noFood`.

## AnalysisState (drives the result screen)

| Case | Meaning | Controls |
|------|---------|----------|
| `analyzing` | Request in flight | spinner + **Cancel** (FR-002) |
| `result(CalorieAnalysis)` | Success | total + breakdown + **Done** |
| `noFood` | No food detected | message + **Retake** + **Cancel** |
| `failed(AnalysisError)` | Failure | message + **Retry** + **Cancel** |

## CalorieAnalysisStore (`@MainActor @Observable`)

| Property | Type | Notes |
|----------|------|-------|
| `state` | `AnalysisState` | Starts `analyzing`. |
| private `imageData` | `Data` | The captured photo (set at init). |
| private `analyzer` | `any CalorieAnalyzing` | Injected (real or mock). |
| private `task` | `Task<Void, Never>?` | The in-flight analysis, cancelable. |

Intents:
- `start()` — run `analyzer.analyze` in a cancelable `Task`; map result →
  `result`/`noFood`, thrown `AnalysisError` → `failed`. Single-flight: ignores a
  call while a task is running (FR-014).
- `retry()` — re-run with the same `imageData` (FR-013).
- `cancel()` — cancel the task and end the flow (FR-002/FR-015).

State transitions:
```
init → analyzing
analyzing --success(items≠∅)--> result
analyzing --success(items=∅)/noFood--> noFood
analyzing --throws AnalysisError--> failed
failed --retry--> analyzing
noFood --retake/cancel--> (dismiss)
result --done--> (dismiss)
any --cancel--> (dismiss, task cancelled)
```

## Relationships

- `CameraCaptureView` (feature 001) creates a `CalorieAnalysisStore(imageData:,
  analyzer:)` on **Send** and presents `AnalysisResultView`.
- The store calls `CalorieAnalyzing`; `GeminiCalorieService` decodes wire DTOs and
  uses `CalorieAggregator` to build the domain `AnalysisOutcome`.
- Dismissing any terminal state calls `Router.dismissCamera()` (feature 001).
