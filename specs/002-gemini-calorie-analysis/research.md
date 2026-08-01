# Phase 0 Research: Photo Calorie Analysis

No open `NEEDS CLARIFICATION` items. Decisions below lock the approach.

## R1. How to call Gemini (SDK vs. REST)

- **Decision**: Call the Gemini REST endpoint directly with `URLSession` +
  `Codable`: `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`.
  Use `gemini-2.5-flash` (fast, multimodal, supports structured output) as the
  default model, configurable via secrets/config.
- **Rationale**: Avoids adding a third-party SDK (constitution Tech Constraints
  prefer Apple frameworks); the request is a single JSON POST that `URLSession`
  and `Codable` handle cleanly and testably. `URLSession` is `Sendable` and
  async-native, fitting Swift 6.
- **Alternatives considered**: Google's generative-ai Swift SDK — rejected: a
  heavy dependency for one call, and the constitution asks us to justify external
  packages. Streaming — unnecessary for a single structured result.

## R2. Forcing well-formed JSON ("json bien formado que puedas entender")

- **Decision**: Set `generationConfig.responseMimeType = "application/json"` and
  supply a `responseSchema` describing the exact object we want (total +
  itemized foods with macros). Decode the model's JSON text with `Codable`. If
  decoding fails or required fields are missing, treat it as
  `AnalysisError.invalidResponse` (FR-004) — never show a number.
- **Rationale**: A response schema makes Gemini return schema-conformant JSON,
  which is exactly the "well-formed JSON the app can understand" the user asked
  for, and lets us decode deterministically and unit-test with fixtures.
- **Alternatives considered**: Free-text prompt + regex/JSON-scraping — rejected:
  brittle and untestable, and forbidden by FR-003.

## R3. Detecting "no food" vs. a real result

- **Decision**: The schema includes a boolean/`foods` array; the prompt instructs
  Gemini to return an **empty foods list** (and a `foodDetected=false` flag) when
  the image contains no identifiable food. The store maps an empty/`false` result
  to `AnalysisOutcome.noFood`, shown distinctly (FR-012), not as 0 kcal.
- **Rationale**: Satisfies US3 AS4 / SC-004 with a deterministic rule instead of
  guessing from a zero total.
- **Alternatives considered**: Treating total==0 as "no food" — rejected:
  ambiguous (a real 0-kcal edge) and conflates error with data.

## R4. Total computation & validation

- **Decision**: A pure `CalorieAggregator` computes `total = Σ items.calories`.
  If the payload carries its own total, the app **ignores it in favor of the
  computed sum** so the displayed total always equals the breakdown (FR-006 /
  SC-002). Rounding is to whole kcal for display.
- **Rationale**: Guarantees the invariant the spec requires and is trivially
  unit-testable (normal, single-item, empty).
- **Alternatives considered**: Trusting the model's `total` field — rejected: can
  disagree with the items and break FR-006.

## R5. Concurrency & threading

- **Decision**: `GeminiCalorieService` is a `Sendable` value type with an
  `async throws` method; all networking/decoding happens in that async context
  (off the main thread). `CalorieAnalysisStore` is `@MainActor @Observable` and
  only touches UI state; it runs the service in a `Task` it can cancel. Cancel /
  leaving mid-flight cancels the `Task` (FR-002/FR-014/FR-015).
- **Rationale**: Keeps the main thread free (Principle IV) and gives clean
  cancellation and single-flight behavior via structured concurrency.
- **Alternatives considered**: A dedicated actor for the service — unnecessary;
  the service holds no mutable state.

## R6. Error mapping

- **Decision**: Map failures to `AnalysisError`:
  `URLError.notConnectedToInternet/.networkConnectionLost → noConnection`;
  `URLError.timedOut` (and our own request timeout) → `timeout`; non-2xx / API
  error body → `serviceError`; decode/schema failure → `invalidResponse`; empty
  foods → surfaced as `noFood` outcome (not an error). Each maps to a localized
  message + Retry/Cancel (FR-011).
- **Rationale**: Gives the specific, actionable messages US3 requires and is
  unit-testable by feeding the mapper canned errors/JSON.

## R7. API key handling (never in repo)

- **Decision**: Store the key in `Config/Secrets.xcconfig` (git-ignored),
  exposing `GEMINI_API_KEY`. The target's Info.plist gets a `GeminiAPIKey` entry
  set to `$(GEMINI_API_KEY)`; `AppSecrets` reads it from `Bundle.main` at runtime.
  Commit `Config/Secrets.example.xcconfig` as a template with a placeholder.
- **Rationale**: Keeps the secret out of source and git (constitution Tech
  Constraints) while remaining simple; CI/other devs copy the example file.
- **Alternatives considered**: Hardcoding the key — forbidden. A full secrets
  manager / Keychain provisioning — overkill for a single dev key.

## R8. Where the result is shown (navigation)

- **Decision**: Tapping **Send** in `CameraCaptureView` stops the session, keeps
  the captured `UIImage`, and presents `AnalysisResultView` (backed by a
  `CalorieAnalysisStore`) as a step **within the already-presented camera cover**
  (local `@State`, analogous to the existing capture→Send button-state step).
  Dismissing the result dismisses the whole camera flow via `Router.dismissCamera()`.
- **Rationale**: The captured photo already lives in the camera flow; progressing
  capture → analyzing → result is in-feature step state, consistent with how the
  capture state already advances locally. Top-level presentation is still owned by
  the Router (`cameraFlow == .camera`), so Principle V holds.
- **Alternatives considered**: Threading the `UIImage` through the Router —
  clunky; the image is transient view data, not app navigation state.

## Resolved unknowns

None outstanding. Proceed to Phase 1.
