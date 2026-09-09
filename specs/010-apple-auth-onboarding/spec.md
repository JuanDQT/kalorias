# Feature Specification: Sign in with Apple After Local Onboarding

**Feature Branch**: `010-apple-auth-onboarding`

**Created**: 2026-09-08

**Status**: Draft

**Input**: User description: "El acceso tiene que estar después del onboarding. Las respuestas se
guardan en local y solo se envían cuando el usuario se ha registrado con Sign in with Apple."

**Backend handoff**: [`backend-handoff.md`](./backend-handoff.md) is the self-contained document
to give to the backend team. It defines the authentication/session endpoints, Apple-token
verification, authenticated onboarding submission, revocation and account deletion.

## Context

Today the onboarding submits its answers directly from the final chat action, and it only marks
the onboarding complete after the server accepts them. There is no account or session layer, and
both onboarding submission and meal analysis are explicitly unauthenticated.

This feature changes that order. The user answers the whole onboarding **before** seeing any
account screen. Their answers are written only to protected local storage while they progress.
Finishing the questions seals a pending submission; it does not upload it. The app then presents
Sign in with Apple. Only after the backend has verified Apple and committed the user account may
the app transmit the pending onboarding answers.

The authoritative first-run sequence is:

```text
public questionnaire fetch
        ↓
onboarding answers (local only, saved after every answer)
        ↓
completed pending submission (local only)
        ↓
Sign in with Apple
        ↓
backend creates or restores the account and returns a Kalorias session
        ↓
separate consent to process health data
        ↓
authenticated onboarding submission
        ↓
server confirms the plan/onboarding is complete
        ↓
main app
```

The boundaries in that sequence are deliberate:

- Fetching questionnaire content before registration is allowed; it contains no user data.
- No answer, health value, free text or onboarding payload travels in the Apple-auth request.
- “Finished answering”, “registered” and “synchronized” are three different durable states.
- The main app does not open for a new account until the authenticated onboarding submission is
  confirmed, because the first plan is not usable before then.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Complete onboarding without creating an account first (Priority: P1)

As a new user, I want to answer the onboarding before being asked to register, so I understand
the value and context of Kalorias before committing to an account.

Every accepted answer is saved locally. The app makes no request containing answers while the
user is still answering, even if a network connection is available. When the final answer is
accepted, the app atomically saves a complete pending submission and then shows the access
screen.

**Why this priority**: This is the product decision that governs the feature. If registration
appears first, or answers leak to the server while the chat is in progress, the requested flow
has not been implemented.

**Independent Test**: Complete the full onboarding while inspecting network traffic, terminate
and relaunch midway once, and confirm that all answers resume locally and that no request body
contains onboarding answers before registration succeeds.

**Acceptance Scenarios**:

1. **Given** a first launch, **When** the onboarding starts, **Then** the user sees the first
   onboarding question and no account or Apple access screen.
2. **Given** a user answers a question, **When** that answer is accepted, **Then** it is saved
   locally before the next question is presented.
3. **Given** a partially completed onboarding, **When** the app is terminated and relaunched,
   **Then** the same questionnaire version, session identifier and valid answers resume at the
   correct question.
4. **Given** the user is answering the onboarding, **When** any number of answers are accepted,
   **Then** no request transmits those answers or derived health/profile data.
5. **Given** the last required answer is accepted, **When** the flow advances, **Then** a complete
   pending submission including its original start time and local completion time is saved
   atomically before the access screen appears.
6. **Given** the device is offline, **When** a bundled or cached questionnaire is available,
   **Then** the user can complete the onboarding and reach the access screen with all answers
   intact.

---

### User Story 2 - Register with Apple, then send the saved answers (Priority: P1)

As someone who has completed onboarding, I want to create my account with Apple and have my
saved answers submitted once the account exists, so the resulting plan belongs to a verified
account and I never need to type the answers again.

The Apple flow and the onboarding submission are two separate server operations. First the
backend verifies Apple, commits or restores the account, and returns a Kalorias session. Only
then does the app ask for the separate health-data consent and submit the already-sealed local
payload with that session. A failure in the second operation must never send the user through
Apple again while the Kalorias session remains valid.

**Why this priority**: This is the minimum complete registration journey and the privacy boundary
the feature exists to enforce.

**Independent Test**: Complete onboarding, register with Apple against a test backend, and verify
from server logs that account creation commits before the first authenticated onboarding request,
that the Apple-auth request contains no answers, and that the confirmed onboarding opens the app.

