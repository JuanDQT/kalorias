---

description: "Task list for 009-backend-meal-analysis"
---

# Tasks: Meal Analysis Moves to the Kalorias Backend

**Input**: Design documents from `/specs/009-backend-meal-analysis/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md),
[data-model.md](./data-model.md), [contracts/](./contracts/)

**Tests**: **Required.** Constitution Principle II (NON-NEGOTIABLE) mandates unit tests for any
logic that computes, aggregates, converts or persists calorie values — which is most of this
feature. Test tasks are therefore first-class, not optional. **No UI tests (XCUITest)** are
authored: the same principle keeps them off by default.

**Test/implementation ordering**: Principle II requires tests "written before or alongside the
implementation". In Swift a test cannot compile before the type it names exists, so *alongside* is
the workable reading: **a test task and the implementation it covers always sit in the same phase,
adjacent, and the suite must be green before that phase's checkpoint.** Never in a later phase —
a checkpoint that declares calorie logic "done" while its tests wait behind it is exactly what
this principle forbids.

**Organization**: grouped by user story so each is independently completable and testable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on incomplete work)
- **[Story]**: the user story the task serves (US1–US4). Setup, Foundational and Polish carry none.

## Path Conventions

Native iOS app. Sources under `Kalorias/`, tests under `KaloriasTests/`, build config under
`Config/`. New `.swift` files under `Kalorias/` are auto-included; **new test files need a
`project.pbxproj` entry or they silently never run** — a test count that does not grow is the
symptom.

---

## Phase 1: Setup (Configuration)

**Purpose**: give the app an address to call. Nothing else can be validated end-to-end until this
is right, and the `//` trap makes "right" non-obvious.

- [ ] T001 Replace the `GEMINI_API_KEY` / `GEMINI_MODEL` settings in `Config/Secrets.xcconfig` (untracked) with the per-configuration base URLs, using the `$(SLASH)` indirection exactly as written in [quickstart.md §2](./quickstart.md): `KALORIAS_API_BASE_URL_Debug = http:$(SLASH)$(SLASH)localhost:8000`, `KALORIAS_API_BASE_URL_Release = https:$(SLASH)$(SLASH)www.quispe.com`, `KALORIAS_API_BASE_URL = $(KALORIAS_API_BASE_URL_$(CONFIGURATION))`
- [ ] T002 [P] Mirror the same three settings into the tracked `Config/Secrets.example.xcconfig` with placeholder hosts, and rewrite its header comment so it documents the service address instead of a Gemini key — **no key, no real host** (FR-008)
- [ ] T003 In `Config/Info.plist`: delete the `GeminiAPIKey` and `GeminiModel` entries, add `KaloriasAPIBaseURL` = `$(KALORIAS_API_BASE_URL)`, and add an `NSAppTransportSecurity` dict containing only `NSAllowsLocalNetworking` = `true` — **no `NSAllowsArbitraryLoads`**, which would weaken ATS for production too (FR-007a, research §2)
- [ ] T004 Create `Kalorias/Support/AppConfiguration.swift` with `static var analysisBaseURL: URL?` (reads `KaloriasAPIBaseURL`, returns `nil` when blank or unparseable) and `static var isConfigured: Bool` — per data-model §5
- [ ] T005 [P] Create `KaloriasTests/AppConfigurationTests.swift` asserting the configured value parses to an **absolute URL with both a scheme and a host** (this is the assertion that catches the xcconfig `//` truncation) and that a blank value yields `nil` — contract C3
- [ ] T006 Register `AppConfigurationTests.swift` in `Kalorias.xcodeproj/project.pbxproj` (`PBXBuildFile`, `PBXFileReference`, group, and the `KaloriasTests` Sources build phase) and confirm it runs

**Checkpoint**: `AppConfiguration.analysisBaseURL` resolves to `http://localhost:8000` in Debug, and its test proves it.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the request/response machinery every user story travels through. **The response
decoder lives here, so its tests live here too** — it is the calorie-bearing logic of the whole
feature and cannot cross a checkpoint untested.

