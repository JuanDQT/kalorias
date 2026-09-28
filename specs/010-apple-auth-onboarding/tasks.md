---
description: "Task list for feature 010: Sign in with Apple After Local Onboarding"
---

# Tasks: Sign in with Apple After Local Onboarding

**Input**: Design documents from `/specs/010-apple-auth-onboarding/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md),
[data-model.md](./data-model.md), [contracts/auth-api-v1.md](./contracts/auth-api-v1.md),
[contracts/ui-contracts.md](./contracts/ui-contracts.md), [quickstart.md](./quickstart.md)

**Tests**: REQUIRED. The constitution makes test-first non-negotiable (Principle II) and
`quickstart.md` fixes the required unit/integration coverage. XCUITest stays disabled: no UI test is
authored or run for this feature.

**Organization**: Tasks are grouped by user story so each story is independently implementable and
testable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: `[US1]`–`[US4]`, mapping to the spec's prioritized user stories
- Every task names its exact file path

## Path Conventions

Single native iOS project at the repository root:

- App sources: `Kalorias/` (filesystem-synchronized group — new sources are discovered automatically)
- Tests: `KaloriasTests/` (**manual Xcode group**)
- Project file: `Kalorias.xcodeproj/project.pbxproj`

## ⚠️ Standing Rule for Every New Test File

`KaloriasTests` is not filesystem-synchronized. Each new test file MUST be registered in **all three**
`Kalorias.xcodeproj/project.pbxproj` locations before its task counts as done:

1. `PBXFileReference` entry
2. Membership in the `KaloriasTests` `PBXGroup`
3. Membership in the `KaloriasTests` target's `PBXSourcesBuildPhase`

A green test command that never compiled the new file is not a valid result.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Enable the Sign in with Apple capability and prepare the shared source/localization
surfaces the feature needs.

- [X] T001 Create `Kalorias/Kalorias.entitlements` declaring `com.apple.developer.applesignin` = `[Default]`, with no other entitlement added
- [X] T002 Set `CODE_SIGN_ENTITLEMENTS = Kalorias/Kalorias.entitlements` for the Kalorias app target's Debug and Release build configurations in `Kalorias.xcodeproj/project.pbxproj`
- [X] T003 [P] Create the `Kalorias/Authentication/` directory with a first source file, and confirm Xcode's synchronized group discovers it without a manual `project.pbxproj` edit
- [X] T004 [P] Add every localization key from the "Localization Key Inventory" of `specs/010-apple-auth-onboarding/contracts/ui-contracts.md` to `Kalorias/Resources/Localizable.xcstrings` with English and Spanish values, reusing existing generic keys where semantics are identical instead of duplicating entries
- [X] T005 Record the pre-feature baseline by running the `xcodebuild ... build` and `xcodebuild ... test` commands from `specs/010-apple-auth-onboarding/quickstart.md` and confirming zero warnings and a green suite

**Checkpoint**: Capability, source location and copy catalog are ready.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Persistence primitives, credential storage and the root journey state machine that every
user story depends on.

**⚠️ CRITICAL**: No user story work may begin until this phase is complete.

### Value types and persistence primitives

- [X] T006 [P] Create `Kalorias/Support/ProtectedFileStore.swift` with a `Sendable` non-`@MainActor` type that performs atomic writes with `.completeFileProtection`, reads, and idempotent deletes under Application Support, distinguishing "unavailable while locked" from "missing"
- [X] T007 [P] Create `Kalorias/Authentication/OnboardingServerStatus.swift` with a `Codable, Sendable` enum of exactly `required` and `complete` that fails decoding on any unknown wire value
- [X] T008 [P] Create `Kalorias/Features/Onboarding/ConsentReceipt.swift` with `privacyNoticeVersion`, `healthDataConsentVersion` and `grantedAt` per `data-model.md`, plus the compiled approved version constants
- [X] T009 [P] Create `Kalorias/Authentication/AuthSession.swift` with the `AuthSession` and `KnownAccount` `Codable, Sendable` records and their `schemaVersion`, validating empty identifiers/tokens and inconsistent expiry ordering (depends on T007)
- [X] T010 [P] Create `Kalorias/Authentication/AccountDeletionAttempt.swift` with `schemaVersion`, `operationId`, `presentedAccessToken`, `ownerUserID` and `confirmedAt`, and a log representation that never emits the bearer
- [X] T011 Create `Kalorias/Features/Onboarding/PendingOnboarding.swift` holding `schemaVersion`, the immutable `OnboardingSubmission` and an optional `ConsentReceipt`, with a sealing initializer that validates completeness against the pinned questionnaire (depends on T008)

### Credential storage

- [X] T012 Create `Kalorias/Authentication/KeychainCredentialStore.swift` with an injectable protocol plus a `Security`-backed implementation storing separate `AuthSession`, `KnownAccount` and `AccountDeletionAttempt` items using `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and no synchronization (depends on T009, T010)
- [X] T013 Create `KaloriasTests/KeychainCredentialStoreTests.swift` covering add/update/read/delete per record, device-only non-synchronizing attributes, decode failure and the no-duplicate-item regression, and register the file in `Kalorias.xcodeproj/project.pbxproj` (depends on T012)
- [X] T088 Create `KaloriasTests/AuthFixtures.swift` with the shared deterministic session/known-account/deletion-attempt/credential fixtures and stub Keychain, URL protocol and clock adapters every auth test depends on, and register it in `Kalorias.xcodeproj/project.pbxproj` (depends on T009, T010, T012)

