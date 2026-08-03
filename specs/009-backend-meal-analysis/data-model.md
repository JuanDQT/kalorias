# Data Model: Meal Analysis Moves to the Kalorias Backend

**Feature**: `009-backend-meal-analysis` | **Date**: 2026-08-01

Types, their rules, and what changes. Reasoning lives in [research.md](./research.md); the wire
format in [contracts/analyze-meal-v1.md](./contracts/analyze-meal-v1.md).

**No persistence change.** `MealEntry`, `StoredFood` and `FoodRegion` are untouched on disk, so
there is no migration and history recorded before this feature stays readable (SC-009).

---

## 1. Wire DTOs — new

`Kalorias/Features/Analysis/AnalyzeMealResponse.swift`. `Decodable`, `nonisolated`, internal to
the analysis feature. These replace `GeminiEnvelope` and `FoodPayload`, which are deleted.

| Type | Field | Wire type | Rule |
|---|---|---|---|
| `AnalyzeMealResponse` | `data` | object | The envelope. Its absence ⇒ `.invalidResponse` |
| `AnalyzeMealResponse.Payload` | `foodDetected` | bool | Required |
| | `totalCalories` | int | Required. Used as-is (D3) |
| | `foods` | array | Required; may be empty |
| `AnalyzeMealResponse.Food` | `name` | string | Required, non-empty |
| | `calories` | int | Required, `>= 0` |
| | `protein` / `carbs` / `fat` | double? | Absent and `0` are different values (D5) |
| | `region` | object? | `null` is normal (D6) |
| `AnalyzeMealResponse.Region` | `x`, `y`, `width`, `height` | double | Proportions `0...1`, origin top-left. **No scaling, no axis swap** |

### Decoding rules

- **D1 — envelope**: the payload is under a root `data` key. Forgetting it fails every response.
- **D2 — strictness is asymmetric.** `name` and `calories` are strict: a food without them is
  meaningless, so the response is `.invalidResponse`. Everything else is lenient: macros and
  region decode with `try?` and degrade to `nil`.
- **D3 — the total is taken, not computed.** `totalCalories` is used exactly as received. In DEBUG
  only, a mismatch against the sum of `foods[].calories` logs a warning; it never alters the value
  and never fails the analysis (FR-012).
- **D4 — negative calories** on any food ⇒ `.invalidResponse` (unchanged rule, retained test).
- **D5 — a missing macro stays missing.** `nil` must not become `0` anywhere between the wire and
  the UI. `0` means "none"; `nil` means "not reported" and renders as `—`.
- **D6 — a missing or unusable region costs only the thumbnail.** The food keeps its name,
  calories and macros (FR-013, FR-016).
- **D7 — no food**: `foodDetected: false` (or an empty `foods`) ⇒ `.noFood`, a success, not an
  error, and never saved (FR-011).
- **D8 — unknown fields are ignored**, so a `v1` server adding a field cannot break the app.

### Mapping to the domain

`AnalyzeMealResponse.Payload → AnalysisOutcome`, via `CalorieAggregator.make(from:reportedTotal:)`.
`FoodItem`, `CalorieAnalysis`, `AnalysisOutcome` and `FoodRegion` are unchanged types — only their
source changes. `Region → FoodRegion` uses the existing `init?(clampingX:y:width:height:)`
verbatim.

---

## 2. `AnalysisError` — modified

`Kalorias/Features/Analysis/AnalysisError.swift`. Two cases added; `Equatable` and the
`messageKey` contract preserved.

| Case | Raised by | Message key | Primary action |
|---|---|---|---|
| `.noConnection` | `URLError` offline family | `analysis.error.noConnection` | Retry |
| `.timeout` | `URLError.timedOut` | `analysis.error.timeout` | Retry |
| `.serviceError` | `503`, other `5xx`, unexpected status, bad URL | `analysis.error.service` | Retry |
| `.invalidResponse` | unreadable/invalid `200` body | `analysis.error.invalidResponse` | Retry |
| **`.photoRejected`** *(new)* | `422`, `413` | `analysis.error.photoRejected` | **Retake** |
| **`.rateLimited(retryAfter: TimeInterval)`** *(new)* | `429` | `analysis.error.rateLimited` (no argument) | Retry, **disabled** until 0 |

