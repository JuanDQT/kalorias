# Implementation Plan: Sign in with Apple After Local Onboarding

**Branch**: `010-apple-auth-onboarding` | **Date**: 2026-09-08 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/010-apple-auth-onboarding/spec.md`

## Summary

Kalorias will keep the questionnaire as the first-run experience, persist every accepted answer
only on the device, and seal a protected pending submission before showing the native Sign in with
Apple control. Apple authentication creates or restores a Kalorias account in a separate request;
only after that request commits, and after a distinct versioned health-data consent, may the app
send the pending onboarding through an authenticated and idempotent endpoint.

The implementation replaces the current `@AppStorage` completion flag and modal gate with a
durable root journey store. Backend tokens live in Keychain, sensitive onboarding files use iOS
complete file protection, all authenticated traffic passes through a single refresh-aware HTTP
client, and local meal rows are scoped by the backend user identifier. The external backend is not
implemented in this repository; its complete handoff remains [backend-handoff.md](./backend-handoff.md),
while [contracts/auth-api-v1.md](./contracts/auth-api-v1.md) is the client-facing wire contract.

## Technical Context

**Language/Version**: Swift 6.0 with complete strict concurrency and default `MainActor` isolation

**Primary Dependencies**: SwiftUI, AuthenticationServices, Security/Keychain, CryptoKit,
Foundation/URLSession, Observation, SwiftData; no third-party dependency

**Storage**: SwiftData for meal history; Application Support JSON for questionnaire cache and
protected onboarding draft/pending payload; Keychain for sessions and durable account identity

**Testing**: XCTest unit and integration-style URL protocol tests in `KaloriasTests`; UI tests stay
disabled unless the maintainer explicitly opts in

**Target Platform**: iOS 26.5+

**Project Type**: Native single-target iOS app plus an external Kalorias API

**Performance Goals**: Cold launch below 2 seconds on the project reference device; locally
accepted answer durably saved and reflected in under 100 ms; owner-filtered history/progress
queries remain responsive at 10,000 meals; state transitions render at native frame cadence

**Constraints**: Questionnaire must remain usable offline from bundled/cached content; no personal
answer leaves the device before backend registration and explicit health-data consent; no secrets
or tokens in source, preferences, files, telemetry, or logs; refresh is single-flight and a failed
request is retried at most once; no custom authentication web view

**Scale/Scope**: One first-run journey, four new root gates (access, consent, finalization, deletion
recovery), one account-settings destination, four auth/account endpoints, two existing endpoints upgraded to
Bearer authentication, and per-account isolation for the existing local meal store

## Constitution Check

*GATE: Passed before Phase 0 research and re-checked after Phase 1 design.*

| Rule | Design evidence | Result |
|---|---|---|
| Swift 6 strict concurrency | UI orchestration is an `@MainActor @Observable` store; mutable session/refresh state is isolated in an actor; cross-boundary values are `Sendable` value types. | Pass |
| MVS plus Router | `AppJourneyStore` owns reusable journey state and intents; views remain declarative; `Router` owns account navigation. No per-view ViewModel/controller is introduced. | Pass |
| Stores/services do not import SwiftUI | Auth, storage, session, and journey types use Foundation, Observation, AuthenticationServices, Security, and CryptoKit only. SwiftUI stays in view files. | Pass |
| Test-first and regression safety | Each state-machine, persistence, auth, retry, ownership, and deletion boundary has an XCTest target. New test files must be registered in the manual test target build phase. | Pass |
| UI tests opt-in only | No XCUITest target, UI-test implementation, execution, or future task is added. Accessibility identifiers and DEBUG launch-state hooks keep the flow inspectable. | Pass |
| UX/design-system consistency | New full-screen gates use existing `AppColor`, `AppTypography`, `AppSpacing`, and `AppMotion`; all observable transitions animate through `AppMotion`; all copy ships EN/ES. | Pass |
| Apple surface decision | The access and consent gates use opaque `surfacePrimary` backgrounds. Authentication uses Apple's native `SignInWithAppleButton`; glass/material is not appropriate for these focused privacy gates. | Pass |
| Accessibility | Native controls, Dynamic Type, meaningful localized labels, logical focus order, 44-point targets, Reduce Motion via `AppMotion`, and nontechnical error text are part of the UI contract. | Pass |
| Performance | Protected file I/O and bulk image cleanup stay off the main actor; token refresh is coalesced; SwiftData queries filter by owner instead of loading all accounts. Measurements are included in the quickstart. | Pass |
| Backend environments and dependencies | Every Kalorias URL continues through `BackendEnvironment`; Apple system frameworks add no package; Apple server calls and secrets exist only in the external backend. | Pass |
| Privacy and credentials | Tokens use non-synchronizing `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; sensitive files combine atomic writes with complete file protection; logs carry only safe categories/correlation IDs. | Pass |
| Localization/appearance | Every new string is added to `Localizable.xcstrings` in English and Spanish and verified in light/dark mode and accessibility settings. | Pass |

