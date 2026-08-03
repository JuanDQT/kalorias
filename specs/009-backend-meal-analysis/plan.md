# Implementation Plan: Meal Analysis Moves to the Kalorias Backend

**Branch**: `009-backend-meal-analysis` | **Date**: 2026-08-01 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/009-backend-meal-analysis/spec.md`

## Summary

The app stops calling Google Gemini and calls the Kalorias server instead. One request — a JPEG in
a `multipart/form-data` field named `photo` — returns an already-normalized analysis. The prompt,
the response schema, the token ceiling, the base64 encoding and the 0–1000 bounding-box conversion
all leave the app, and so does the API key.

The migration is smaller than it looks, because the domain layer was already decoupled from the
provider:

- **`CalorieAnalyzing` does not change.** `GeminiCalorieService` is replaced by
  `RemoteCalorieService` behind the same protocol, so the store, the views, persistence and every
  store test carry on unmodified. This boundary is why the feature is a service swap and not a
  rewrite.
- **`FoodRegion` needs no new geometry.** The server sends proportions in `0...1` from the
  top-left, which is exactly what `FoodRegion(clampingX:y:width:height:)` already stores and
  already validates. The 0–1000 initializer is deleted rather than adapted.
- **`FoodItem`, `CalorieAnalysis`, `MealEntry` and `StoredFood` are untouched**, so there is no
  migration and existing history stays readable (SC-009).

Three things are genuinely new, and each is a place the feature can go wrong quietly:

1. **Two new failure modes with real UI behaviour** — a rejected photo offers *retake*, not retry;
   a rate limit runs a countdown that keeps retry disabled until it expires. The countdown logic
   is a pure type with an injected clock, so it is tested without sleeping (Principle II).
2. **The photo must be sized before it is sent.** `CameraCaptureView.swift:74` currently encodes
   the capture at full resolution, which on a 48 MP device can exceed the server's 8 MB limit —
   today's latent bug, fixed here by downsizing to 1024 (what the server analyses anyway).
3. **The base URL is a per-configuration xcconfig value**, and xcconfig treats `//` as a comment,
   so a literal `https://…` silently truncates to `https:`. Handled with `$(SLASH)` indirection
   and a test that the configured URL parses (research §1).

Full reasoning in [research.md](./research.md); types and rules in [data-model.md](./data-model.md);
the wire agreement in [contracts/analyze-meal-v1.md](./contracts/analyze-meal-v1.md) and the screen
behaviour in [contracts/ui-contracts.md](./contracts/ui-contracts.md).

## Technical Context

**Language/Version**: Swift 6, strict concurrency `complete`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.

**Primary Dependencies**: Foundation (`URLSession`, `URLSessionConfiguration.ephemeral`), `os` for
`Logger`, UIKit for the existing image downsizing. **No new dependency** — the multipart body is
~20 lines of `Data` assembly, which is well below the constitution's bar for justifying a
networking package.

**Storage**: No change. No new field, no schema change, no migration. `MealEntry` and `StoredFood`
are written exactly as before.