**⚠️ CRITICAL**: no user story work can begin until this phase is complete.

### Request body

- [ ] T007 [P] Create `Kalorias/Features/Analysis/MultipartFormData.swift`: a pure `Sendable` value type producing a one-part body (field `photo`, filename `meal.jpg`, `Content-Type: image/jpeg`) plus a `contentTypeHeaderValue` carrying the same generated boundary — rules M1–M5 in data-model §6
- [ ] T008 [P] Create `KaloriasTests/MultipartFormDataTests.swift`: field name, header/body boundary match, CRLF endings, closing `--boundary--\r\n`, image bytes unaltered, and that the body contains **exactly one part** with no extra fields (FR-002) — contract A1

### Response decoding — implementation and tests together

- [ ] T009 Create `Kalorias/Features/Analysis/AnalyzeMealResponse.swift` with the `data`-enveloped DTOs (`Payload`, `Food`, `Region`) and a static `parse(_:) throws -> AnalysisOutcome`. Strict on `name`/`calories`, lenient (`try?` → `nil`) on macros and region; `Region` maps through the existing `FoodRegion(clampingX:y:width:height:)` **unscaled** — rules D1–D8 in data-model §1
- [ ] T010 [P] Create `KaloriasTests/AnalyzeMealResponseTests.swift` covering the success payload: names, calories, macros, and regions mapping **unscaled, x→x and y→y** (the axis-swap guard) — contracts A2, A4
- [ ] T011 [P] Add to `AnalyzeMealResponseTests.swift`: the `data` envelope is required (a root-level payload is `.invalidResponse`); unknown extra fields are ignored — contracts A3, A12
- [ ] T012 [P] Add to `AnalyzeMealResponseTests.swift`: `region: null`, a malformed region, and a degenerate region each keep the food and yield `region == nil`; `null` macros stay `nil` and are distinct from `0`; the reported total is used verbatim when it differs from the sum — contracts A5, A6, A9
- [ ] T013 [P] Add to `AnalyzeMealResponseTests.swift`: missing `name`, missing `calories`, negative calories, and garbage each throw `.invalidResponse` — contract A8

### Totals and errors

- [ ] T014 Change `CalorieAggregator.make(from:)` to `make(from:reportedTotal:)` in `Kalorias/Features/Analysis/CalorieAggregator.swift`: empty items still yield `.noFood`, but the total is the reported one. Keep `total(of:)` and use it for a **DEBUG-only warning when the reported total differs from the sum** — logged, never corrected, never fatal (research §10, FR-012)
- [ ] T015 Update `KaloriasTests/CalorieAggregatorTests.swift` for the new signature, adding a case where the reported total **differs** from the sum and asserting the reported value wins (FR-012)
- [ ] T016 [P] Add `.photoRejected` and `.rateLimited(retryAfter: TimeInterval)` to `AnalysisError` in `Kalorias/Features/Analysis/AnalysisError.swift` with message keys `analysis.error.photoRejected` and `analysis.error.rateLimited`, preserving `Equatable` and the existing `from(_:)` mapping — data-model §2
- [ ] T017 [P] Extend `KaloriasTests/CalorieAnalysisErrorMappingTests.swift` to cover the two new cases and confirm the existing `URLError`/`DecodingError` mappings are unchanged

### The service