No constitutional violation requires an exception. The post-design re-check is unchanged: the actor,
storage, navigation, surface, animation, localization, testing, and performance decisions above
remain compliant.

## Project Structure

### Documentation (this feature)

```text
specs/010-apple-auth-onboarding/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── backend-handoff.md
├── contracts/
│   ├── auth-api-v1.md
│   └── ui-contracts.md
├── tasks.md             # generated separately; not an output of this plan run
└── checklists/
    └── requirements.md
```

The existing `tasks.md` was produced by a separate `speckit-tasks`/implementation run; this
`speckit-plan` run does not create or modify it.

### Source Code (repository root)

```text
Kalorias/
├── App/
│   ├── RootView.swift                         # replace boolean/modal gate with root phase switch
│   ├── Router.swift                           # add Progress account route/path
│   ├── AppJourneyPhase.swift                  # exhaustive restored root phases
│   └── AppJourneyStore.swift                  # new durable journey orchestration
├── Authentication/                            # new feature-neutral auth/session boundary
│   ├── AppleAuthorizationCredential.swift
│   ├── AppleCredentialStateService.swift
│   ├── AppleSignInRequestFactory.swift
│   ├── AuthSession.swift
│   ├── AccountDeletionAttempt.swift
│   ├── AuthSessionCoordinator.swift
│   ├── AuthenticatedHTTPClient.swift
│   ├── KeychainCredentialStore.swift
│   └── RemoteAuthService.swift
├── DesignSystem/
│   ├── AppColor.swift                         # reuse existing tokens
│   ├── AppMotion.swift                        # reuse existing motion/transition vocabulary
│   ├── AppSpacing.swift                       # reuse existing scale
│   └── AppTypography.swift                    # reuse existing roles
├── Features/
│   ├── Access/
│   │   ├── AccessView.swift                   # native Apple button
│   │   ├── HealthDataConsentView.swift
│   │   ├── FinalizingOnboardingView.swift
│   │   └── PrivacyNoticeView.swift
│   ├── Account/
│   │   ├── AccountSettingsView.swift
│   │   └── AccountDeletionView.swift
│   ├── Analysis/
│   │   └── RemoteCalorieService.swift         # authenticated client
│   ├── History/
│   │   ├── MealEntry.swift                    # add opaque ownerUserID
│   │   ├── MealHistoryRepository.swift        # owner-aware writes/deletion
│   │   ├── HistoryView.swift                  # owner predicate
│   │   └── ImageStore.swift                   # protected writes/batch deletion
│   ├── Onboarding/
│   │   ├── OnboardingProviding.swift          # split public fetch/authenticated submit
│   │   ├── OnboardingStorage.swift            # draft plus sealed pending payload
│   │   ├── OnboardingStore.swift              # finish locally, never upload
│   │   ├── RemoteOnboardingService.swift      # public questionnaire GET only
│   │   └── RemoteOnboardingSubmissionService.swift # authenticated/idempotent POST
│   └── Progress/
│       └── ProgressTabView.swift               # owner predicate/account destination
├── KaloriasApp.swift                          # compose store/services and restore state
├── Kalorias.entitlements                      # Sign in with Apple capability
├── Resources/Localizable.xcstrings            # EN/ES access, consent, retry, deletion copy
└── Support/
    ├── AuthLog.swift                           # redacted auth/account categories only
    ├── ProtectedFileStore.swift                # atomic complete-protection file I/O
    └── BackendEnvironment.swift                # existing single environment decision point

KaloriasTests/
├── AppJourneyStoreTests.swift
├── AuthFixtures.swift
├── AppleSignInRequestFactoryTests.swift
├── AuthSessionCoordinatorTests.swift
├── AuthenticatedHTTPClientTests.swift
├── KeychainCredentialStoreTests.swift
├── PendingOnboardingStorageTests.swift
├── RemoteAuthServiceTests.swift
├── OnboardingStoreTests.swift                 # update local-completion contract
├── OnboardingSubmissionTests.swift            # add consent envelope/idempotency
├── RemoteCalorieServiceTests.swift             # add auth/one-refresh behavior
├── MealHistoryRepositoryTests.swift            # add cross-account isolation/deletion
├── ImageStoreTests.swift                       # add protected/batch cleanup cases
└── RouterTests.swift                           # add account route and identity reset
```

**Structure Decision**: Keep the existing single iOS application and unit-test targets. Auth is a
top-level technical boundary because it is consumed by root navigation, onboarding, analysis, and
account lifecycle; feature-specific views remain under `Features`. Xcode's filesystem-synchronized
app group discovers new app sources automatically, while every new test source must be added to
the existing `KaloriasTests` group and Sources build phase in `project.pbxproj`.

## Design and Implementation Strategy

