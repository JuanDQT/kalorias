# Phase 0 Research: Sign in with Apple After Local Onboarding

**Date**: 2026-09-08

**Scope**: Native iOS authentication, local protection, session lifecycle, root restoration, and
the boundary with the external Kalorias backend.

## Decision 1: Use the native SwiftUI Sign in with Apple control

**Decision**: Render `SignInWithAppleButton(.continue)` and provide its `onRequest` and
`onCompletion` closures. Enable the Sign in with Apple capability in the app target and App ID.
Version 1 requests no `.fullName` or `.email` scope because Kalorias does not need either value for
the described experience.

**Rationale**: Apple's native control carries the expected branding, accessibility, sizing, and
authorization presentation. Avoiding unnecessary scopes reduces data collection and avoids a false
assumption that name/email will be returned on every login. Apple documents the native button and
the Xcode capability setup in [Displaying Sign in with Apple buttons in your app](https://developer.apple.com/documentation/signinwithapple/displaying-sign-in-with-apple-buttons-in-your-app)
and [Configuring Sign in with Apple](https://developer.apple.com/documentation/xcode/configuring-sign-in-with-apple).

**Alternatives considered**:

- A custom Apple-branded button: rejected because it duplicates system behavior and introduces
  branding/accessibility compliance risk.
- OAuth in an in-app web view: rejected because AuthenticationServices is the native app flow.
- Request name/email pre-emptively: rejected because neither is required for V1 functionality.

## Decision 2: Bind each authorization attempt with both nonce and state

**Decision**: For every button attempt, generate 32 cryptographically secure random bytes as a raw
nonce plus a separate random `state`. Base64url-encode the raw nonce, set `request.nonce` to its
SHA-256 digest, and retain the raw value only in memory for the active attempt. Compare the returned
credential state to the expected state before calling Kalorias; send the raw nonce to the backend so
it can validate the nonce claim in Apple's identity token.

**Rationale**: Nonce binds the Apple token to the client attempt and prevents replay; state binds the
callback to the initiating flow. `ASAuthorizationOpenIDRequest` exposes the nonce and
`ASAuthorizationAppleIDCredential` exposes state, identity token, authorization code, and stable
Apple user identifier. See Apple's [nonce property](https://developer.apple.com/documentation/authenticationservices/asauthorizationopenidrequest/nonce)
and [Apple ID credential](https://developer.apple.com/documentation/authenticationservices/asauthorizationappleidcredential).

**Alternatives considered**:

- Nonce only: rejected because state independently protects callback correlation.
- State only: rejected because it does not let the backend verify token replay binding.
- Persist the raw nonce: rejected; it is short-lived attempt state and must not survive or be reused.

## Decision 3: Treat Apple authorization and Kalorias registration as separate commits

**Decision**: Convert the Apple callback into a strict UTF-8 credential value containing
`identityToken`, `authorizationCode`, `appleUserIdentifier`, and `rawNonce`, then call
`POST /api/v1/auth/apple`. Do not store a Kalorias session, ask for health-data consent, or send answers
until the backend verifies Apple and commits the account. The HTTP body contains only identity token,
authorization code, and raw nonce; the Apple user identifier remains local for provider-state checks.
Do not send onboarding data in this call.

**Rationale**: Apple credentials establish an identity assertion; only the Kalorias backend can
validate the token against Apple, map it to an internal user, rotate server-side tokens, and return
the authoritative onboarding status. Apple describes server-side credential verification in
[Verifying a user](https://developer.apple.com/documentation/signinwithapple/verifying-a-user).

**Alternatives considered**:

- Trust identity-token fields decoded by the app: rejected; client parsing is not server trust.
- Create a local-only account before backend response: rejected because a network failure would
  leave ambiguous registration state.
- Bundle auth and onboarding in one request: rejected because it violates the required privacy and
  consent boundary.

## Decision 4: Store Kalorias sessions in a non-synchronizing, device-only Keychain class

**Decision**: Store encoded `AuthSession`, `KnownAccount`, and user-confirmed
`AccountDeletionAttempt` records as generic-password Keychain items using a bundle-qualified service,
distinct account keys,
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, and `kSecAttrSynchronizable=false`. Tokens never
enter `UserDefaults`, SwiftData, files, analytics, or logs.

**Rationale**: This accessibility class makes values available only after device unlock and prevents
migration to a different device. `WhenPasscodeSetThisDeviceOnly` is stronger but would make the app
incompatible with devices that have no passcode configured; the selected class is the strongest
practical baseline for a foreground-only session. Apple defines these accessibility and migration
semantics in [Keychain item attribute keys and values](https://developer.apple.com/documentation/security/item-attribute-keys-and-values).

**Alternatives considered**:

- `UserDefaults`: rejected because it is preference storage, not credential storage.
- `kSecAttrAccessibleAfterFirstUnlock`: rejected because background availability is not required.
- iCloud-synchronizing Keychain: rejected because sessions and owner bindings are device-local.
- Passcode-required Keychain: rejected for V1 compatibility; it can be revisited if a product-level
  device-passcode requirement is adopted.

## Decision 5: Protect sensitive onboarding files atomically while the device is locked

**Decision**: Keep questionnaire cache as ordinary non-sensitive cached JSON. Write `OnboardingDraft`
and `PendingOnboarding` under Application Support using both `.atomic` and
`.completeFileProtection`, excluding them from backup where appropriate. Propagate write failures;
never advance the visible state before persistence succeeds.

**Rationale**: Onboarding contains health/profile answers and free text. Atomic replacement prevents
partial JSON after interruption, while complete file protection makes the contents unavailable when
the device is locked. Apple documents the option in
[Data.WritingOptions.completeFileProtection](https://developer.apple.com/documentation/foundation/nsdata/writingoptions/completefileprotection).

**Alternatives considered**:

- Store the payload in `UserDefaults`: rejected because it is sensitive structured data.
- Encrypt with an app-bundled symmetric key: rejected because a bundled secret adds complexity
  without improving over platform data protection.
- Put the entire payload in Keychain: rejected because Keychain is for small credentials, not a
  mutable questionnaire document.

## Decision 6: Model the app journey as restored durable state, not a completion Boolean

**Decision**: Replace `@AppStorage("onboarding.completed")` and the full-screen cover with an
`AppJourneyStore` and exhaustive `AppJourneyPhase`. Bootstrap resolves Keychain session,
`KnownAccount`, pending consent/submission, and server onboarding status before rendering one root
gate. If an authenticated account is already complete, it wins and any redundant pending payload is
removed. A known completed account with no session returns to access instead of first-run onboarding.

**Rationale**: The flow now has independently durable boundaries: answered locally, registered,
consented, synchronized, and session-expired. One Boolean cannot distinguish or recover those states.
A root phase switch also prevents the authenticated app shell from running invisibly behind a modal.

**Alternatives considered**:

- Add more `@AppStorage` flags: rejected because independent flags permit contradictory states and
  would place sensitive lifecycle decisions in preferences.
- Keep chained full-screen covers: rejected because restoration and identity replacement would be
  presentation side effects instead of an explicit state machine.
- Put journey state in `Router`: rejected because Router owns navigation paths, not feature/business
  state under the project's MVS architecture.

## Decision 7: Use a single-flight actor for session refresh and retry only once

**Decision**: `AuthSessionCoordinator` owns session reads/writes and coalesces concurrent refreshes.
`AuthenticatedHTTPClient` refreshes shortly before expiry; on an unexpected `401`, it performs one
forced refresh and replays the request once. Refresh rotation is written atomically to Keychain. If
refresh fails definitively or the replay is also unauthorized, clear the active session and require
Apple access while preserving pending answers.

**Rationale**: Analysis and onboarding can overlap with lifecycle checks. Actor isolation prevents
two requests from spending the same rotating refresh token and gives every authenticated service
one consistent policy. A single replay handles clock drift/server invalidation without creating an
infinite authentication loop.

**Alternatives considered**:

- Refresh independently inside each service: rejected because concurrent rotation races can log the
  user out and duplicate security logic.
- Retry every `401` indefinitely: rejected because it hides authorization failures and loops.
- Use only long-lived access tokens: rejected because short access lifetime plus rotated refresh
  credentials limits exposure.

## Decision 8: Separate health-data consent from Apple consent

**Decision**: After `/auth/apple` confirms an account whose onboarding is required, show a dedicated
full-screen consent gate. Persist a receipt containing privacy-notice version,
health-data-consent version, and acceptance time into the protected pending envelope before upload.
Apple button success never implies this consent. “Not now” keeps the session and payload but sends
nothing.

**Rationale**: Apple authorization allows account access; it does not authorize Kalorias to process
weight, pregnancy/health conditions, dates, or free text. A distinct affirmative action gives the
backend an auditable versioned receipt and preserves the user's ability to decline without losing
their work.

**Alternatives considered**:

- Add consent copy under the Apple button: rejected because continuing with Apple would conflate two
  different purposes.
- Upload immediately after auth and ask afterward: rejected because processing would precede consent.
- Store consent only on the server: rejected because the client must durably know that the user
  accepted before a retry following termination.

## Decision 9: Use one stable onboarding idempotency identity and commit client state in safe order

**Decision**: Reuse the locally generated onboarding `sessionId` as the request idempotency key and
body identity for every retry. After a successful response, persist `onboardingStatus=complete` in
Keychain first and delete draft/pending files second. On relaunch, completed server/session state
causes any leftover payload to be discarded.

**Rationale**: The client cannot distinguish a timeout before commit from a lost response after
commit. Stable idempotency lets the backend return the original result. Recording the positive
completion before deleting source data means a crash can leave a harmless duplicate local file, but
cannot leave neither proof nor payload.

**Alternatives considered**:

- Generate a new key on each retry: rejected because it can create duplicate plans.
- Clear pending data when a request begins: rejected because a failure would lose answers.
- Delete pending first after success: rejected because termination between operations would recreate
  an ambiguous state.

## Decision 10: Check Apple credential state, but invalidate only on definitive outcomes

**Decision**: Store the stable Apple user identifier with the account/session. At launch/foreground,
call `getCredentialState(forUserID:)` and observe Apple credential-revocation notifications. Treat
`.revoked` and `.notFound` as definitive session-invalidating results; preserve state after transport
or service errors. Treat `.transferred` as a gated migration/support state until the backend has an
explicit transfer path.

**Rationale**: Apple recommends retaining the user identifier securely and checking credential
state. The provider exposes authorized, revoked, not-found, and transferred results. See
[Implementing user authentication with Sign in with Apple](https://developer.apple.com/documentation/authenticationservices/implementing-user-authentication-with-sign-in-with-apple),
[getCredentialState](https://developer.apple.com/documentation/authenticationservices/asauthorizationappleidprovider/getcredentialstate%28foruserid%3Acompletion%3A%29),
and [ASAuthorizationAppleIDProvider](https://developer.apple.com/documentation/authenticationservices/asauthorizationappleidprovider).

**Alternatives considered**:

- Clear session on any check error: rejected because a transient Apple/network issue is not evidence
  of revocation.
- Never check after login: rejected because a revoked Apple relationship could retain app access.
- Automatically erase data for `.transferred`: rejected because account-transfer handling requires
  server identity migration, not destructive client inference.

## Decision 11: Scope every local meal by the authenticated backend user

**Decision**: Add optional `ownerUserID: String?` to `MealEntry`, treating backend identifiers as
opaque strings. Every new insert requires the active user ID; History and Progress filter in their
SwiftData query; repository operations verify the same owner. Existing unowned rows are hidden. On
confirmed account deletion, delete only the current owner's rows and associated images.

**Rationale**: Keychain can outlive logout and different Apple identities can use one installation.
Without ownership, the second account can see the first account's local health history. An optional
field permits an inferred lightweight SwiftData migration; filtering—not assigning legacy rows to a
new identity—is the safe privacy default. Apple exposes SwiftData schema concepts in
[Schema](https://developer.apple.com/documentation/swiftdata/schema).

**Alternatives considered**:

- Delete all meals on logout: rejected because reauthentication should not erase local history.
- Associate existing unowned rows with the first user who logs in: rejected because ownership cannot
  be proven.
- Use the Apple user identifier as owner: rejected because internal resources should bind to the
  backend's authoritative user ID and remain decoupled from identity-provider details.

## Decision 12: Make account deletion synchronous in the V1 client contract

**Decision**: The shipped client requires authenticated `DELETE /api/v1/account` to finish revocation,
server deletion, and invalidation and then return `204 No Content`. Only after `204` does the app
delete current-owner local data and credentials. The server retains a short-lived, non-PII deletion
tombstone keyed by HMACs of the operation key and presented access credential so an exact replay can
return `204` after sessions are invalidated if the first response was lost. Before the first request,
iOS persists those exact replay values as a device-only Keychain `AccountDeletionAttempt` and gates
the app shell until the attempt resolves. A future asynchronous
backend must first add a versioned deletion-status resource; `202` alone is insufficient for safe
local finalization.

**Rationale**: Apple requires apps supporting account creation to offer in-app account deletion, and
Sign in with Apple accounts must have tokens revoked. A synchronous V1 boundary gives the client an
unambiguous point after which destructive local cleanup is correct. See Apple's
[Offering account deletion in your app](https://developer.apple.com/support/offering-account-deletion-in-your-app/),
[TN3194](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple),
and [Revoke tokens](https://developer.apple.com/documentation/signinwithapplerestapi/revoke-tokens).

**Alternatives considered**:

- Treat `202 Accepted` as deletion complete: rejected because server revocation/deletion could still
  fail after the app destroys its only authenticated session.
- Delete local data before the server response: rejected because the request could fail.
- Keep all local data after server confirmation: rejected because it violates the account lifecycle
  acceptance criteria.
- Keep the attempt only in memory: rejected because process termination can occur after server
  deletion but before the `204` is received.

## Decision 13: Use opaque system surfaces and the existing motion vocabulary

**Decision**: Access, consent, finalization, and privacy screens use an opaque
`AppColor.surfacePrimary` canvas and existing typography/spacing tokens. The Apple control is native;
secondary actions are ordinary system buttons. State transitions use existing `AppMotion` values and
their reduced-motion substitutions. No glass, blur, decorative animation, or custom haptic is added.

**Rationale**: These screens are focused privacy/security gates, not layered contextual surfaces.
Opaque presentation gives clear hierarchy and predictable contrast in both appearances. Native
controls already provide immediate press feedback; additional haptics would not add semantic value.

**Alternatives considered**:

- Liquid Glass or material cards: rejected because there is no content layer that needs spatial
  separation and translucency would weaken the focused gate.
- Custom springs/haptics: rejected because the existing system vocabulary already communicates state
  changes consistently and respects Reduce Motion.

## Resolved Unknowns

No technical unknown remains for planning. Production Team ID, Services/App ID values, Apple private
key, backend signing keys, exact consent/legal copy, and privacy-policy URL are environment/release
inputs. They must be supplied through Apple Developer/backend secret management or approved content;
none belongs in the repository or changes the selected architecture.
