# Phase 1 Data Model: Sign in with Apple After Local Onboarding

## Model Boundaries

The feature deliberately uses three persistence technologies for three different trust domains:

| Domain | Persistence | Contents |
|---|---|---|
| Public content | Application Support cache/bundle | Questionnaire definitions only |
| Sensitive in-progress data | Application Support with complete file protection | Draft answers and sealed pending onboarding |
| Credentials and durable identity | Non-synchronizing device-only Keychain | Kalorias session and known-account marker |
| Account-owned history | SwiftData plus protected image files | Meals scoped by backend user ID |

No Apple/Kalorias token or full onboarding payload is stored in preferences. The only source of
truth for whether server onboarding is complete is the last backend-auth/session response persisted
in Keychain; a local draft-completion flag is never used as its substitute.

## Entities

### OnboardingDraft

Mutable local progress written after every accepted answer.

| Field | Type | Rules |
|---|---|---|
| `schemaVersion` | `Int` | Local envelope migration version; starts at `1` |
| `sessionId` | `UUID` | Generated once when onboarding begins; never regenerated on resume |
| `contentVersion` | `String` | Pins answers to the questionnaire definition used |
| `locale` | `String` | Supported normalized locale (`en` or `es`) |
| `startedAt` | `Date` | Set once using UTC absolute time |
| `updatedAt` | `Date` | Updated after a durable answer/change |
| `answers` | `[String: OnboardingAnswer]` | Keyed by known question ID; retains valid shadowed conditional answers needed to resume/edit |

**Validation/invariants**:

- `sessionId`, `contentVersion`, and `startedAt` are immutable after creation.
- An answer can only reference a question in the pinned questionnaire.
- Answers hidden by a later branch choice stay in the draft for reversible navigation but are
  omitted from the sealed submission unless visible in the final evaluated flow.
- The next question is shown only after the modified draft write succeeds.
- A schema/content mismatch is handled explicitly; it never silently sends partially reinterpreted
  answers.
- This file remains available while the user is on Access so “Review answers” can reconstruct the
  questionnaire.

### PendingOnboarding

Immutable submission snapshot plus a separately added consent receipt.

| Field | Type | Rules |
|---|---|---|
| `schemaVersion` | `Int` | Local envelope migration version; starts at `1` |
| `submission` | `OnboardingSubmission` | Complete, validated payload sealed from the draft |
| `consent` | `ConsentReceipt?` | `nil` until an authenticated user accepts the separate notice |

**Validation/invariants**:

- It is written atomically before transitioning from Onboarding to Access.
- `submission.sessionId` equals the draft session ID and API idempotency key.
- The submission is not edited after sealing. Returning to review creates and seals a replacement
  snapshot with the same session identity; it does not patch an upload in flight.
- `consent == nil` means no onboarding upload is permitted.
- The file is removed only after complete server status has first been durably persisted, or when an
  already-complete returning account makes it provably redundant.

### OnboardingSubmission

Existing wire-domain value expanded only where needed for authentication/consent integration.

| Field | Type | Rules |
|---|---|---|
| `sessionId` | `UUID` | Stable idempotency identity |
| `contentVersion` | `String` | Questionnaire contract version |
| `locale` | `String` | `en` or `es` |
| `startedAt` | `Date` | Original local start time |
| `completedAt` | `Date` | Time final required answer was durably sealed |
| `answers` | `[SubmittedAnswer]` | Complete validated answers in canonical question order |

The HTTP request combines this value with `ConsentReceipt`; consent is not inserted into individual
answers and never appears in the Apple-auth request.

### ConsentReceipt

| Field | Type | Rules |
|---|---|---|
| `privacyNoticeVersion` | `String` | Compiled/approved published notice version |
| `healthDataConsentVersion` | `String` | Compiled/approved affirmative-consent version |
| `grantedAt` | `Date` | Device time captured at the affirmative action |

**Validation/invariants**:

- Created only from the explicit “Accept and create plan” intent.
- Persisted into `PendingOnboarding` before the first upload attempt.
- Apple success, merely opening the notice, or choosing “Not now” cannot create a receipt.
- Backend stores its receipt time as well; server receipt does not trust device time as an audit
  authority, but retains it as client context.

### AppleSignInAttempt

Ephemeral, memory-only value for one native authorization sheet.

| Field | Type | Rules |
|---|---|---|
| `rawNonce` | `String` | Base64url secure random value; sent only to Kalorias backend |
| `hashedNonce` | `String` | Lowercase SHA-256 sent in Apple's request |
| `state` | `String` | Independent secure random callback correlation value |

The attempt is cleared on callback, cancellation, error, or a new attempt. A callback whose `state`
does not exactly match is rejected locally and never reaches the backend.

### AppleAuthorizationCredential

Short-lived `Sendable` transport value mapped from `ASAuthorizationAppleIDCredential`.

| Field | Type | Rules |
|---|---|---|
| `identityToken` | `String` | Required, non-empty UTF-8 JWS from credential data |
| `authorizationCode` | `String` | Required, non-empty UTF-8 one-time code |
| `appleUserIdentifier` | `String` | Required stable provider subject for credential-state checks |
| `rawNonce` | `String` | Required value from matching active attempt |

It is never persisted or logged. Mapping fails closed for missing data, invalid UTF-8, empty values,
wrong authorization type, or state mismatch.

### AuthSession

Credential record encoded into one Keychain item and replaced as a unit.

| Field | Type | Rules |
|---|---|---|
| `schemaVersion` | `Int` | Keychain payload migration version; starts at `1` |
| `userId` | `String` | Opaque authoritative Kalorias user identifier |
| `appleUserIdentifier` | `String` | Used only for Apple credential-state lifecycle |
| `accessToken` | `String` | Opaque short-lived Bearer token |
| `accessTokenExpiresAt` | `Date` | Server-provided absolute expiry |
| `refreshToken` | `String` | Opaque rotating credential |
| `refreshTokenExpiresAt` | `Date` | Server-provided absolute expiry |
| `onboardingStatus` | `OnboardingServerStatus` | `required` or `complete` |

**Validation/invariants**:

- Empty IDs/tokens or expiry ordering inconsistent with the response invalidate the response.
- A refresh response atomically replaces both tokens and expiries.
- Access token use and refresh-token rotation are serialized by `AuthSessionCoordinator`.
- Only successful backend authentication/refresh/onboarding responses mutate this record.
- Definitive revocation, unrefreshable auth failure, logout, or deletion removes the active session.

### KnownAccount

Small Keychain record that survives ordinary session loss and prevents a completed user from being
treated as a brand-new first run.

| Field | Type | Rules |
|---|---|---|
| `schemaVersion` | `Int` | Starts at `1` |
| `userId` | `String` | Last authoritative backend account on this installation |
| `appleUserIdentifier` | `String` | Optional only for compatibility/migration; populated after Apple auth |
| `onboardingStatus` | `OnboardingServerStatus` | Last committed server status |

It contains no token. It is updated alongside successful session/status commits, retained after
revocation/session expiry, and removed only after confirmed account deletion or an explicit full
local reset belonging to that account.

### AccountDeletionAttempt

Device-only Keychain record created only after the user confirms the destructive action and before
the first deletion request.

| Field | Type | Rules |
|---|---|---|
| `schemaVersion` | `Int` | Starts at `1` |
| `operationId` | `UUID` | Stable `Idempotency-Key` for every retry |
| `presentedAccessToken` | `String` | Exact Bearer used by the first request; credential, never logged |
| `ownerUserID` | `String` | Captured backend owner for scoped local cleanup |
| `confirmedAt` | `Date` | Time of explicit destructive user confirmation |

