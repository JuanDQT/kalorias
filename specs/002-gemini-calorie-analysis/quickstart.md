# Quickstart & Validation: Photo Calorie Analysis

A run/validation guide. Implementation details live in `tasks.md` and the code.

## Prerequisites

- Feature 001 (camera capture) working on a **physical device** (Simulator has no
  camera; capture is required to produce the photo this feature analyzes).
- A Gemini API key. Configure it **without committing**:
  1. `cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig`
  2. Put `GEMINI_API_KEY = your_key_here` in `Config/Secrets.xcconfig` (git-ignored).
  3. The target's Info.plist exposes it as `GeminiAPIKey = $(GEMINI_API_KEY)`;
     `AppSecrets` reads it at runtime.

## Build & unit tests (no network needed)

```bash
xcodebuild -project Kalorias.xcodeproj -scheme Kalorias \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build

xcodebuild -project Kalorias.xcodeproj -scheme Kalorias \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test
```

Expected: zero warnings under Swift 6 strict concurrency; these unit suites pass:
- `CalorieAggregatorTests` — total = Σ items; single item; empty ⇒ noFood.
- `CalorieAnalysisDecodingTests` — decodes the success + no-food fixtures
  (contracts/gemini-response.schema.md); rejects malformed/negative payloads as
  `invalidResponse`.
- `CalorieAnalysisStoreTests` — with a **mock** `CalorieAnalyzing`: analyzing →
  result / noFood / failed; `retry()` re-runs; `cancel()` ends the flow;
  single-flight (no concurrent analyses).

## Manual validation (physical device)

### US1 — Total (happy path)
1. Capture a plate of food → tap **Send** → a loading state appears. (US1 AS1, FR-002)
2. Within ~10s a prominent **total kcal** is shown. (US1 AS2, SC-001, FR-005)
3. The total equals the sum of the listed foods. (US1 AS3, FR-006, SC-002)
4. Tap **Done** → returns to the main screen + bottom bar. (US1 AS4, FR-015)

### US2 — Breakdown
1. Photo with several foods → result lists each food with its kcal. (US2 AS1, FR-007)
2. Macros shown when available, using the macro token colors. (US2 AS2, FR-008)
3. Listed items sum to the displayed total. (US2 AS3)

### US3 — Failures
1. Airplane mode → Send → "no connection" + Retry/Cancel; no number. (US3 AS1, FR-011)
2. Force a slow/timeout → timeout message + Retry/Cancel. (US3 AS2)
3. Photo of a wall → "no food detected" (not 0 kcal) + Retake/Cancel. (US3 AS4, FR-012, SC-004)
4. Tap **Retry** on an error → the same photo is re-analyzed. (US3 AS5, FR-013)
5. Throughout, the UI stays responsive and Cancel works. (SC-006, FR-010)

## Definition of done

- All unit suites green; build warning-free under Swift 6 strict concurrency.
- Total always equals the itemized sum; failures never show a number.
- New strings present in EN + ES; result UI verified light + dark.
- Colors from `AppColor`; result surfaces use native Liquid Glass.
- `Config/Secrets.xcconfig` is git-ignored; no key committed.