### Protected onboarding storage

- [X] T014 Split `Kalorias/Features/Onboarding/OnboardingStorage.swift` into a non-sensitive questionnaire cache path and a protected draft path, moving the draft to `ProtectedFileStore` while keeping `sessionId`, `contentVersion` and `startedAt` immutable across resume (depends on T006; questionnaire-cache portion superseded by Phase 8)
- [X] T015 Create `Kalorias/Features/Onboarding/PendingOnboardingStorage.swift` with atomic protected read/write/delete of `PendingOnboarding`, a consent-update operation, and idempotent cleanup (depends on T006, T011)
- [X] T016 Create `KaloriasTests/PendingOnboardingStorageTests.swift` covering atomic round trip, consent update, corruption surfaced as a recoverable error, file-protection attributes, restart recovery and repeated cleanup, and register it in `Kalorias.xcodeproj/project.pbxproj` (depends on T015)

### Root journey state machine

- [X] T017 [P] Create `Kalorias/App/AppJourneyPhase.swift` with the `restoring`, `onboarding`, `access`, `consent`, `finalizing`, `ready` and `deletingAccount` cases and their associated state per `data-model.md`
- [X] T018 Create `Kalorias/App/AppJourneyStore.swift` as an `@MainActor @Observable` store that owns `phase`, injects storage/keychain/service dependencies, and implements the full bootstrap resolution table from `data-model.md` including the locked-device `restoring` and corrupted-payload rules (depends on T012, T014, T015, T017)
- [X] T019 Create `KaloriasTests/AppJourneyStoreTests.swift` asserting every row of the bootstrap resolution table in `specs/010-apple-auth-onboarding/data-model.md`, including the deletion-attempt precedence row, the locked-device `restoring` row and the `KnownAccount` reconciliation from a valid session, and register the file in `Kalorias.xcodeproj/project.pbxproj` (depends on T018, T088)
- [X] T020 Replace the `@AppStorage` completion flag and onboarding modal in `Kalorias/App/RootView.swift` with an exhaustive switch over `AppJourneyStore.phase`, animating transitions with the existing `AppMotion.standard` pair (depends on T018)
- [X] T021 Compose `AppJourneyStore` and its services in `Kalorias/KaloriasApp.swift`, restoring durable state before the authenticated shell is built and removing the old boolean gate (depends on T018, T020)

**Checkpoint**: Foundation ready — user story implementation can begin.

---

## Phase 3: User Story 1 - Complete onboarding without creating an account first (Priority: P1) 🎯 MVP

**Goal**: The questionnaire is answered first, every accepted answer is written only to protected
local storage, and finishing seals a pending submission before the access screen appears.

**Independent Test**: Complete the whole onboarding with a network proxy attached, force-terminate
midway once, and confirm answers resume locally and that no request body contains onboarding answers
before registration.

### Tests for User Story 1