The exact Bearer is retained because ordinary session refresh may be impossible after successful
server deletion, while the backend tombstone authenticates an exact route-specific replay using its
HMAC. The record has the same non-synchronizing, device-only accessibility as `AuthSession`. On
bootstrap it takes precedence over `ready` and renders a deletion-recovery gate. It is removed only
after `204` and local cleanup complete; a non-`204` error keeps it for manual retry/support.

### MealEntry (SwiftData change)

Existing model plus one ownership field:

| New field | Type | Rules |
|---|---|---|
| `ownerUserID` | `String?` | Opaque backend ID; required for every new authenticated insert |

**Migration and privacy rules**:

- Optionality permits a lightweight inferred migration of the current store.
- `nil` legacy rows are not assigned to the first account automatically and stay hidden.
- History and Progress apply `ownerUserID == activeUserID` in the SwiftData fetch predicate.
- Detail navigation verifies/derives its entry from an already owner-filtered result.
- Repository mutation rejects writes without an active user and deletion outside that user.
- Confirmed account deletion removes matching rows, then their named images. It does not delete rows
  owned by a different ID.

## Enums and State Values

### OnboardingServerStatus

```text
required
complete
```

Unknown wire values fail decoding rather than treating the user as complete.

### AppJourneyPhase

```text
restoring
onboarding
access
consent
finalizing
ready
deletingAccount
```

Associated state belongs to the reusable store, not the view:

- `restoring`: bootstrap in progress or protected data temporarily unavailable until unlock.
- `onboarding`: an `OnboardingStore` exists with new/resumed local draft.
- `access`: Apple action availability, pending/review capability, auth error, in-flight flag.
- `consent`: authenticated required account and pending payload without receipt.
- `finalizing`: first upload progress, recoverable failure, retry availability.
- `ready`: authenticated account whose server onboarding status is complete.
- `deletingAccount`: a user-confirmed persisted deletion attempt is running or awaits manual retry;
  authenticated content is not visible.

Account Settings captures the confirmation and persists `AccountDeletionAttempt` before switching to
the root deletion phase. This ensures termination cannot restore authenticated content while a server
deletion may already have committed.

### AppleCredentialState

```text
authorized
revoked
notFound
transferred
temporarilyUnavailable(errorCategory)
```

The local wrapper distinguishes a lookup failure from provider `.notFound`; only the provider's
definitive revoked/not-found values clear the active session.

## Bootstrap Resolution Table

Resolution is deterministic and evaluated before the authenticated app shell is built.

| Deletion attempt | Session | Known account | Pending payload | Consent | Resolution |
|---|---|---|---|---|---|
| present | any | any | any | any | `deletingAccount`; never show authenticated content or auto-create an account |
| absent | complete | any | any | any | `ready`; discard redundant draft/pending after status commit is known durable |
| absent | required | any | present | absent | `consent` |
| absent | required | any | present | present | `finalizing` in recoverable/manual-retry mode after relaunch |
| absent | required | any | absent | n/a | `onboarding`; rebuild a local submission for the existing account |
| absent | absent | complete | any | any | `access`; never restart first-run onboarding |
| absent | absent | required | present | any | `access`; preserve payload/receipt |
| absent | absent | required | absent | n/a | `access`, then resume onboarding after backend reauthentication confirms status |
| absent | absent | absent | present | any | `access` |
| absent | absent | absent | absent | n/a | `onboarding` |

Additional resolution rules:

- A protected file being unavailable while the device is locked keeps `restoring`; it is not treated
  as “missing.”
- A corrupted protected payload surfaces a recoverable local-data error; it is never silently sent
  or deleted.
- On bootstrap, a consented pending payload does not upload silently. The finalization screen asks
  for retry because a previous process may have already shown an error or terminated mid-request.
- After fresh consent in the current process, the first upload is automatic.

## State Transitions

