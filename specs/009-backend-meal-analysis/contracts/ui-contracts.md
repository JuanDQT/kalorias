# UI Contract: analysis failure states

**Feature**: `009-backend-meal-analysis` | **Date**: 2026-08-01

Only `AnalysisResultView` changes, and only its failure branch. The analyzing, result and no-food
states are untouched — this feature must be invisible on the happy path.

---

## States

| State | Icon | Primary action | Secondary |
|---|---|---|---|
| `.analyzing` | spinner | — | Cancel |
| `.result` | — | Done | — |
| `.noFood` | `questionmark.circle` | Retake | Cancel |
| `.failed(.noConnection / .timeout / .serviceError / .invalidResponse)` | `exclamationmark.triangle` | **Retry** | Cancel |
| `.failed(.photoRejected)` | `exclamationmark.triangle` | **Retake** | Cancel |
| `.failed(.rateLimited)` | `exclamationmark.triangle` | **Retry, disabled while counting down** | Cancel |

Rules:

- **U1**: no failure state displays a calorie number (FR-023).
- **U2**: `.photoRejected` shows **Retake**, not Retry — retrying the same bytes cannot succeed
  (FR-019).
- **U3**: while a cooldown runs, the retry button is disabled and its label carries the remaining
  seconds. At zero it re-enables in place, with no navigation (FR-020).
- **U4**: the store refuses the retry independently of the button's disabled state (data-model S2).
- **U5**: Cancel behaves as today in every failure state.
- **U6**: no request id, HTTP status, provider name or server message text appears on screen
  (FR-022, FR-027).

---

## Accessibility identifiers

Existing, unchanged: `analysis.screen`, `analysis.loading`, `analysis.total`, `analysis.foodList`,
`analysis.errorMessage`, `analysis.retryButton`, `analysis.retakeButton`, `analysis.cancelButton`,
`analysis.doneButton`, `analysis.noFoodMessage`.

The rejected-photo state reuses `analysis.retakeButton` for its primary action, so the identifier
always names what the control *does*. No new identifiers are added.

---

## Copy — `Localizable.xcstrings`, EN + ES both required (Principle VI)

| Key | EN | ES |
|---|---|---|
| `analysis.error.photoRejected` | "That photo can't be analyzed. Try a different one." | "Esa foto no se puede analizar. Prueba con otra." |
| `analysis.error.rateLimited` | "Too many analyses for now." | "Demasiados análisis por ahora." |
| `analysis.retryIn` | "Retry in %lld s" | "Reintentar en %lld s" |

- Reuses the existing `analysis.retry`, `analysis.retake`, `analysis.cancel`, and the four
  existing error messages, unchanged.
- `%lld` (not `%d`) for an `Int` on 64-bit.
- Vocabulary follows the constitution: "análisis", "foto", "alimento" — the terms already used
  elsewhere in the app.
- No message names a provider or model; none is a raw identifier read aloud by VoiceOver
  (Principle VI).

---

## Appearance

No new color token, no new surface treatment. The failure state keeps `AppColor.warning` for its
icon and the existing button styles. Verified in light and dark, EN and ES, at an accessibility
Dynamic Type size — the countdown label is the one new piece of text that grows, and it must not
truncate the button (Principle VI).