- [X] T022 [P] [US1] Extend `KaloriasTests/OnboardingStoreTests.swift` with failing tests that each accepted answer is durably persisted before the next question is presented, that a draft write failure does not advance the question, and that the final answer performs zero submission calls
- [X] T023 [P] [US1] Cover sealing in `KaloriasTests/OnboardingStoreTests.swift`: the sealed payload preserves `sessionId`, `onboardingId`, `schemaVersion`, `contentVersion`, `locale`, `startedAt` and the local `completedAt`, an incomplete flow cannot be sealed, and resealing after a review edit keeps the same `sessionId`
- [X] T024 [P] [US1] Add a failing test to `KaloriasTests/AppJourneyStoreTests.swift` that the `onboarding → access` transition only publishes after the protected pending write succeeds, and that a failed seal leaves the phase on `onboarding` (depends on T019)
- [X] T089 [P] [US1] Add a failing test to `KaloriasTests/OnboardingSubmissionTests.swift` that the public `GET /api/v1/kalorias/onboarding?stage=onboarding` built by `Kalorias/Features/Onboarding/RemoteOnboardingService.swift` carries no `Authorization` header, no user, device or analytics identifier and no draft content, per `quickstart.md` "Required Unit/Integration Coverage"

### Implementation for User Story 1

- [X] T025 [US1] Split `Kalorias/Features/Onboarding/OnboardingProviding.swift` into a public `OnboardingFetching` capability and a separate authenticated `OnboardingSubmitting` capability so a public fetch cannot carry a draft or account identity
- [X] T026 [US1] Remove the submission call from the final intent of `Kalorias/Features/Onboarding/OnboardingStore.swift`, replacing it with sealing an immutable `PendingOnboarding`, writing it, and only then reporting local completion (depends on T015, T025)
- [X] T027 [US1] Update `Kalorias/Features/Onboarding/RemoteOnboardingService.swift` so `GET /api/v1/kalorias/onboarding?stage=onboarding` remains anonymous with unchanged `ETag`/`304`/bundled-fallback behavior and sends no `Authorization`, user, device or analytics identity (depends on T025; cache/fallback portion superseded by Phase 8)
- [X] T028 [US1] Add a localized storage-failure path to `Kalorias/Features/Onboarding/OnboardingChatView.swift` that distinguishes "could not save on this device" from a network failure and does not advance the question (depends on T026)
- [X] T029 [US1] Create `Kalorias/Features/Access/AccessView.swift` with the layout, states and accessibility identifiers from `contracts/ui-contracts.md`, on opaque `AppColor.surfacePrimary`, with the "Review answers" secondary action and inline status/error region; the Apple control is added in US2 (depends on T004, T020)
- [X] T030 [US1] Wire the `onboarding → access` and `access → onboarding` (Review answers) intents in `Kalorias/App/AppJourneyStore.swift`, resealing a replacement snapshot with the same session identity on review (depends on T026, T029)

**Checkpoint (superseded by Phase 8)**: A first-run user could answer everything offline. The current
product requires a live backend questionnaire while keeping answers local and durable.

---

## Phase 4: User Story 2 - Register with Apple, then send the saved answers (Priority: P1)

**Goal**: Apple authorization and Kalorias registration commit first; a separate versioned health-data
consent then permits exactly one authenticated, idempotent onboarding submission.

**Independent Test**: Complete onboarding, register with Apple against a staging backend, and confirm
from server logs that account creation commits before the first authenticated onboarding request,
that the Apple-auth request contains no answers, and that the confirmed onboarding opens the app.

### Tests for User Story 2