| From | Event | Durable write before transition | To |
|---|---|---|---|
| `onboarding` | Answer accepted | Updated protected draft | `onboarding` next question |
| `onboarding` | Final answer accepted | Protected pending snapshot | `access` |
| `access` | Review answers | None | `onboarding` with same session identity |
| `access` | Apple cancelled/failed | None | `access` with localized result |
| `access` | Backend auth says complete | Session + known account complete | `ready`, then remove redundant pending |
| `access` | Backend auth says required, no pending | Session + known account required | `onboarding` |
| `access` | Backend auth says required, pending exists | Session + known account required | `consent` or `finalizing` depending on receipt |
| `consent` | Not now | None | `consent` idle |
| `consent` | Accept | Pending with consent receipt | `finalizing`, automatic first attempt |
| `finalizing` | Upload fails | None; preserve session/pending | `finalizing` failed, manual retry |
| `finalizing` | Session becomes unrefreshable | Remove active session only | `access` |
| `finalizing` | Server confirms complete | Session + known account complete | `ready`, then remove pending/draft |
| `ready` | Apple definitively revoked/not found | Remove active session only | `access` |
| `ready` | User confirms account deletion | Persist deletion attempt with exact bearer/key | `deletingAccount` |
| `deletingAccount` | Request/replay fails | None; preserve deletion attempt and all data | `deletingAccount` failed, manual retry |
| `deletingAccount` | Account deletion returns `204` | Remove owner meals/images, session, known account, attempt, local onboarding | `onboarding` |

Every observable transition is initiated by a store intent and animated at the view/root boundary
with an existing `AppMotion` animation/transition pair.

## Persistence Commit Ordering

### Local onboarding completion

```text
validate complete answers
→ encode immutable submission
→ atomic + complete-protection write of PendingOnboarding
→ publish access phase
```

### Backend registration

```text
validate auth response
→ atomic Keychain AuthSession write
→ atomic Keychain KnownAccount write
→ publish server-derived phase
```

If one of the paired Keychain writes fails, do not upload onboarding. Reconciliation may recreate
`KnownAccount` from a valid `AuthSession` on next bootstrap.

### Onboarding success

```text
validate response/session user identity and complete status
→ persist AuthSession(onboardingStatus: complete)
→ persist KnownAccount(onboardingStatus: complete)
→ publish ready phase
→ delete PendingOnboarding and draft
```

Deletion cleanup is safe to retry. A crash before cleanup leaves a redundant payload that bootstrap
discards because durable server status is already complete.

### Account deletion

```text
persist AccountDeletionAttempt with exact bearer + stable operation key
→ publish deletingAccount gate
→ DELETE /api/v1/account using those exact values
→ receive 204
→ dismiss camera and clear navigation paths
→ capture current owner's image names
→ delete only current owner's SwiftData rows and save
→ delete captured files off main actor
→ clear protected onboarding files
→ delete AuthSession, KnownAccount, and AccountDeletionAttempt Keychain items
→ create fresh journey and publish onboarding
```

Cleanup functions are idempotent so a terminated local cleanup resumes safely. Server failure leaves
all local data/session intact and exposes retry. The app retains the exact operation key and presented
access credential in `AccountDeletionAttempt` until it receives `204`; the backend's bounded tombstone can therefore
return the completed result even after the account/session rows have already been removed.

## Service Relationships

```text
AccessView / ConsentView / FinalizingView / RootView
                         │ intents/state
                         ▼
                  AppJourneyStore (@MainActor)
          ┌──────────────┼─────────────────┐
          ▼              ▼                 ▼
 OnboardingStorage  RemoteAuthService  AppleCredentialStateService
          │              │
          │              ▼
          │      AuthSessionCoordinator (actor)
          │              │ access/refresh
          │              ▼
          └────── AuthenticatedHTTPClient ──────┐
                                                ▼
                                onboarding / analysis / account API

ready phase ── active user ID ──► MealHistoryRepository / filtered @Query
```

`Router` is intentionally outside this business-state graph: it owns `progressPath` and the account
destination, while identity changes ask it to clear navigation/camera presentation safely.