**Acceptance Scenarios**:

1. **Given** a complete pending onboarding and no Kalorias session, **When** the access screen is
   shown, **Then** it offers the native Sign in with Apple action and never asks for a password.
2. **Given** Apple authorization succeeds, **When** the app calls the Kalorias authentication
   endpoint, **Then** it sends only Apple credentials and the one-time anti-replay value; it does
   not send onboarding answers.
3. **Given** the backend verifies Apple and commits a new account, **When** it returns a Kalorias
   session, **Then** the app stores the session securely and treats the user as registered.
4. **Given** a registered account with onboarding still required, **When** the user separately
   accepts the health-data processing notice, **Then** the app submits the locally saved payload
   with the Kalorias session and the original onboarding session identifier.
5. **Given** the backend confirms the onboarding submission, **When** the response arrives,
   **Then** the app clears the local pending answers, records the onboarding as complete, and
   opens the main app.
6. **Given** the Apple identity already maps to a Kalorias account whose onboarding is complete,
   **When** authentication succeeds, **Then** the app does not overwrite that account with the
   newly completed local answers; it discards the redundant pending submission and opens the app.
7. **Given** the Apple identity already maps to a Kalorias account whose onboarding is pending,
   **When** authentication succeeds, **Then** the app submits the local pending onboarding exactly
   as it would for a new account.
8. **Given** registration succeeds but onboarding submission fails, **When** the failure is shown,
   **Then** the account remains registered, the answers remain local, and retrying the submission
   does not invoke Apple again.

---

### User Story 3 - Recover safely from cancellation, interruption and network failure (Priority: P2)

As a user who has already spent time answering the onboarding, I want every interruption after
the last answer to be recoverable, so cancellation, app termination or a server outage cannot
erase my work or create duplicate accounts/plans.

**Why this priority**: Apple authorization and two backend operations create several interruption
points. Without explicit durable states, the most likely failure mode is either lost health data
or duplicate plan creation after a timeout.

**Independent Test**: Terminate the app at each boundary—before Apple, after Apple but before the
auth response, after registration, during submission, and after server acceptance but before the
client processes the response—and verify that relaunch resumes at the correct boundary without
duplicate records.

**Acceptance Scenarios**:

1. **Given** the Apple sheet is visible, **When** the user cancels it, **Then** the app remains on
   the access screen and preserves every pending answer.
2. **Given** Apple or the Kalorias auth service is unavailable, **When** registration fails,
   **Then** the app shows a localized retry action and transmits no onboarding payload.
3. **Given** registration completed previously and its secure session remains valid, **When** the
   app relaunches with a pending submission, **Then** it resumes at the consent/finalization state
   rather than showing Apple again.
4. **Given** an onboarding upload times out after the server may have accepted it, **When** the
   user retries, **Then** the same onboarding session identifier and idempotency key are reused and
   the server returns the original result instead of creating a second plan.
5. **Given** onboarding upload failed, **When** the app is terminated and relaunched, **Then** the
   pending payload remains available and no retry occurs until the user requests it.
6. **Given** the access token expires before submission, **When** the app still has a valid refresh
   session, **Then** it renews the Kalorias session once and retries the same idempotent submission.
7. **Given** the session cannot be renewed, **When** the user retries finalization, **Then** the app
   returns to Apple access while preserving the pending answers.
8. **Given** the backend confirms that the account already has a completed onboarding after an
   ambiguous client timeout, **When** the app authenticates again, **Then** it clears the pending
   duplicate and enters the app without resubmitting it.

---

### User Story 4 - Keep the account and local data private throughout its lifecycle (Priority: P3)

As a registered user, I want my session and health information protected, and I want to be able
to delete my account, so registration does not leave credentials or personal data outside my
control.

**Why this priority**: The onboarding includes dates, weight, pregnancy/health conditions and
free text. Account lifecycle is therefore part of the feature, not optional polish.

**Independent Test**: Inspect persisted values and logs, revoke the app from Apple, and delete a
test account. Confirm that tokens are only in protected credential storage, onboarding payloads
never appear in logs, revocation gates access, and account deletion removes server and local data.

**Acceptance Scenarios**:

1. **Given** a Kalorias session, **When** the app persists it, **Then** tokens are kept in protected
   credential storage and never in preferences, plain files or logs.
