# UI Contracts: Photo Calorie Analysis

Store intents, screen states, accessibility identifiers, and localization keys.
(UI tests are off by default per Principle II; identifiers are added now so a
future maintainer-triggered UI-test pass has stable hooks.)

## Store intent contracts

### CalorieAnalysisStore
- `start()` → `state` becomes `analyzing`, then `result` / `noFood` / `failed`.
- `retry()` → re-analyze the same photo; `state` returns to `analyzing`.
- `cancel()` → cancel the in-flight task and end the flow.

### CalorieAnalyzing (injected)
- `analyze(imageData:) async throws -> AnalysisOutcome` — real = Gemini, test = mock.

## Screen state contracts — `AnalysisResultView` by `state`

| state | Shows | Controls |
|-------|-------|----------|
| `analyzing` | photo thumbnail + spinner + "Analyzing…" | **Cancel** (FR-002) |
| `result` | large **total kcal** + itemized foods (name, kcal, macros) | **Done** |
| `noFood` | "No food detected" message | **Retake**, **Cancel** (FR-012) |
| `failed` | specific error message | **Retry**, **Cancel** (FR-011) |

- Success total is rendered prominently with a unit, e.g. "575 kcal" (FR-005).
- Breakdown rows use the macro tokens (`AppColor.macroProtein/Carbs/Fat`).
- Terminal dismissal (Done/Cancel/Retake→cancel) calls `Router.dismissCamera()`.

## Camera integration (feature 001)

- `CameraCaptureView` **Send** button: instead of dismissing, it calls
  `store.stop()` on the session, constructs `CalorieAnalysisStore(imageData:, analyzer:)`
  from the captured image, and presents `AnalysisResultView`.

## Accessibility identifiers (stable)

| Identifier | Element |
|------------|---------|
| `analysis.screen` | Result container |
| `analysis.loading` | Loading/analyzing state |
| `analysis.cancelButton` | Cancel (during analyzing / errors) |
| `analysis.total` | Total calories value |
| `analysis.foodList` | Itemized breakdown list |
| `analysis.doneButton` | Done (success) |
| `analysis.errorMessage` | Failure message text |
| `analysis.retryButton` | Retry (failure) |
| `analysis.noFoodMessage` | No-food message |
| `analysis.retakeButton` | Retake (no food) |

## Localization keys (EN + ES required — FR-016)

`analysis.analyzing`, `analysis.totalLabel`, `analysis.kcalUnit`,
`analysis.done`, `analysis.cancel`, `analysis.retry`, `analysis.retake`,
`analysis.noFood`, `analysis.error.noConnection`, `analysis.error.timeout`,
`analysis.error.service`, `analysis.error.invalidResponse`,
`analysis.macro.protein`, `analysis.macro.carbs`, `analysis.macro.fat`.