### 1. Make completion local and durable

`OnboardingStore` stops invoking the submission service. Its final intent builds an immutable
`PendingOnboarding` from the draft, writes it successfully, and only then reports local completion.
Draft and pending files are separate so the access screen can offer “Review answers.” Sensitive
writes combine `.atomic` and `.completeFileProtection`; questionnaire cache remains non-sensitive.

### 2. Replace presentation flags with a root state machine

`AppJourneyStore` restores Keychain and protected local state and exposes one `AppJourneyPhase`:
`restoring`, `onboarding`, `access`, `consent`, `finalizing`, `ready`, or `deletingAccount`.
`RootView` switches on that
phase rather than presenting onboarding above an already-active app. A known completed account
without a current session returns to access—not onboarding—and an authenticated completed account
wins over any redundant local pending payload.

### 3. Authenticate Apple without coupling it to health data

`AccessView` embeds `SignInWithAppleButton(.continue)`. A request factory creates a cryptographically
random raw nonce and state, sends the SHA-256 nonce to Apple, verifies the returned state locally,
keeps Apple's returned user identifier only for local credential-state checks, and gives the backend
only the raw nonce, identity token, and authorization code. Version 1 requests no Apple name or email
scope. No Apple credential is considered a Kalorias session until `/api/v1/auth/apple` succeeds.

### 4. Centralize session storage and refresh

`AuthSessionCoordinator` is an actor and the sole owner of Keychain token rotation and single-flight
refresh. `AuthenticatedHTTPClient` attaches the access token, refreshes shortly before expiry, and
on a `401` forces one refresh then retries the original request once. A second `401` ends the session;
the client never loops. Logout/revocation clears only the active session, while a small non-secret
Keychain `KnownAccount` record preserves whether a completed user should reauthenticate instead of
restarting onboarding. The confirmed deletion flow owns a separate temporary Keychain attempt record
and clears session, known-account, and deletion-attempt records after `204` and local cleanup.

### 5. Obtain consent and submit once registration commits

For a new or pending account, the app presents a separate localized health-data processing notice.
Accepting it persists a versioned `ConsentReceipt` into the pending envelope before network work.
The first upload begins immediately; after a visible failure, subsequent retries are user-initiated.
The request reuses the onboarding session identifier as its idempotency key. On server success the
app first persists `onboardingStatus=complete` in Keychain, then removes draft/pending files; this
ordering makes a crash recover as complete rather than lose an unconfirmed payload.

### 6. Protect existing authenticated features and local ownership

`RemoteOnboardingSubmissionService` and `RemoteCalorieService` use the authenticated client. The server
must reject missing/invalid Bearer tokens before decoding or doing expensive image/model work.
`MealEntry` gains `ownerUserID: String?`; new writes require the active backend user ID and history,
progress, and repository reads filter at the SwiftData query. Legacy unowned rows remain hidden.
After the user confirms account deletion, an attempt containing the stable operation key and exact
Bearer used is persisted in device-only Keychain and the authenticated shell is replaced by the
deletion gate. After a confirmed/replayed `204`, only that owner's rows and images are removed,
followed by all auth/onboarding/deletion state and a transition to first-run onboarding.

### 7. Handle credential lifecycle without destructive guesses

The app checks Apple credential state at bootstrap/foreground and observes Apple's revocation
notification. Only definitive `.revoked` or `.notFound` invalidates the current session. A transient
lookup error preserves local state; `.transferred` is surfaced as a recoverable account migration
condition for backend support rather than silently deleting data. All paths log safe categories and
correlation identifiers, never credentials or health/profile values.

## Delivery Boundaries

- The iOS implementation owns native Apple authorization, protected local state, session use,
  state restoration, UI, local meal isolation, and local cleanup.
- The backend team owns Apple token/code verification, Apple JWKS caching, Kalorias session issuance
  and rotation, authenticated/idempotent onboarding, authorization of analysis, revocation, and
  server-side deletion. [backend-handoff.md](./backend-handoff.md) is its delivery document.
- Apple Developer capability/App ID enablement, backend production credentials, exact legal consent
  copy approval, privacy-policy publication, and App Store privacy answers are release prerequisites.
  They do not change the technical state machine or API contract.
- Version 1 requires `DELETE /api/v1/account` to complete synchronously and return `204`. An asynchronous
  deletion flow requires a separately versioned status-resource contract before the client can ship it.

## Complexity Tracking

No constitution exceptions or unjustified abstractions are introduced. The root journey store and
session actor exist because their state spans multiple views/features and process launches; they are
not view-specific presentation layers.

## Clarification Gate

No open product or architecture questions remain. The feature specification and this design settle
ordering, persistence, consent, returning-account behavior, retry semantics, credential revocation,
data ownership, and deletion. Exact legal wording is an external approval artifact and must be
provided before release, but it is not an implementation-choice ambiguity.