- [ ] T018 Create `Kalorias/Features/Analysis/RemoteCalorieService.swift` conforming to the **unchanged** `CalorieAnalyzing`: builds `POST {base}/api/v1/kalorias/analyzeMeal` with the multipart body, **sets no auth header**, uses a `URLSessionConfiguration.ephemeral` session with `timeoutIntervalForRequest = 35` and `timeoutIntervalForResource = 60`, and maps status → outcome per the table in [contracts/analyze-meal-v1.md](./contracts/analyze-meal-v1.md) (200/422/413/429/503/other). A `nil` base URL throws `.serviceError` — research §3–§5, §8
- [ ] T019 Create `KaloriasTests/RemoteCalorieServiceTests.swift` with a `URLProtocol` stub (no real network): 200 → success, 422 and 413 → `.photoRejected`, 429 → `.rateLimited`, 503/500/418 → `.serviceError`, unreadable 200 → `.invalidResponse`, missing base URL → `.serviceError`, **no `Authorization` header sent** (FR-004), and assertions on the session's configuration: `timeoutIntervalForRequest == 35`, `timeoutIntervalForResource == 60`, `urlCache == nil` (FR-005, FR-006) — contract A10
- [ ] T020 Register `MultipartFormDataTests.swift`, `AnalyzeMealResponseTests.swift` and `RemoteCalorieServiceTests.swift` in `Kalorias.xcodeproj/project.pbxproj` and confirm all three run

**Checkpoint**: the app can send a photo and receive a mapped outcome, and every decoding rule is under test. Nothing is wired to the UI yet and `GeminiCalorieService` still exists.

---

## Phase 3: User Story 1 - Get calories from a photo, with no key in the app (Priority: P1) 🎯 MVP

**Goal**: the core flow works against the Kalorias service, and the provider key is gone from the app.

**Independent Test**: run the stub in `ok` mode, photograph a plate, confirm total 615, two foods, a thumbnail cropped for the located food and none for the other, and that the grep in [quickstart.md §7](./quickstart.md) finds no provider credential.

- [ ] T021 [P] [US1] Create `KaloriasTests/AnalysisPhotoEncoderTests.swift`: longest side ≤ 1024, never upscales a smaller image, output is JPEG whatever the source, result under the 7.5 MB cap, and `nil` when even the lowest quality exceeds it — rules P1–P6
- [ ] T022 [P] [US1] Create `Kalorias/Features/Analysis/AnalysisPhotoEncoder.swift`: downsize via the existing `ImageCropper.downsized(_:maxDimension: 1024)`, encode JPEG at 0.8, falling back to 0.6 then 0.4 only while over the 7.5 MB cap, returning `nil` if still over — research §7
- [ ] T023 [US1] Register `AnalysisPhotoEncoderTests.swift` in `Kalorias.xcodeproj/project.pbxproj` and confirm it runs
- [ ] T024 [US1] Add the `init(rejectedPhoto:)` entry point to `Kalorias/Features/Analysis/CalorieAnalysisStore.swift` — constructed already `.failed(.photoRejected)`, with `start()` returning immediately so `.onAppear` cannot overwrite it, no analyzer call and nothing recorded (data-model §4, rules S7–S9). Cover S7–S9 in `KaloriasTests/CalorieAnalysisStoreTests.swift`
- [ ] T025 [US1] Wire `Kalorias/Features/Camera/CameraCaptureView.swift`: use `AnalysisPhotoEncoder` instead of the raw full-resolution `image.jpegData(compressionQuality: 0.8)` at line 74, construct `RemoteCalorieService()` instead of `GeminiCalorieService()` at line 81, and on a `nil` encoding present `CalorieAnalysisStore(rejectedPhoto:)` **instead of silently dismissing** as line 75 does today (FR-003, FR-023, SC-006)
- [ ] T026 [US1] Update the doc comment on `CalorieAnalysis.totalCalories` in `Kalorias/Features/Analysis/CalorieAnalysis.swift` — the total is now the reported one, not derived. The comment currently asserts the opposite and would mislead the next reader (FR-012)
- [ ] T027 [US1] **Delete** `Kalorias/Features/Analysis/GeminiCalorieService.swift` entirely — prompt, `responseSchema`, `maxOutputTokens`, base64 encoding, `GeminiEnvelope` and `FoodPayload` (FR-009)
- [ ] T028 [US1] **Delete** `Kalorias/Support/AppSecrets.swift` (FR-008)
- [ ] T029 [US1] **Delete** `KaloriasTests/CalorieAnalysisDecodingTests.swift` — all 16 cases. Thirteen of them already exist against the new contract in `AnalyzeMealResponseTests` (T010–T013); the other three assert properties of a request the app no longer makes (FR-010)
- [ ] T030 [US1] **Delete** `FoodRegion.init(geminiTop:left:bottom:right:)` from `Kalorias/Features/Analysis/FoodRegion.swift` and the six `gemini*` cases from `KaloriasTests/FoodRegionTests.swift`; keep every clamping/validation case (FR-009, research §11)
- [ ] T031 [US1] Verify a successful analysis still records a meal through the untouched `MealHistoryRepository` — same foods, same macros including absent ones, same regions (SC-009)