**Testing**: XCTest in `KaloriasTests`. Of the **186** existing test functions, 22 are removed with
the provider path — all 16 in `CalorieAnalysisDecodingTests` and the 6 `gemini*` cases in
`FoodRegionTests` — but 13 of those 16 are re-created against the new contract in
`AnalyzeMealResponseTests`, so only 9 behaviours genuinely disappear (3 provider-request
assertions and the 6 obsolete region conversions). Every other pre-existing test stays green
**unmodified**. Six new suites. No test performs network I/O, sleeps, or reads the wall clock: the
service is tested against a `URLProtocol` stub, and the cooldown against injected dates. Each test
task sits in the same phase as the implementation it covers (tasks.md, "Test/implementation
ordering") — Principle II's "before or alongside", read the only way Swift allows.

**Target Platform**: iOS 26.5+.

**Project Type**: Native iOS app. New `.swift` files under `Kalorias/` are auto-included; **new
test files need a `project.pbxproj` entry** or they silently never run.

**Performance Goals**: end-to-end wait no worse than today on the same network (SC-007). The image
downsize and JPEG encode run off the main thread, as does all networking; the countdown ticks once
a second on the main actor and touches one `Int`.

**Constraints**: JPEG only, ≤ 8 MB (app targets 7.5); no auth header; ≥ 35 s patience; no caching;
no automatic retry anywhere; no provider name in any user-facing string; EN + ES for all new copy;
zero AI-provider credentials in the binary or repo.

**Scale/Scope**: 7 files added, 9 modified, 2 deleted. 6 new test suites, 4 modified, 1 deleted.
One configuration change and one Info.plist change. No navigation, persistence or design-system
change.

## Constitution Check

*GATE: evaluated against Kalorias Constitution v3.1.0. Re-checked after Phase 1 — see below.*

| Principle | Gate | Status |
|-----------|------|--------|
| I. Code Quality | Every piece of logic that can be wrong is a pure, testable type: multipart assembly, response decoding, `Retry-After` parsing, countdown arithmetic, photo sizing. No force-unwraps. The dead provider path is **deleted, not disabled** — including its tests, which would otherwise keep passing while covering unreachable code. Key revocation is a task, not a TODO comment. | ✅ |
| II. Testing (NON-NEG) | Calorie-bearing logic (decoding, totals, aggregation) has normal, empty and error cases. New suites for multipart, response decoding, status mapping, cooldown, photo encoding, configuration. Tests are deterministic: `URLProtocol` stub for the network, injected `Date` for time — **nothing sleeps** (research §6). No UI tests authored, per this principle. | ✅ |
| III. UX Consistency | Failure states reuse the existing `messageState` layout, buttons and `AppColor.warning`. The two new outcomes are actionable: retake for a rejected photo, a visible countdown for a rate limit — no dead-end error. Latency already has its loading state. No new surface treatment, no new token. | ✅ |
| IV. Performance | Networking, downsizing and encoding are off the main thread. The 1024 downsize makes uploads *smaller* than today's full-resolution send, so SC-007 has margin rather than risk. Countdown is one `Int` per second. | ✅ |
| V. Architecture (NON-NEG) | `CalorieAnalyzing` unchanged, so the store/view contract is unchanged. The service is a `Sendable` value type that never touches SwiftUI; the cooldown gate lives in the **store**, not in the view's `disabled` modifier (data-model S2). Router untouched. Strict concurrency throughout. | ✅ |
| VI. Localization & Appearance (NON-NEG) | Three new keys, EN + ES in the same change. **The server's Spanish-only message text is never displayed** — the app shows its own localized copy (FR-021a), which is exactly what this principle demands. No raw identifier reaches VoiceOver. Verified in both appearances and languages. | ✅ |
| Tech Constraints | No third-party dependency added. No credential in the repo or binary. **But this feature changes the answer to "what is the app's external service"** — see below. | ⚠️ |
| Design System (governance) | No new color token; the palette table is untouched. | ✅ |

**Result**: gates pass, with one governance action this plan will not silently absorb.

**The constitution becomes factually wrong on merge.** Its Product Overview states the image "is
sent to **Google Gemini**", and its External Services block names Gemini as "the one approved
external service". After this feature the app's single external service is the Kalorias backend,
and the app no longer holds a provider credential at all. That is a change in the app's trust and
privacy story, not just an implementation detail.

Amending the constitution is **not** in this feature's scope and must not be smuggled into it: it
is a governed document with its own command and version history. Recorded in Complexity Tracking
and as a follow-up `/speckit-constitution` run once this lands.

## Project Structure

### Documentation (this feature)

```text
specs/009-backend-meal-analysis/
├── spec.md
├── backend-integration-brief.md      # the brief this feature implements
├── plan.md                           # this file
├── research.md                       # Phase 0
├── data-model.md                     # Phase 1
├── quickstart.md                     # Phase 1
├── contracts/
│   ├── analyze-meal-v1.md            # wire contract, as the app consumes it
│   └── ui-contracts.md               # failure-state behaviour and copy
├── checklists/requirements.md
└── tasks.md                          # /speckit-tasks — not created here
```

### Source code

```text
Kalorias/
├── Features/Analysis/
│   ├── RemoteCalorieService.swift        # NEW — replaces GeminiCalorieService
│   ├── AnalyzeMealResponse.swift         # NEW — wire DTOs + mapping to domain
│   ├── MultipartFormData.swift           # NEW — pure body builder
│   ├── AnalysisPhotoEncoder.swift        # NEW — JPEG within the size cap
│   ├── RetryCooldown.swift               # NEW — pure Retry-After + countdown
│   ├── GeminiCalorieService.swift        # DELETED
│   ├── AnalysisError.swift               # MOD — .photoRejected, .rateLimited
│   ├── CalorieAnalysisStore.swift        # MOD — cooldown state, retry gate
│   ├── AnalysisResultView.swift          # MOD — failure branch only
│   ├── CalorieAggregator.swift           # MOD — make(from:reportedTotal:)
│   ├── CalorieAnalysis.swift             # MOD — doc only: total is reported, not derived
│   └── FoodRegion.swift                  # MOD — delete init(geminiTop:…)
├── Support/
│   ├── AppConfiguration.swift            # NEW — replaces AppSecrets
│   ├── AppSecrets.swift                  # DELETED
│   └── AnalysisLog.swift                 # NEW — os.Logger, category "analysis"
└── Features/Camera/
    └── CameraCaptureView.swift           # MOD — encoder + RemoteCalorieService

Config/
├── Info.plist                            # MOD — drop Gemini keys, add KaloriasAPIBaseURL + ATS
├── Secrets.xcconfig                      # MOD (untracked) — base URLs
└── Secrets.example.xcconfig              # MOD — documents the URLs, no key

KaloriasTests/
├── MultipartFormDataTests.swift          # NEW
├── AnalyzeMealResponseTests.swift        # NEW — replaces CalorieAnalysisDecodingTests
├── RemoteCalorieServiceTests.swift       # NEW — URLProtocol stub, status mapping
├── RetryCooldownTests.swift              # NEW
├── AnalysisPhotoEncoderTests.swift       # NEW
├── AppConfigurationTests.swift           # NEW — the xcconfig `//` guard
├── CalorieAnalysisDecodingTests.swift    # DELETED (superseded)
├── FoodRegionTests.swift                 # MOD — drop the 6 gemini cases
├── CalorieAggregatorTests.swift          # MOD — reported total
├── CalorieAnalysisStoreTests.swift       # MOD — cooldown / retry-gate cases
└── CalorieAnalysisErrorMappingTests.swift # MOD — new cases
```

**Structure Decision**: the existing feature-folder layout is kept exactly. Everything analysis-
related stays in `Kalorias/Features/Analysis/`, configuration in `Kalorias/Support/`. No new
module, group or layer — the feature replaces the contents of one service boundary, and inventing
structure around that would obscure how contained the change actually is.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Constitution's Product Overview and External Services sections become inaccurate on merge | The app's single external service changes from Google Gemini to the Kalorias backend — a change in its privacy and trust story, not just an implementation detail | Editing the constitution inside this feature was rejected: it is a governed document with its own amendment command and version history. Leaving it stale was also rejected — it would state, in the file that governs the project, that the app ships a Gemini key it no longer has. Tracked as a follow-up `/speckit-constitution` run. |
| Hand-rolled multipart encoding | The contract requires `multipart/form-data`; Foundation has no encoder | A networking dependency for one request with one part fails the Technology Constraints justification bar. The hand-rolled version is ~20 lines, pure, and unit-tested (A1). |
| `NSAllowsLocalNetworking` in the shipped Info.plist | A physical device cannot reach the Mac's `localhost`; it needs the Mac's LAN address, which is a private range | `NSAllowsArbitraryLoads` would weaken ATS for production too, breaking FR-007a. Per-configuration Info.plists would duplicate 40 lines of plist to vary one dict, and they drift. This key relaxes ATS *only* for loopback, private ranges and `.local`, so the release build's HTTPS address keeps full protection by construction — nothing to remember to strip. |

## Post-Design Constitution Re-check

Re-evaluated after Phase 1. No gate moved.

- **Principle II** ends stronger than it started: the two hardest things to test — a network
  boundary and elapsed time — were designed into pure types (`RetryCooldown`,
  `AnalyzeMealResponse`, `MultipartFormData`), leaving an impure remainder of a `URLProtocol` stub
  and a `Task.sleep` loop that contains no logic.
- **Principle I** is why [research.md §12](./research.md) lists the deletions explicitly. The
  failure mode this feature invites is leaving the provider code in place "just in case", which
  would keep the key in the binary and defeat the entire point (FR-008, FR-009, SC-001).
- **Principle VI** overrode the brief on one point: the brief says to display the server's `422`
  message, but that text is Spanish-only and this app ships EN + ES. The app's own localized copy
  wins (FR-021a); the server's text is logged instead.
- The **Tech Constraints** flag stays open by design, discharged by a separate
  `/speckit-constitution` run rather than by this feature.