2. **Given** pending onboarding answers, **When** they are written locally, **Then** the file uses
   the strongest practical iOS data protection compatible with background-free foreground use.
3. **Given** the app receives a definitive Apple credential-revoked or credential-not-found
   state, **When** that state is processed, **Then** the Kalorias session is invalidated locally
   and authenticated content is gated behind access again.
4. **Given** checking Apple credential state itself fails temporarily, **When** no definitive
   revocation was received, **Then** the app does not erase the session or local data merely
   because of that transient error.
5. **Given** a registered user opens account settings, **When** they choose account deletion and
   confirm it, **Then** the backend revokes the Apple authorization, invalidates all Kalorias
   sessions, and deletes the account and associated server data.
6. **Given** account deletion is confirmed by the backend, **When** the app finishes the action,
   **Then** it deletes the local session, pending onboarding, current user's local meal records
   and images, and returns to the first-run onboarding.
7. **Given** two different Kalorias users authenticate on the same installation over time,
   **When** either uses the app, **Then** one user's locally stored meals are never shown to the
   other user.
8. **Given** any auth/onboarding failure, **When** diagnostics are recorded, **Then** logs contain
   no Apple token, Kalorias token, email, answer, free text, health value or onboarding body.

### Edge Cases

- **Questionnaire fetch before registration**: `GET` remains public and may be cached because it
  contains product content only. The answer submission is a separate authenticated `POST`.
- **Final-answer crash window**: the complete pending payload is atomically committed before the
  UI changes to access. Relaunch can therefore never show access with no payload behind it.
- **Apple sheet cancelled**: cancellation is not presented as an error and does not mutate the
  pending onboarding.
- **Apple succeeds without an identity token or authorization code**: registration is refused;
  nothing is uploaded and the user can retry.
- **Apple name/email absent on a later authorization**: authentication still succeeds. Account
  identity comes from Apple's stable subject in the verified token, never from email.
- **Hide My Email**: a relay address, if Apple supplies one, is treated as a valid Apple-managed
  address. V1 does not require or use an email address.
- **Repeated tap on Sign in with Apple**: only one authorization attempt may be active; duplicate
  taps do not create concurrent backend calls.
- **Auth response is lost after account creation**: a fresh Apple authorization maps to the same
  backend user; it never creates a duplicate account.
- **Submission response is lost after plan creation**: the retry uses the same idempotency key and
  returns the already-created result.
- **Consent declined**: no onboarding data is sent. The registered but incomplete account and the
  protected local pending payload remain; the user may reconsider or delete the empty account.
- **Local questionnaire version becomes stale while access is pending**: the sealed submission
  keeps the exact `onboardingId`, schema/content versions and answers it was completed with. It is
  never rebuilt against newer content.
- **Backend rejects a now-retired questionnaire version**: answers remain local and the app shows
  an actionable service message. It must not silently reinterpret old option ids using a newer
  questionnaire.
- **Refresh token expired or revoked**: pending answers remain, while Apple access is requested
  again.
- **Apple authorization revoked while the app is running**: authenticated screens are gated and
  in-flight authenticated work is cancelled or allowed to fail closed; local account data is not
  exposed to a subsequently authenticated different user.
- **Existing account with complete onboarding**: its server-side plan wins. The newly completed
  local onboarding is discarded only after that state is authenticated and confirmed by the
  backend.
- **Existing account on another device**: V1 still follows the requested onboarding-first entry;
  after Apple identifies the existing complete account, the redundant local answers are not sent.
- **App reinstallation**: uninstalling can remove the pending local payload. Recovery of an
  unregistered onboarding across uninstall/device change is impossible by design because it was
  never uploaded.
- **Account changes on a shared device**: local meal records are scoped to the authenticated
  backend user identifier. Unowned records from development builds are not automatically exposed
  to every future account.
- **Deletion response lost after server commit**: the confirmed deletion attempt survives in
  device-only credential storage and can replay the exact operation against a short-lived backend
  tombstone. The app neither restores authenticated content nor deletes local data without a
  confirmed/replayed final result.

## Requirements *(mandatory)*

### Functional Requirements

#### Local-first onboarding

- **FR-001**: The app MUST present and complete the onboarding before presenting Sign in with
  Apple to a first-time user.
- **FR-002**: The app MUST persist the onboarding draft locally after every accepted answer,
  preserving the session identifier, questionnaire identity/version, start time, answers and
  shadowed conditional answers required to resume correctly.