- [X] T031 [P] [US2] Create `KaloriasTests/AppleSignInRequestFactoryTests.swift` covering secure raw-nonce shape, lowercase SHA-256 hashed nonce, an independent random state, exact callback state comparison, credential mapping failures, and that no name or email scope is requested; register it in `Kalorias.xcodeproj/project.pbxproj`
- [X] T032 [P] [US2] Create `KaloriasTests/RemoteAuthServiceTests.swift` asserting exact method/path/body for `/auth/apple`, `/auth/refresh`, `/auth/logout` and `DELETE /api/v1/account`, that the auth body encodes no answers/email/name/client Apple ID, response validation (`tokenType`, unknown status, empty opaque values, invalid dates, expiry ordering), and the stable error-code mapping; register it in `Kalorias.xcodeproj/project.pbxproj`
- [X] T033 [P] [US2] Create `KaloriasTests/AuthSessionCoordinatorTests.swift` covering proactive near-expiry refresh, one in-flight refresh shared by concurrent callers, atomic token rotation commit, paired `AuthSession`/`KnownAccount` commit, and transient versus definitive failure; register it in `Kalorias.xcodeproj/project.pbxproj`
- [X] T034 [P] [US2] Create `KaloriasTests/AuthenticatedHTTPClientTests.swift` covering Bearer attachment, exactly one `401` refresh plus one replay, no loop on a second `401`, no refresh for `409`/`422`, the non-replayable opt-out, and the `authenticationRequired` event reaching `AppJourneyStore`; register it in `Kalorias.xcodeproj/project.pbxproj` (depends on T088)
- [X] T035 [P] [US2] Extend `KaloriasTests/OnboardingSubmissionTests.swift` with failing tests that the authenticated submission built by `Kalorias/Features/Onboarding/RemoteOnboardingSubmissionService.swift` carries `Authorization`, the consent envelope and `Idempotency-Key == sessionId`, and that a `complete` response is validated before any local cleanup
- [X] T036 [P] [US2] Extend `KaloriasTests/AppJourneyStoreTests.swift` with failing tests for the `access → consent`/`finalizing`/`ready`/`onboarding` transitions driven by the persisted backend status, and for the commit ordering `AuthSession → KnownAccount → publish phase` (depends on T019)

### Implementation for User Story 2

- [X] T037 [P] [US2] Create `Kalorias/Authentication/AppleSignInRequestFactory.swift` producing an in-memory `AppleSignInAttempt` (raw nonce, lowercase SHA-256 hashed nonce, independent state) with CryptoKit, requesting no Apple name/email scope, and clearing the attempt on callback, cancellation, error or a new attempt
- [X] T038 [P] [US2] Create `Kalorias/Authentication/AppleAuthorizationCredential.swift` as a `Sendable` value mapped from `ASAuthorizationAppleIDCredential`, failing closed on missing data, invalid UTF-8, empty values, the wrong authorization type or a state mismatch, and never conforming to a loggable description
- [X] T039 [US2] Create `Kalorias/Authentication/RemoteAuthService.swift` implementing `POST /auth/apple`, `POST /auth/refresh` and `POST /auth/logout` against `BackendEnvironment`, with response validation and stable error-code mapping per `contracts/auth-api-v1.md` (depends on T009)
- [X] T040 [US2] Create `Kalorias/Authentication/AuthSessionCoordinator.swift` as an `actor` that is the sole owner of Keychain token rotation and single-flight refresh, serializing access-token vending and refresh (depends on T012, T039)
- [X] T041 [US2] Create `Kalorias/Authentication/AuthenticatedHTTPClient.swift` implementing the "Authenticated Client Algorithm" from `contracts/auth-api-v1.md`, including the opt-out for non-replayable requests and the `authenticationRequired` event to `AppJourneyStore` (depends on T040)
- [X] T042 [US2] Add the native `SignInWithAppleButton(.continue)` and its request/completion wiring to `Kalorias/Features/Access/AccessView.swift`, with a single-active-attempt guard, the in-progress disabled state, and quiet non-destructive cancellation feedback (depends on T029, T037, T038)
- [X] T043 [US2] Create `Kalorias/Features/Access/PrivacyNoticeView.swift` rendering the approved localized notice with semantic headings, the external policy link, and the identifiers from `contracts/ui-contracts.md` (depends on T004)
- [X] T044 [US2] Create `Kalorias/Features/Access/HealthDataConsentView.swift` with the summary, privacy link, "Accept and create plan" and "Not now" actions, no preselected acceptance, and a retryable local receipt-write error state (depends on T008, T043)
- [X] T045 [US2] Create `Kalorias/Features/Access/FinalizingOnboardingView.swift` with the in-progress, failed, relaunch-recovery and success states, a disabled duplicate submit, and the identifiers from `contracts/ui-contracts.md` (depends on T004)
- [X] T046 [US2] Create `Kalorias/Features/Onboarding/RemoteOnboardingSubmissionService.swift` implementing the authenticated `OnboardingSubmitting` capability: send the sealed body plus the consent envelope through `AuthenticatedHTTPClient` with `Idempotency-Key = sessionId` and map the stable error codes from `contracts/auth-api-v1.md` (depends on T041, T025)
- [X] T047 [US2] Implement the registration and finalization intents in `Kalorias/App/AppJourneyStore.swift`: persist `AuthSession` then `KnownAccount` before publishing a server-derived phase, persist the `ConsentReceipt` before any network work, start the first upload automatically after fresh consent only, and on success persist `complete` status before deleting the pending/draft files (depends on T040, T044, T045, T046)
- [X] T048 [US2] Discard a redundant pending payload in `Kalorias/App/AppJourneyStore.swift` when an authenticated account reports `onboarding complete`, without sending or overwriting it (depends on T047)