The rate-limit message carries **no** number: the remaining seconds live on the button, in
`analysis.retryIn` (`%lld`), so there is one moving value in one place — as
[contracts/ui-contracts.md](./contracts/ui-contracts.md) specifies.

Rules:

- **E1**: no message names a provider, model, or upstream code (FR-022).
- **E2**: the server's own message text is never surfaced to the UI; it is logged (FR-021a).
- **E3**: `.photoRejected` never offers retry with the same photo (FR-019).
- **E4**: `AnalysisError.from(_:)` keeps its `URLError`/`DecodingError` mapping unchanged; HTTP
  status mapping is new and lives in the service.

---

## 3. `RetryCooldown` — new, pure

`Kalorias/Features/Analysis/RetryCooldown.swift`. A value type; no timer, no clock of its own.

```
init(seconds: TimeInterval, now: Date)      // clamps seconds to 1...3600
var expiry: Date
func secondsRemaining(at: Date) -> Int      // ceil, floored at 0
func hasExpired(at: Date) -> Bool
static func parseRetryAfter(_ header: String?, now: Date) -> TimeInterval   // default 60
```

| Rule | Behaviour |
|---|---|
| R1 | `Retry-After` as delay-seconds (`"45"`) → 45 |
| R2 | `Retry-After` as HTTP-date → seconds until that date |
| R3 | absent, empty, unparseable, or a past date → **60 s** (FR-020a) |
| R4 | clamped to `1...3600`; `0`, negatives and absurd values cannot disable retry forever |
| R5 | `secondsRemaining` never returns a negative; rounds **up**, so "1" is displayed until it is genuinely over |
| R6 | every rule above is asserted with injected dates — **no test sleeps or reads the clock** (Principle II) |

---

## 4. `CalorieAnalysisStore` — modified

`Kalorias/Features/Analysis/CalorieAnalysisStore.swift`. Still `@MainActor`, still single-flight,
still owns the state machine.

Added state:

| Member | Meaning |
|---|---|
| `private(set) var secondsUntilRetry: Int` | `0` when retry is available; drives the countdown label |
| `var canRetry: Bool` | `false` while `secondsUntilRetry > 0`, and `false` for `.photoRejected` |
| `private var cooldownTask: Task<Void, Never>?` | ticks once a second; cancelled on `cancel()`, on a successful retry, and on deinit |

Rules:

- **S1**: on `.rateLimited(retryAfter:)` the store builds a `RetryCooldown` and starts the tick.
- **S2**: `retry()` is a **no-op** while `canRetry == false` — the gate is in the store, not only
  in the button's `disabled` modifier, so it holds however the view is driven (FR-020).
- **S3**: reaching zero re-enables retry in place, with no navigation (FR-020).
- **S4**: `cancel()` cancels the analysis *and* the cooldown.
- **S5**: nothing else changes — success still records the meal, `.noFood` and every failure still
  record nothing (FR-024).
- **S6**: the store gets a `now: () -> Date` seam so its cooldown behaviour is testable without
  waiting.

### The photo that never left the device

`AnalysisPhotoEncoder` can return `nil` — an image that will not fit the size cap even at the
lowest quality. There is nothing to send, so no request happens, but the user still deserves the
same answer they would get if the server had refused it.

A second entry point covers this:

```
init(rejectedPhoto image: UIImage?)      // state = .failed(.photoRejected)
```

| Rule | Behaviour |
|---|---|
| S7 | The store is constructed already `.failed(.photoRejected)`; `start()` returns immediately without calling any analyzer, so `.onAppear` cannot overwrite the state |
| S8 | `retry()` is a no-op — `canRetry` is already `false` for `.photoRejected` (S2). The only way out is Retake, which is what the screen offers |
| S9 | Nothing is recorded, and no request is made — the failure is entirely local |