- **FR-003**: The app MUST NOT transmit onboarding answers, answer summaries, derived profile
  values, or free text while the onboarding is being answered.
- **FR-004**: Fetching public questionnaire content MUST remain distinct from submitting user
  answers; a public fetch MUST NOT include the local draft or any stable account/device identity.
- **FR-005**: On completion, the app MUST create and atomically persist a sealed pending submission
  before navigating to access.
- **FR-006**: The sealed submission MUST preserve `sessionId`, `onboardingId`, `schemaVersion`,
  `contentVersion`, `locale`, `startedAt`, the local `completedAt`, and the final visible answer
  entries. The send time MUST NOT replace `completedAt`.
- **FR-007**: Editing answers MAY remain available before Apple registration begins; if an answer
  changes, the app MUST reseal the payload locally before registration and MUST NOT change its
  stable `sessionId`. Once an authenticated submission attempt begins, the sealed payload MUST be
  immutable until it succeeds or is explicitly discarded.

#### Access after onboarding

- **FR-008**: The access screen MUST be unreachable until a complete pending onboarding exists,
  except when reauthentication is required for a previously registered installation.
- **FR-009**: Sign in with Apple MUST be the only account-creation/sign-in method in this feature.
- **FR-010**: The app MUST use Apple's native authorization experience and MUST NOT collect or
  handle an Apple Account password itself.
- **FR-011**: Each authorization attempt MUST use a cryptographically random, single-use anti-
  replay value that the backend can verify against the Apple identity token.
- **FR-012**: V1 MUST request no Apple name/email scopes because neither is required for the
  product flow. A future requirement for either field must justify the added collection and handle
  Apple's one-time delivery semantics.
- **FR-013**: The app MUST send the Apple identity token, single-use authorization code and the
  anti-replay proof to the Kalorias backend; it MUST NOT treat unverified client-side Apple data as
  a Kalorias account.
- **FR-014**: The Apple-auth request MUST NOT contain the onboarding payload or any individual
  onboarding answer.
- **FR-015**: The user becomes registered only after the backend confirms that the Apple
  credential was verified and the Kalorias account was committed.
- **FR-016**: Repeated Apple authorization for the same verified Apple subject MUST restore the
  same Kalorias account rather than create duplicates.

#### Consent and authenticated submission

- **FR-017**: Before the first upload of onboarding answers, the app MUST present a separate,
  explicit consent for processing the health/profile data, with a versioned privacy notice; Apple
  account authorization MUST NOT double as this consent.
- **FR-018**: Declining or postponing the health-data consent MUST result in zero onboarding-data
  transmission and MUST preserve the local pending submission.
- **FR-019**: The app MUST submit the onboarding only after both registration and consent have
  succeeded, using a valid Kalorias access session.
- **FR-020**: The authenticated onboarding request MUST preserve the existing submission shape and
  `Idempotency-Key = sessionId`, adding only the required authorization and versioned consent
  metadata defined in the backend handoff.
- **FR-021**: The backend result MUST distinguish at least `onboarding required` from `onboarding
  complete` at authentication time.
- **FR-022**: If an existing authenticated account reports `onboarding complete`, the app MUST NOT
  send or overwrite it with the local pending payload. It MUST discard that payload only after the
  authenticated backend state is confirmed.
- **FR-023**: If the account reports `onboarding required`, the app MUST keep the local pending
  payload until the backend confirms its idempotent submission.
- **FR-024**: For a new/incomplete account, the main app MUST remain gated until the onboarding
  submission is confirmed. A registered-but-not-finalized account is not a completed first run.
- **FR-025**: After a confirmed submission, the app MUST clear the pending onboarding payload and
  mark the first-run state complete in one recoverable transition. Relaunch between those writes
  MUST reconcile against the server's onboarding status rather than resubmit blindly.

#### Session and recovery

- **FR-026**: Kalorias access and refresh credentials MUST be stored only in protected credential
  storage; preferences and plain application files MUST contain no bearer credential.
- **FR-026a**: The opaque Apple user identifier needed for native credential-state checks MUST be
  stored in protected credential storage alongside the session and MUST NOT be used as the app's
  server-facing user id or written to diagnostics.
- **FR-027**: The app MUST represent at least these durable journey states: answering locally,
  pending authentication, registered/pending consent, registered/pending submission, and complete.
  A single Boolean MUST NOT be the source of truth for the new flow.