**Checkpoint**: A new account registers with Apple, consents separately, and its sealed answers are
submitted once and confirmed before the main app opens.

---

## Phase 5: User Story 3 - Recover safely from cancellation, interruption and network failure (Priority: P2)

**Goal**: Every interruption after the last answer is recoverable, with no lost answers and no
duplicate account or plan.

**Independent Test**: Force-terminate at each of the five registration/submission boundaries and
verify relaunch resumes at the correct boundary with no duplicate records.

### Tests for User Story 3

- [X] T049 [P] [US3] Extend `KaloriasTests/AppJourneyStoreTests.swift` with failing tests for relaunch at each boundary: before Apple, after Apple before the auth response, after registration, during submission, and after server acceptance before the client processed the response (depends on T019)
- [X] T050 [P] [US3] Extend `KaloriasTests/AppJourneyStoreTests.swift` with failing tests that a bootstrap with a consented pending payload never uploads silently and requires a user-initiated retry, and that a failed upload preserves both the sealed payload and a still-valid session (depends on T019)
- [X] T051 [P] [US3] Extend `KaloriasTests/AuthSessionCoordinatorTests.swift` with tests that a rejected or reused refresh token invalidates the local session family while preserving the account marker and the pending answers/consent
- [X] T052 [P] [US3] Extend `KaloriasTests/OnboardingSubmissionTests.swift` with failing tests that a retry after a timeout reuses the identical canonical body and idempotency key, that `onboarding_already_complete` reconciles instead of resubmitting, and that `idempotency_payload_mismatch` stops retrying without generating a new key

### Implementation for User Story 3

- [X] T053 [US3] Complete the remaining bootstrap resolution rows in `Kalorias/App/AppJourneyStore.swift`: `required` status with no pending payload resumes `onboarding`, an absent session with a known account goes to `access` and never restarts first run, and a locked-device protected read stays in `restoring` (depends on T018, T047)
- [X] T054 [US3] Implement manual-only retry in `Kalorias/Features/Access/FinalizingOnboardingView.swift` and its store intent, so no automatic retry runs after a displayed failure or after relaunch (depends on T045, T047)
- [X] T055 [US3] Handle an unrefreshable session during finalization in `Kalorias/App/AppJourneyStore.swift` by removing only the active session and returning to `access` with the pending payload and consent intact (depends on T041, T047)
- [X] T056 [US3] Map `429` with `Retry-After` and the recoverable `503`/`500` service codes to the delayed/enabled Apple action and localized copy in `Kalorias/Features/Access/AccessView.swift` (depends on T039, T042)
- [X] T057 [US3] Freeze the sealed payload in `Kalorias/App/AppJourneyStore.swift` once an authenticated submission attempt begins, disabling "Review answers" until the attempt succeeds or is explicitly discarded (depends on T030, T047)
- [X] T058 [US3] Ensure `Kalorias/Features/Access/AccessView.swift` clears the ephemeral nonce/state and requires a wholly fresh attempt after an invalid callback, a state mismatch or `auth_attempt_replayed`, sending nothing when the local comparison fails (depends on T037, T042)

**Checkpoint**: The journey survives cancellation, termination, expiry and server outages without
losing answers or creating duplicates.

---

## Phase 6: User Story 4 - Keep the account and local data private throughout its lifecycle (Priority: P3)

**Goal**: Tokens and health data stay protected, credential revocation gates access, local meals are
scoped per account, and account deletion removes server and on-device data.