**Checkpoint**: the happy path works end-to-end against the stub and no provider code or credential remains. This is a shippable MVP.

---

## Phase 4: User Story 2 - A photo with no recognizable food is not a failure (Priority: P1)

**Goal**: `foodDetected: false` reaches the existing no-food state, not the error state.

**Independent Test**: run the stub in `nofood` mode, take any photo, confirm the no-food screen with its Retake action and that History gains no entry.

> **This phase is almost entirely verification.** T009 already decodes both no-food shapes, so
> there is no new production code here — do not go looking for some to write.

- [ ] T032 [P] [US2] Add to `KaloriasTests/AnalyzeMealResponseTests.swift`: `foodDetected: false` yields `.noFood`, **and** `foodDetected: true` with an empty `foods` array also yields `.noFood` — contract A7, rule D7
- [ ] T033 [US2] Confirm `RemoteCalorieService` returns `.noFood` as a **success** for a `200` with no food — it must not reach any error path (FR-011)
- [ ] T034 [US2] Verify against the stub (quickstart §6 row 3) that the no-food state saves nothing to History and offers Retake, exactly as before this feature

**Checkpoint**: US1 and US2 both work independently.

---

## Phase 5: User Story 3 - Failures explain themselves and the user can recover (Priority: P2)

**Goal**: every failure the service can return, plus a dead network, produces its own actionable, localized message — and the rate limit counts down.

**Independent Test**: cycle the stub through `422`, `429`, `503` and `garbage`, plus airplane mode, and confirm rows 4–9 of [quickstart.md §6](./quickstart.md) in both languages.

- [ ] T035 [P] [US3] Create `Kalorias/Features/Analysis/RetryCooldown.swift`: a pure value type with `init(seconds:now:)` (clamped `1...3600`), `secondsRemaining(at:)`, `hasExpired(at:)`, and `static parseRetryAfter(_:now:)` defaulting to 60 s — data-model §3
- [ ] T036 [P] [US3] Create `KaloriasTests/RetryCooldownTests.swift`: `Retry-After` as delay-seconds, as an HTTP-date, absent, empty, garbage, negative, and 99999 (clamped to 3600); `secondsRemaining` rounds **up** and floors at 0. **All dates injected — no test sleeps or reads the clock** — contract A11, rules R1–R6
- [ ] T037 [US3] Register `RetryCooldownTests.swift` in `Kalorias.xcodeproj/project.pbxproj` and confirm it runs
- [ ] T038 [US3] Add cooldown state to `Kalorias/Features/Analysis/CalorieAnalysisStore.swift`: `secondsUntilRetry`, `canRetry`, a `cooldownTask` ticking once a second, a `now: () -> Date` seam, and a `retry()` that **returns early while cooling** — the gate lives in the store, not only in the button (rules S1–S6, FR-020)
- [ ] T039 [US3] Add cooldown cases to `KaloriasTests/CalorieAnalysisStoreTests.swift`: `.rateLimited` starts a cooldown; `retry()` is a **no-op** while cooling; reaching zero re-enables it; `cancel()` cancels analysis *and* cooldown; no failure ever triggers a retry the user did not ask for (FR-022a)
- [ ] T040 [P] [US3] Add the three new keys to `Kalorias/Resources/Localizable.xcstrings` with **both** English and Spanish values: `analysis.error.photoRejected`, `analysis.error.rateLimited` (no argument), `analysis.retryIn` (`%lld`) — copy table in [contracts/ui-contracts.md](./contracts/ui-contracts.md), Principle VI
- [ ] T041 [US3] Update the `failed(_:)` branch of `Kalorias/Features/Analysis/AnalysisResultView.swift`: `.photoRejected` shows **Retake** (reusing `analysis.retakeButton`) instead of Retry; `.rateLimited` shows a disabled Retry labelled with the countdown; every other case is unchanged — rules U1–U6
- [ ] T042 [US3] Confirm no failure state displays a calorie number, saves a meal, or shows a request id, HTTP status, provider name or the server's own message text (FR-021a, FR-022, FR-023, FR-024, U6)