- **FR-028**: Cancelling or failing Apple authorization MUST preserve the pending onboarding and
  MUST NOT be recorded as a completed registration.
- **FR-029**: Failure to create a Kalorias session MUST preserve the pending onboarding and MUST
  prevent its transmission.
- **FR-030**: A failed onboarding submission after registration MUST preserve both the sealed
  payload and any still-valid Kalorias session, allowing a manual retry without repeating Apple.
- **FR-031**: Submission retries MUST reuse the same `sessionId` and idempotency key. No error or
  relaunch may generate a new identifier for the same sealed payload.
- **FR-032**: The app MUST perform at most one transparent access-token refresh for an
  authenticated request. If refresh fails, it MUST gate access and require Apple interaction
  rather than loop.
- **FR-033**: No onboarding submission retry may run automatically after a displayed failure. The
  next attempt MUST be initiated by the user.
- **FR-034**: The app MUST check the stored Apple user's credential state at appropriate lifecycle
  points and observe revocation notifications. Only definitive revoked/not-found results may clear
  authenticated access; a transient check error MUST NOT destroy local state.
- **FR-035**: Any authenticated endpoint changed by this feature MUST return an authentication
  failure before performing domain work, making the single client retry after token refresh safe.

#### Privacy and account lifecycle

- **FR-036**: Pending onboarding files MUST use iOS data protection suitable for health data and
  MUST be excluded from application logs, analytics, crash breadcrumbs and request-body tracing.
- **FR-037**: Authentication logs MUST NOT contain Apple credentials, Kalorias credentials, raw
  Apple subjects, email addresses, nonces, onboarding answers or health/profile values.
- **FR-038**: The app MUST expose account deletion from an easy-to-find account/settings surface
  and require an explicit destructive confirmation.
- **FR-039**: Account deletion MUST call the backend while authenticated; the backend MUST revoke
  the user's Apple token/authorization, invalidate every Kalorias session and delete the account
  and associated data not subject to a documented legal retention requirement.
- **FR-040**: Only after deletion is confirmed (or accepted for processing with an explicit final
  status) may the app remove the current user's local credentials and data and return to first run.
- **FR-040a**: A user-confirmed deletion attempt MUST survive process termination until its final
  result. If the first success response is lost, the same operation authority/key MUST be replayable
  without granting access to any other authenticated route.
- **FR-041**: Locally persisted meal records and images MUST remain on-device and MUST NOT be
  uploaded by this feature.
- **FR-042**: Local meal data MUST be scoped by the stable Kalorias user identifier so one account
  cannot view another account's records on the same installation.
- **FR-043**: Deleting an account MUST remove that user's local meal records and image files.
- **FR-044**: All new user-facing copy MUST ship in Spanish and English, and every new screen MUST
  remain usable in Dark Mode, Dynamic Type, VoiceOver and Reduce Motion.

#### Backend contract transition

- **FR-045**: `GET /api/v1/kalorias/onboarding` MUST remain public and MUST NOT create a user
  session or accept user answers.
- **FR-046**: `POST /api/v1/kalorias/onboarding` MUST require a valid Kalorias bearer session after
  this feature ships; the previous no-auth contract for this method is superseded.
- **FR-047**: `POST /api/v1/kalorias/analyzeMeal` MUST require the same Kalorias bearer session,
  because the main app is account-gated; the previous no-auth requirement from feature 009 is
  superseded. Authentication MUST be checked before reading or processing the photo.
- **FR-048**: Authenticated request limits SHOULD be enforced per Kalorias user, with an additional
  IP/device abuse ceiling if needed; the user's product allowance MUST NOT depend solely on a
  shared network address.
- **FR-049**: Every changed/new server response MUST retain the `X-Request-Id` diagnostic header
  and a stable machine-readable error code; server error prose MUST NOT be the app's display copy.

### Key Entities

- **Onboarding draft**: The resumable local questionnaire state while the user is answering. It
  includes conditional/shadow state and is never sent as-is.
- **Pending onboarding submission**: An immutable, complete local snapshot ready for upload. It
  includes the stable `sessionId`, exact questionnaire versions, start/completion timestamps and
  normalized answer entries.
- **Registration attempt**: One native Apple authorization attempt and its one-time anti-replay
  value. It carries no onboarding data.