**Independent Test**: Inspect persisted values and logs, revoke the app from Apple, authenticate a
second identity, and delete a test account.

### Tests for User Story 4

- [X] T059 [P] [US4] Extend `KaloriasTests/MealHistoryRepositoryTests.swift` with failing tests that a write without an active owner is rejected, that one owner's rows are invisible to another, that legacy `nil`-owner rows stay hidden, and that `clearLocalData(ownedBy:)` removes only the selected owner's rows
- [X] T060 [P] [US4] Extend `KaloriasTests/ImageStoreTests.swift` with failing tests for `.completeFileProtection` on saved images and for an idempotent current-owner batch deletion that runs off the main actor
- [X] T061 [P] [US4] Update `KaloriasTests/RemoteCalorieServiceTests.swift` for the superseded feature-009 no-auth contract: replace `testNoAuthorizationHeaderIsSent` with failing tests that the analysis request goes through `AuthenticatedHTTPClient`, carries a Bearer token, and replays exactly once only after an auth-first `401` (FR-047)
- [X] T062 [P] [US4] Extend `KaloriasTests/RouterTests.swift` with failing tests for the `ProgressRoute.account` destination and for clearing `progressPath` and camera presentation before an identity gate
- [X] T063 [P] [US4] Create `KaloriasTests/AppleCredentialStateServiceTests.swift` asserting that only definitive `revoked`/`notFound` clears the active session while a transient lookup failure preserves local state and `transferred` surfaces a recoverable migration condition; register it in `Kalorias.xcodeproj/project.pbxproj` (depends on T088)
- [X] T064 [P] [US4] Extend `KaloriasTests/AppJourneyStoreTests.swift` with failing tests for the deletion flow: the persisted attempt takes precedence over `ready` at bootstrap, any non-`204` result performs zero local cleanup, and a `204` runs the `data-model.md` cleanup order before publishing `onboarding` (depends on T019)

### Implementation for User Story 4

- [X] T065 [P] [US4] Add `ownerUserID: String?` to `Kalorias/Features/History/MealEntry.swift` so the existing store migrates lightly, with `nil` legacy rows never auto-assigned to an account
- [X] T066 [US4] Make `Kalorias/Features/History/MealHistoryRepository.swift` owner-aware: reject writes without an active backend user ID, filter reads by `ownerUserID`, and scope deletion to that owner (depends on T065)
- [X] T067 [P] [US4] Apply the `ownerUserID == activeUserID` predicate to the `@Query` in `Kalorias/Features/History/HistoryView.swift` and derive detail navigation from the already-filtered result (depends on T065)
- [X] T068 [P] [US4] Apply the same owner predicate to the `@Query` in `Kalorias/Features/Progress/ProgressTabView.swift` (depends on T065)
- [X] T069 [P] [US4] Add complete file protection to writes and an off-main-actor idempotent batch deletion for a named set of images in `Kalorias/Features/History/ImageStore.swift`
- [X] T070 [US4] Route `Kalorias/Features/Analysis/RemoteCalorieService.swift` through `AuthenticatedHTTPClient` so the multipart analysis request carries the Bearer token and replays at most once, and fail the analysis rather than calling anonymously when no client is composed (depends on T041)
- [X] T071 [P] [US4] Create `Kalorias/Authentication/AppleCredentialStateService.swift` wrapping `ASAuthorizationAppleIDProvider` credential-state lookup into the `authorized`/`revoked`/`notFound`/`transferred`/`temporarilyUnavailable` values from `data-model.md`
- [X] T072 [US4] Check credential state at bootstrap and foreground and observe Apple's revocation notification in `Kalorias/App/AppJourneyStore.swift`, invalidating only on definitive results and surfacing `transferred` with the `account.transfer.*` copy (depends on T071)
- [X] T073 [US4] Add the `ProgressRoute.account` destination, the `openAccount()` intent and a safe identity-reset path clear (including camera dismissal) to `Kalorias/App/Router.swift`
- [X] T074 [US4] Add the account toolbar action and `navigationDestination` to `Kalorias/Features/Progress/ProgressTabView.swift` and create `Kalorias/Features/Account/AccountSettingsView.swift` with the safe account status, privacy action and destructive delete action per `contracts/ui-contracts.md` (depends on T043, T073)
- [X] T075 [US4] Create `Kalorias/Features/Account/AccountDeletionView.swift` with the progress, retryable-error and Continue-replay states and its accessibility identifiers (depends on T004)
- [X] T076 [US4] Add `DELETE /api/v1/account` to `Kalorias/Authentication/RemoteAuthService.swift`, presenting the exact stored Bearer and stable operation key without proactive refresh on replay, and accepting only `204` as success (depends on T010, T039)
- [X] T077 [US4] Implement the deletion intent in `Kalorias/App/AppJourneyStore.swift`: persist `AccountDeletionAttempt` and enter `deletingAccount` before the first request, keep everything intact on any non-`204`, and on `204` run the `data-model.md` cleanup order — clear navigation/camera, delete only the owner's SwiftData rows, delete their images off the main actor, clear protected onboarding files, remove all three Keychain records, then publish `onboarding` (depends on T066, T069, T075, T076)
- [X] T078 [US4] Create `Kalorias/Support/AuthLog.swift` with an `auth` category whose signatures accept only a stage, a stable outcome and the server `X-Request-Id`, making a token, Apple subject, nonce, email, user id, answer or health value impossible to pass, and route every new auth/account file through it