**Why this and not the alternatives.** Constructing the store with an analyzer that always throws
would work, but it fakes a network round-trip that never happened and leaves a retry path that
silently re-throws. Dismissing the camera without a message — today's behaviour at
`CameraCaptureView.swift:75` — loses the user's photo with no explanation, which is the failure
mode FR-023 exists to prevent. A dedicated initializer says exactly what happened, in one line, at
the one call site that knows.

---

## 5. `AppConfiguration` — new, replaces `AppSecrets`

`Kalorias/Support/AppConfiguration.swift`. `AppSecrets.swift` is deleted.

| Member | Rule |
|---|---|
| `static var analysisBaseURL: URL?` | Reads `KaloriasAPIBaseURL` from `Info.plist`; `nil` when blank or unparseable |
| `static var isConfigured: Bool` | `analysisBaseURL != nil` |

- **C1**: a `nil` URL produces `.serviceError` on every analysis — never a crash, never a
  provider fallback (FR-009).
- **C2**: no API key, no model id, no provider hostname exists anywhere in the app (FR-008,
  SC-001).
- **C3**: a test asserts the configured value parses to an absolute URL with a scheme and host —
  this is what catches the xcconfig `//` comment trap (research §1).

---

## 6. `MultipartFormData` — new, pure

`Kalorias/Features/Analysis/MultipartFormData.swift`.

| Rule | Behaviour |
|---|---|
| M1 | Exactly one part, field name `photo`, filename `meal.jpg`, `Content-Type: image/jpeg` |
| M2 | `contentTypeHeaderValue` carries the **same** boundary as the body |
| M3 | CRLF (`\r\n`) line endings throughout; body ends with `--<boundary>--\r\n` |
| M4 | The image bytes appear in the body unmodified |
| M5 | Boundary is unique per request and cannot occur in normal JPEG data |

---

## 7. `AnalysisPhotoEncoder` — new, pure

`Kalorias/Features/Analysis/AnalysisPhotoEncoder.swift`. Called at the capture site.

| Rule | Behaviour |
|---|---|
| P1 | Downsizes to a longest side of 1024 via the existing `ImageCropper.downsized` |
| P2 | Encodes JPEG at quality 0.8, then 0.6, then 0.4 — only while over the cap |
| P3 | Cap is 7.5 MB, below the server's 8 MB, leaving room for multipart overhead |
| P4 | Returns `nil` if even 0.4 exceeds the cap; the caller shows `.photoRejected` |
| P5 | Never upscales an image already smaller than 1024 |
| P6 | Output is always JPEG, whatever the source format (camera, HEIC or PNG from the library) |

---

## 8. `AnalysisLog` — new

`Kalorias/Support/AnalysisLog.swift`. One `os.Logger`, category `analysis`.

| Rule | Behaviour |
|---|---|
| L1 | Success logs outcome, duration, food count, `X-Request-Id` |
| L2 | Failure logs outcome, duration, HTTP status, `X-Request-Id`, and the server's message when the photo was rejected |
| L3 | The request id is interpolated `privacy: .public` — otherwise it reads `<private>` in release, which is when it is needed |
| L4 | Never logs the photo, the image bytes, or food names (FR-026) |
| L5 | Nothing from this type reaches the UI (FR-027) |

---

## 9. `CalorieAggregator` — modified

`make(from:)` becomes `make(from:reportedTotal:)`: empty items still ⇒ `.noFood`, but the total is
the reported one. `total(of:)` stays as the DEBUG cross-check (research §10). Its existing tests
are updated, not deleted.

---

## Deleted

`GeminiCalorieService.swift` · `AppSecrets.swift` · `FoodRegion.init(geminiTop:left:bottom:right:)`
· `GeminiAPIKey` and `GeminiModel` in `Info.plist` · `GEMINI_API_KEY` and `GEMINI_MODEL` in both
xcconfig files · the three provider-request tests and the six `gemini*` region tests.