**Checkpoint**: all failure rows of quickstart §6 pass in EN and ES.

---

## Phase 6: User Story 4 - A reported problem can be traced (Priority: P3)

**Goal**: the request id reaches the device log, and nothing else does.

**Independent Test**: stream `category == "analysis"` while forcing a `503`; the id appears in clear, and no photo or food name appears anywhere in the stream.

- [ ] T043 [P] [US4] Create `Kalorias/Support/AnalysisLog.swift`: one `Logger(subsystem: <bundle id>, category: "analysis")`, with the request id interpolated `privacy: .public` — otherwise it reads `<private>` in release, which is exactly when it is needed (research §9, rules L1–L5)
- [ ] T044 [US4] Call it from `RemoteCalorieService`: `.info` on success (outcome, duration, food count, `X-Request-Id`), `.error` on failure (outcome, duration, HTTP status, `X-Request-Id`, plus the server's message when the photo was rejected)
- [ ] T045 [US4] Verify by streaming the log (quickstart §7) while forcing a `503`: the request id appears **in clear, not as `<private>`**, and no photo, image bytes or food names appear anywhere in the stream (SC-008, FR-026, FR-027)

**Checkpoint**: all four stories are independently functional.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [ ] T046 Run the full suite: `xcodebuild -project Kalorias.xcodeproj -scheme Kalorias -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test`. Expect `BUILD SUCCEEDED` with **zero warnings** and every pre-existing test still green apart from the 22 deliberately removed (16 in `CalorieAnalysisDecodingTests`, of which 13 are re-created in `AnalyzeMealResponseTests`, plus 6 `gemini*` region cases) — Principle I
- [ ] T047 **Run every row of the [quickstart.md §6](./quickstart.md) validation matrix** — all ten, in the primary language. This is the only place FR-014's UI rule (`—` vs `0 g`, row 2), the full failure set (SC-004) and the locally rejected photo (row 10) are actually exercised end-to-end
- [ ] T048 [P] Run the credential sweep from [quickstart.md §7](./quickstart.md) over sources **and the built binary**; both must return nothing (SC-001)
- [ ] T049 [P] Verify the Release configuration: the built `Info.plist` contains `NSAllowsLocalNetworking` and **no** `NSAllowsArbitraryLoads`, and `KaloriasAPIBaseURL` resolves to an `https://` address (FR-007a)
- [ ] T050 [P] Verify the region crops on at least 10 real photos with foods in clearly different corners — an axis swap or stray ÷1000 raises no error and a passing unit test is not evidence here (SC-003)
- [ ] T051 [P] Verify rows 1, 4 and 5 of quickstart §6 in **Spanish** and in **dark mode**, and row 5 at an accessibility Dynamic Type size — the countdown is the one new string that grows and must not truncate its button (Principle VI)
- [ ] T052 [P] On a physical device, confirm the upload is a few hundred KB rather than megabytes and that the server never answers `422` for size (SC-006), and measure the median end-to-end wait over 10 runs against the current app (SC-007)
- [ ] T053 **Revoke the Gemini API key at the provider.** It was never committed (`Config/Secrets.xcconfig` is git-ignored and untracked) but it has shipped inside every build made so far, and a key inside a distributed binary is extractable. Deleting it from the project does not stop it working
- [ ] T054 Run `/speckit-constitution` to amend the Product Overview and External Services sections: the app's single external service is now the Kalorias backend, and the app holds no provider credential. **Out of scope for this feature's code** — it is a governed document with its own version history (plan.md Complexity Tracking)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies. T001 → T003 → T004 → T005 → T006 are sequential (each needs the previous); T002 is parallel to all of them.
- **Foundational (Phase 2)**: needs Setup. **Blocks every user story.**
- **US1 (Phase 3)**: needs Foundational. The MVP.
- **US2 (Phase 4)**: needs Foundational. Verification only — T009 already implements the behaviour.
- **US3 (Phase 5)**: needs Foundational. Independent of US1 and US2 — it exercises the error paths T018 already maps.
- **US4 (Phase 6)**: needs Foundational. Fully independent; it only adds logging inside the service.
- **Polish (Phase 7)**: needs every story that is being shipped.

### Critical path

T001 → T003 → T004 → T018 (the service cannot be written before it has an address and a body
builder) → T025 (the app cannot call it before the capture site is wired) → T027–T030 (the old
path cannot be deleted before the new one works).

### Within each user story

- A test task and the implementation it covers stay adjacent in the same phase; the suite is green
  before that phase's checkpoint.
- Pure types before the service that uses them; the service before the view that shows it.
- **Deletions come last within US1** (T027–T030): removing `GeminiCalorieService` before
  `CameraCaptureView` is switched over leaves the project uncompilable.

### Parallel opportunities

- T002 runs alongside all of Phase 1.
- T010–T013 are four independent test tasks on one new file — the largest parallel block, and they
  run while T014–T017 proceed on unrelated files.
- T007/T008 (multipart) are independent of T009–T013 (decoding).
- US2, US3 and US4 can be developed simultaneously by different people once Phase 2 is done; they
  touch disjoint files apart from `RemoteCalorieService`, to which US4 only adds log calls.
- T048–T052 are five independent verifications.

---

## Parallel Example: Phase 2 decoding

```bash
# The four decoder test tasks, together, alongside T009:
Task: "T010 success payload + unscaled region mapping in KaloriasTests/AnalyzeMealResponseTests.swift"
Task: "T011 data envelope required; unknown fields ignored"
Task: "T012 null/malformed/degenerate regions; null vs 0 macros; reported total wins"
Task: "T013 missing name, missing calories, negative calories, garbage"
```

---

## Implementation Strategy

### MVP (US1 only)

1. Phase 1 Setup → the app has an address.
2. Phase 2 Foundational → it can send, receive and decode, with the decoder fully tested.
3. Phase 3 US1 → the core flow works and the key is gone.
4. **Stop and validate**: quickstart rows 1 and 2, plus the §7 credential sweep.

That is already the whole point of the feature: the key is out of the binary and calories still
appear. US2 is a few tests away, and US3/US4 harden it.

### Incremental delivery

Setup + Foundational → US1 (MVP, demo) → US2 → US3 → US4 → Polish. Each step leaves the app
shippable.

---

## Notes

- **The one-way door is T027–T030.** Once the provider code is deleted the app cannot analyze
  anything without a reachable server. That is deliberate (FR-009) — a fallback would keep the key
  in the binary and defeat the feature.
- Region correctness cannot be proven by a green test (T050). An axis swap produces a
  valid-looking crop of the wrong food, silently.
- No XCUITest work anywhere in this list, per Principle II. Accessibility identifiers are added as
  part of the view task so future UI tests remain possible.
- Commit after each task or logical group; stop at any checkpoint to validate a story on its own.