**Checkpoint**: All four user stories are independently functional.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T079 [P] Add the DEBUG-only `-journey-state …` and `-account-deletion-error` launch-argument fixtures from `contracts/ui-contracts.md` to `Kalorias/KaloriasApp.swift`, compiled out of Release and never weakening Keychain, Apple authorization or server verification
- [X] T080 [P] Verify every accessibility identifier listed in `contracts/ui-contracts.md` exists on the corresponding control across `Kalorias/Features/Access/` and `Kalorias/Features/Account/`
- [ ] T081 [P] Run the "UX, Localization, and Accessibility Pass" of `specs/010-apple-auth-onboarding/quickstart.md` in EN and ES, light and dark, largest accessibility Dynamic Type, VoiceOver, Reduce Motion, Increase Contrast and Reduce Transparency
- [X] T082 [P] Confirm `KaloriasTests/PaletteContrastTests.swift` still passes for every token used by the new gates and that no new view introduces an inline font, spacing, color, spring, glass or material literal
- [ ] T083 Run the "Privacy Boundary Audit" of `specs/010-apple-auth-onboarding/quickstart.md` with a network proxy, confirming that only the public questionnaire GET and Apple's system traffic precede a successful registration, and that `UserDefaults` holds no completion authority, token, Apple identifier, answer or receipt
- [X] T084 Extend `KaloriasTests/BackendEnvironmentAuditTests.swift` to assert that no endpoint path or credential is added to `Config/Secrets.example.xcconfig` and that every new service composes its URL from the single validated base URL
- [ ] T085 Take the "Performance Measurements" from `specs/010-apple-auth-onboarding/quickstart.md`: cold launch under 2 s, an accepted answer durable in under 100 ms at p95, responsive owner-filtered queries at 10,000 mixed-owner meals, and one refresh under an expired-token burst
- [X] T086 Run the full `xcodebuild ... test` suite from `quickstart.md` and confirm zero warnings under Swift 6 complete concurrency, with `AppJourneyStoreTests.swift`, `AuthenticatedHTTPClientTests.swift` and `AppleCredentialStateServiceTests.swift` actually compiled by the `KaloriasTests` target
- [ ] T087 Walk the complete "Manual End-to-End Matrix" and "Release Gate" of `specs/010-apple-auth-onboarding/quickstart.md` on a physical device against the staging backend

---

## Phase 8: Backend-Only Questionnaire Amendment

- [X] T090 Remove questionnaire disk/bundle fallback and background refresh while preserving protected answer drafts across app termination
- [X] T091 Force the public questionnaire request to bypass URL caches and surface a retryable error whenever the backend cannot provide a valid questionnaire
- [X] T092 Remove embedded questionnaire resources, their generator, and bundle-only tests/project references
- [X] T093 Align the feature specification, plan, contract, research notes, quickstart, backend documentation, and functional guide with the backend-only rule
- [X] T094 Classify unsupported questionnaire schemas, types, and structural values as a mandatory app update instead of a retryable service failure
- [X] T095 Add a non-dismissible localized update gate that opens the configured App Store listing and never exposes stale onboarding content
- [X] T096 Cover the compatibility gate and App Store release configuration with unit tests
- [X] T097 Support `date.mode = dateTime` from picker through protected draft and RFC 3339 submission, preserving IANA zone and captured UTC offset

