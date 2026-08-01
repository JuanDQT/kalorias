# Implementation Plan: Photo Calorie Analysis

**Branch**: `002-gemini-calorie-analysis` | **Date**: 2026-07-24 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/002-gemini-calorie-analysis/spec.md`

## Summary

Turn the camera flow's stubbed **Send** button (feature 001) into the app's core
loop: send the captured photo to Google Gemini, receive a **structured JSON**
result, compute the **total calories**, and show it (with an itemized breakdown)
— handling every failure with a clear message and Retry/Cancel.

Technical approach (native, per constitution): a `CalorieAnalyzing` protocol
boundary hides Gemini behind a Store. `GeminiCalorieService` calls the Gemini
REST `generateContent` endpoint with the image inline and a **response schema**
so the model must return schema-conformant JSON, decoded with `Codable`. A pure,
testable aggregator validates the payload and derives the total. A
`CalorieAnalysisStore` (`@MainActor @Observable`) owns the analyzing → success /
no-food / failure state machine and Retry/Cancel. The result UI uses native
Liquid Glass, tokenized colors (macro tokens for the breakdown), and localized
EN+ES copy. All network/decoding runs off the main thread; the API key is read
from a git-ignored config, never committed.

## Technical Context

**Language/Version**: Swift 6 (strict concurrency `complete`, default MainActor isolation).

**Primary Dependencies**: SwiftUI, Observation, Foundation `URLSession` (REST call
to Gemini), `Codable`. The existing camera stack (feature 001) supplies the
photo. **No third-party SDK** — Gemini is called over REST directly to keep
dependencies minimal (constitution Tech Constraints).

**Storage**: N/A. The photo, request, and result are transient (no persistence —
Progress/History are later features).

**Testing**: XCTest in the existing `KaloriasTests` target. A mock
`CalorieAnalyzing` and canned JSON fixtures test the store's state machine, the
response decoding, and the total aggregation **without** network access. UI tests
remain OFF by default (Principle II).

**Target Platform**: iOS 26.5+.

**Project Type**: Native iOS app (single SwiftUI target, filesystem-synchronized groups).

**Performance Goals**: 90% of typical single-plate analyses return within 10s
(SC-001, network-bound); main thread never blocks (SC-006).

**Constraints**: Gemini confined to a service/Store boundary, never called from
views; all analysis off the main thread; API key never committed (read from a
git-ignored `Secrets.xcconfig` surfaced via Info.plist); native Liquid Glass +
`AppColor` tokens; every string localized EN+ES; correct in light/dark.

**Scale/Scope**: 1 service + 1 protocol, ~4 model types, 1 store, 1 result screen
with loading/success/no-food/failure states. Small.

## Constitution Check

*GATE: evaluated against Kalorias Constitution v1.1.0. Re-checked after Phase 1.*

| Principle | Gate | Status |
|-----------|------|--------|
| I. Code Quality | Parsing + total aggregation in dedicated testable types (FR-006/FR-009), not views; no force-unwrap. | ✅ `CalorieAnalysis` decoding + `CalorieAggregator` own the math. |
| II. Testing (NON-NEG) | Unit tests for decoding, total = sum, no-food/empty, and the store machine via a mock analyzer + JSON fixtures. UI tests off. | ✅ See contracts + data-model; no UI-test tasks. |
| III. UX Consistency | Loading state + cancel (FR-002); clear actionable errors + Retry/Cancel (FR-011); native Liquid Glass result; `AppColor` incl. macro tokens; Dynamic Type/VoiceOver/a11y ids. | ✅ `AnalysisResultView` covers all states. |
| IV. Performance | Network + decode off main thread; UI responsive throughout (FR-010/SC-006). | ✅ `async` service; `@MainActor` only for state. |
| V. Architecture (NON-NEG) | Swift 6 strict; MV + Stores; Gemini behind `CalorieAnalyzing` boundary; navigation not ad hoc. | ✅ `CalorieAnalysisStore` + protocol-injected service. |
| VI. Localization & Appearance (NON-NEG) | All new copy EN+ES; dark mode; tokens. | ✅ new keys in `Localizable.xcstrings`. |
| Tech Constraints | Gemini = approved external service, confined to a service, off-main, **key not in repo**. | ✅ `Secrets.xcconfig` git-ignored; REST, no SDK. |

**Result**: All gates pass. No violations → Complexity Tracking empty.

## Project Structure

### Documentation (this feature)

```text
specs/002-gemini-calorie-analysis/
├── plan.md
├── research.md              # Phase 0
├── data-model.md            # Phase 1
├── quickstart.md            # Phase 1
├── contracts/
│   ├── gemini-response.schema.md   # the structured JSON contract Gemini must return
│   └── ui-contracts.md             # store intents, screen states, a11y ids, l10n keys
├── checklists/requirements.md
└── tasks.md                 # /speckit-tasks (not created here)
```

### Source Code (repository root)

```text
Kalorias/
├── Features/
│   ├── Camera/
│   │   └── CameraCaptureView.swift        # MODIFIED: Send → start analysis (was a stub)
│   └── Analysis/                          # NEW
│       ├── CalorieAnalysis.swift           # models: CalorieAnalysis, FoodItem, AnalysisOutcome
│       ├── AnalysisError.swift             # failure categories → message/actions
│       ├── CalorieAggregator.swift         # pure total = Σ items; validation (FR-006)
│       ├── CalorieAnalyzing.swift          # protocol boundary (Sendable)
│       ├── GeminiCalorieService.swift      # REST call + request/response DTOs + error mapping
│       ├── CalorieAnalysisStore.swift      # @Observable @MainActor state machine + retry/cancel
│       └── AnalysisResultView.swift        # loading / total+breakdown / no-food / error UI
├── Support/                               # NEW
│   └── AppSecrets.swift                    # reads GEMINI_API_KEY from Info.plist (git-ignored source)
├── Resources/Localizable.xcstrings        # MODIFIED: analysis strings (EN+ES)
└── DesignSystem/AppColor.swift            # existing macro tokens reused in the breakdown

Config/                                    # NEW
├── Secrets.example.xcconfig               # committed template (placeholder key)
└── Secrets.xcconfig                       # git-ignored real key (GEMINI_API_KEY = …)

KaloriasTests/                             # add
├── CalorieAggregatorTests.swift
├── CalorieAnalysisDecodingTests.swift
└── CalorieAnalysisStoreTests.swift        # uses a mock CalorieAnalyzing
```

**Structure Decision**: Add a self-contained `Features/Analysis/` module and a
tiny `Support/` for secret access, reusing the existing DesignSystem tokens and
the camera flow as the entry point. Gemini sits behind the `CalorieAnalyzing`
protocol so the store and UI are fully unit-testable with a mock, and the real
service can be swapped or upgraded without touching them. The API key lives in a
git-ignored `Config/Secrets.xcconfig` referenced by the target's Info.plist.

## Complexity Tracking

> No constitution violations. Section intentionally empty.