- **Kalorias user**: The server account identified by an internal stable identifier and linked to
  the verified Apple issuer/subject pair. Email is not its identity key.
- **Kalorias session**: A short-lived access credential plus a renewable, revocable session
  credential held in protected storage.
- **Health-data consent**: A positive, timestamped acceptance of a specific privacy/consent text
  version, separate from Apple authorization.
- **Onboarding record/plan**: The server-owned result of applying one idempotent pending submission
  to one registered user.
- **Journey state**: The durable client state that determines whether the root presents onboarding,
  access, consent, finalization or the main app.
- **Account-scoped local meal**: A meal that remains on-device but is associated with one Kalorias
  user identifier for isolation on a shared installation.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Across the full onboarding, network inspection finds zero user answers or derived
  health/profile data transmitted before the backend confirms account registration.
- **SC-002**: 100% of accepted answers survive force termination and relaunch at every onboarding
  step in the recovery test matrix.
- **SC-003**: In 100 interruption tests across the five registration/submission boundaries, the
  server creates at most one Kalorias user and one plan for the same Apple identity/session id.
- **SC-004**: Cancelling Apple or losing connectivity at the access screen loses zero answers and
  requires zero questions to be re-entered.
- **SC-005**: After successful registration, an onboarding service failure can be retried without
  invoking Apple again whenever the Kalorias refresh session is still valid.
- **SC-006**: A returning Apple identity with a completed onboarding causes zero overwrite requests
  and reaches the main app using the server's existing state.
- **SC-007**: Static/runtime credential audits find zero Apple private keys, client secrets,
  identity tokens, authorization codes, Kalorias bearer tokens or raw onboarding bodies in source,
  build settings, preferences and logs.
- **SC-008**: Revoking Apple authorization gates authenticated access on the next definitive
  credential-state check, without exposing account-scoped local data to another identity.
- **SC-009**: Account deletion can be initiated inside the app and removes the test user's server
  account/sessions/onboarding plus that user's local meals/images, with zero access using old
  refresh credentials afterward.
- **SC-010**: The complete flow is manually verified in Spanish and English, light and dark mode,
  an accessibility Dynamic Type size, VoiceOver, and Reduce Motion.

## Assumptions and Decisions

- **Onboarding first is absolute for new installations**: there is no “Sign in” shortcut before
  the questionnaire in V1. A returning user on a new installation completes the local onboarding;
  after Apple identifies an already-complete account, those redundant local answers are discarded
  without upload.
- **Server state wins for an existing complete account**: onboarding/profile editing and plan
  replacement belong to a later profile feature, not this registration flow.
- **No Apple profile scopes in V1**: Kalorias needs a stable verified identity, not the user's name
  or email. This minimizes collection and avoids making auth correctness depend on fields Apple may
  not return on later authorizations.
- **Explicit consent is separate**: the existing medical disclaimer is not treated as consent to
  upload/process special-category health data. Exact legal wording and lawful basis require owner/
  legal approval before release; this spec fixes the product behavior, not legal advice.
- **One automatic submission only**: the app automatically makes the first upload immediately
  after registration + consent. After a visible failure, retries are manual.
- **Local history stays local**: authentication scopes it to a user but does not add cloud sync,
  backup or restore.
- **Pre-release migration**: the constitution records that no pre-feature build was distributed.
  Therefore production migration of unowned meal records or the old `onboarding.completed` Boolean
  is out of scope. Tests must cover a deterministic development-data reset/assignment policy, but
  no silent production ownership guess is required.
- **Backend implementation language/framework is not prescribed**: the handoff defines observable
  security and API behavior so the backend team can implement it in its existing stack.

## Out of Scope

- Email/password, Google, Facebook or guest accounts.
- Collecting or editing a display name or contact email.
- A “sign in before onboarding” returning-user shortcut.
- Cloud synchronization, restore or cross-device transfer of local meal history/photos.
- Editing/replacing an already-complete server onboarding from the registration flow.
- Web/Android Sign in with Apple and Apple Services ID/redirect flows; this feature is native iOS.
- Subscription entitlements or billing.
- Changes to the questionnaire's dynamic rendering/types beyond separating completion from upload.

## Clarification Gate

No open product question remains for planning. The requested ordering and storage boundary are
explicit, and the remaining choices are resolved above: server-complete state wins for returning
users, V1 requests no Apple profile scopes, failed uploads retry manually, and the main app remains
gated until a new account's onboarding is confirmed.