**Checkpoint**: Without a valid backend response there are no questions. After relaunch, a successful
fetch of the same questionnaire version restores the protected answers at the correct position.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies
- **Foundational (Phase 2)**: depends on Setup — **blocks every user story**
- **US1 (Phase 3)**: depends on Foundational
- **US2 (Phase 4)**: depends on Foundational; consumes the sealed payload produced by US1
- **US3 (Phase 5)**: depends on Foundational; hardens the US2 boundaries
- **US4 (Phase 6)**: depends on Foundational; its analysis/deletion work depends on the authenticated
  client from US2 (T041)
- **Polish (Phase 7)**: depends on all desired stories

### User Story Dependencies

- **US1 (P1)**: independent after Foundational. Testable on its own — it ends at Access.
- **US2 (P1)**: needs a sealed pending payload. In practice it follows US1; a fixture payload from
  T088 lets it be tested independently.
- **US3 (P2)**: exercises the US2 boundaries. It adds no new endpoint, only recovery semantics.
- **US4 (P3)**: local ownership (T065–T069) and the credential-state service (T071) are fully
  independent of US2; the analysis and deletion routes require T041.

### Critical Path Through the Remaining Work

`T019` is the widest blocker left: `T024`, `T036`, `T049`, `T050` and `T064` all extend
`KaloriasTests/AppJourneyStoreTests.swift`, so they are sequential against each other and cannot
start until that file exists and is registered in `project.pbxproj`.

### Parallel Opportunities

- Setup: T003 and T004 run in parallel.
- Foundational value types: T006, T007, T008, T009 and T010 are five different new files.
- Remaining test files: T034, T063 and T019 are three independent new files.
- Remaining test extensions: T035/T052 (submission), T059, T060, T061 and T062 touch five different
  existing files and run in parallel with each other and with T019.
- Polish: T079–T082 are parallel.

---

## Parallel Example: Remaining Test Work

```bash
# Three independent new test files:
Task: "Create KaloriasTests/AppJourneyStoreTests.swift"
Task: "Create KaloriasTests/AuthenticatedHTTPClientTests.swift"
Task: "Create KaloriasTests/AppleCredentialStateServiceTests.swift"

# Five independent existing test files:
Task: "Extend KaloriasTests/OnboardingSubmissionTests.swift"
Task: "Extend KaloriasTests/MealHistoryRepositoryTests.swift"
Task: "Extend KaloriasTests/ImageStoreTests.swift"
Task: "Update KaloriasTests/RemoteCalorieServiceTests.swift"
Task: "Extend KaloriasTests/RouterTests.swift"
```

---

## Implementation Strategy

### MVP First (User Story 1)

1. Phase 1: Setup
2. Phase 2: Foundational (blocks everything)
3. Phase 3: User Story 1
4. **STOP and VALIDATE**: onboarding completes offline, seals a protected payload, and reaches Access
   with zero answer traffic

### Incremental Delivery

1. Setup + Foundational → root state machine replaces the boolean gate
2. + US1 → local-first onboarding (MVP)
3. + US2 → Apple registration, consent and confirmed submission — the first shippable end-to-end flow
4. + US3 → interruption and failure hardening
5. + US4 → per-account isolation, revocation handling and account deletion
6. + Polish → audits, accessibility, performance and the release gate

### Release Prerequisites (outside this task list)

Apple Developer capability enablement, backend production credentials, approved legal consent copy,
published privacy policy and App Store privacy answers are release inputs. They do not change the
state machine or the API contract.

---

## Notes

- `[P]` means a different file with no incomplete dependency.
- Every new `KaloriasTests` file must be registered in all three `project.pbxproj` locations.
- Tests are written first and must fail before the matching implementation task. Where a `[X]`
  implementation task is paired with an unchecked test task, the test still has to be written and
  seen to fail against a deliberately reverted behavior before it counts.
- No XCUITest is authored or enabled for this feature.
- Commit after each task or logical group; stop at any checkpoint to validate a story independently.
