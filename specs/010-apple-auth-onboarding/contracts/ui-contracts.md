# UI Contract: Post-Onboarding Access and Account Lifecycle

**Platform**: iOS 26.5+, SwiftUI

**Languages**: English and Spanish

**Appearance**: Light and Dark

**Architecture**: MVS with root journey state; Router owns in-app destinations

## Shared Presentation Rules

- Access, consent, finalization, and privacy notice are full-screen root phases on opaque
  `AppColor.surfacePrimary`; they are not sheets over the authenticated app.
- Account Settings is a routed destination from Progress because it belongs inside an authenticated
  journey.
- Use only existing `AppTypography`, `AppSpacing`, `AppColor`, and `AppMotion` roles. No inline font,
  spacing, color, spring/easing, glass, blur, or material literals.
- Root/observable phase changes animate through the existing `AppMotion.standard` transition pair.
  Small status changes use `AppMotion.subtle`; gestures use the existing gestural pair. The vocabulary
  supplies the Reduce Motion substitution.
- No idle animation, staggered entrance, decorative flourish, or custom haptic. Native buttons retain
  immediate system press feedback.
- Layout supports Dynamic Type without clipping, logical VoiceOver order, landscape/small screens,
  keyboard/safe areas, and minimum 44×44-point interactive targets.
- Errors use concise localizable copy and a next action. Raw HTTP codes, token/JWT terms, Apple
  subjects, backend IDs, request IDs, and validation paths are never VoiceOver/user-facing text.

## Root Phase Contract

`RootView` renders exactly one branch from `AppJourneyStore.phase`:

| Phase | Visible root | Authenticated app shell active? |
|---|---|---|
| `restoring` | Launch/restoration progress on branded opaque background | No |
| `onboarding` | Existing onboarding chat | No |
| `access` | `AccessView` | No |
| `consent` | `HealthDataConsentView` | No |
| `finalizing` | `FinalizingOnboardingView` | No |
| `ready` | Existing tab shell | Yes |
| `deletingAccount` | `AccountDeletionView` | No |

The Camera cover and navigation paths are dismissed/cleared before transitioning from `ready` to an
identity gate. No authenticated view renders behind Access or Consent, including during animation.

## AccessView

### Purpose

Authenticate with Apple only after a complete local onboarding exists, or reauthenticate a known
account. The screen never collects onboarding answers, name, email, or password.

### Layout

From top to bottom within a safe-area-aware scroll container:

1. Kalorias app mark/title using existing brand and title roles.
2. Short explanation that Apple creates/opens the account and saved answers remain on this device
   until registration and separate consent succeed.
3. Flexible spacing.
4. Native `SignInWithAppleButton(.continue)`, using the system style appropriate for current color
   scheme and Apple's required sizing.
5. Optional “Review answers” secondary button only when a local pending onboarding belongs to an
   account not yet committed in this journey.
6. Inline status/error region with retry guidance.
7. Privacy notice link.

The content column uses the existing readable/max-width convention. It does not place the Apple
button inside a custom card or restyle its icon/text.

### States and actions

| State | Apple action | Other behavior |
|---|---|---|
| Idle | Enabled | Review/privacy links enabled |
| Native Apple sheet shown | System-owned | Local pending data stays unchanged |
| Backend registration in progress | Disabled; adjacent system progress indicator | Review disabled to prevent changing sealed data mid-auth |
| User cancelled Apple | Enabled | Quiet localized cancellation feedback; not styled as a destructive error |
| Recoverable Apple/backend error | Enabled or delayed by `Retry-After` | Localized message; pending data unchanged |
| Invalid callback/state/token mapping | Enabled for a wholly fresh attempt | Old nonce/state cleared; nothing sent if local state comparison failed |

Apple success does not transition directly to `ready`. It transitions from the persisted backend
status to `consent`, `onboarding`, `finalizing`, or `ready`.

### Accessibility identifiers

```text
access.screen
access.appleButton
access.reviewAnswersButton
access.privacyButton
access.progress
access.error
```

The native Apple control keeps its native accessible name. The identifier supplements it and does
not replace its label.

## HealthDataConsentView

### Purpose

Obtain explicit permission to send/process the already completed health/profile answers. This is a
separate decision after backend registration.

### Layout

1. Localized title explaining creation of the personalized plan.
2. Concise approved summary of data categories and purpose.
3. Link/button to open the full bundled/published privacy notice.
4. Primary affirmative button: localized equivalent of “Accept and create plan.”
5. Secondary “Not now” button.

Exact legal copy and version constants are approved release inputs. Placeholder legal prose must not
ship. The code references localization keys and compiled approved versions, not server-delivered HTML
that can silently change the consent presented for the same version.

### States and actions

| Action/state | Contract |
|---|---|
| Open privacy notice | Shows readable localized notice; returning preserves the consent gate |
| Accept | Persist `ConsentReceipt` first, then transition to first automatic finalization attempt |
| Not now | Remain registered with payload local; make no onboarding request |
| Local receipt write fails | Remain on consent, show retryable storage error, send nothing |
| Consent version rejected by server | Return/show consent gate with newly approved version; old receipt cannot be reused |

There is no preselected checkbox, inferred acceptance, timeout acceptance, or acceptance attached to
the Apple button.

### Accessibility identifiers

```text
consent.screen
consent.summary
consent.privacyButton
consent.acceptButton
consent.notNowButton
consent.error
```

## PrivacyNoticeView

### Purpose

Display the approved localized privacy/health-data information from Access, Consent, and Account
Settings.

### Contract

- Readable scroll view with semantic headings and Dynamic Type.
- Displays the public privacy-policy link where required; opening an external URL is explicit.
- The Account Settings version does not imply a new consent action.
- The Consent version returns to the unchanged consent screen; reading alone is not acceptance.
- Version shown to the user corresponds exactly to the `privacyNoticeVersion` stored in the receipt.

Identifiers:

```text
privacy.screen
privacy.content
privacy.externalPolicyLink
privacy.doneButton
```

## FinalizingOnboardingView

### Purpose

Represent the authenticated, consented upload boundary without asking the user to repeat Apple
authorization while their Kalorias session remains renewable.

### States

| State | Presentation | Action |
|---|---|---|
| First attempt in progress | Title/body plus system progress indicator | No duplicate submit action |
| Failed after a visible attempt | Safe localized reason category | Primary “Try again”; privacy notice remains available |
| Relaunched with consented pending payload | Calm recovery message, no silent network call | Primary “Continue” starts retry |
| Session no longer renewable | Transition to Access | Pending answers and consent stay protected locally |
| Server says account already complete | No error presentation | Persist complete, discard redundant pending, enter app |
| Success | Brief state transition only; no blocking celebration | Enter `ready` immediately after durable status commit |

Repeated primary taps while one request is in flight are ignored/disabled. The same body and
idempotency key are used for all retries.

Identifiers:

```text
finalization.screen
finalization.progress
finalization.retryButton
finalization.error
finalization.privacyButton
```

## AccountSettingsView

### Entry and navigation

- Add an account/settings toolbar action to the authenticated Progress tab.
- `Router.progressPath` owns the `ProgressRoute.account` destination.
- Identity invalidation/deletion clears this path before changing the root journey phase.

### Content

1. Account heading and safe nontechnical account status; do not expose Apple subject/backend ID.
2. Privacy notice action.
3. Destructive “Delete account” action.

Logout UI is outside V1 product scope even though the backend session service supports logout.

### Deletion flow

1. Tapping Delete presents a native destructive alert/dialog explaining permanent server and device
   deletion and that the operation cannot be undone.
2. Cancel dismisses with no state/network change.
3. Confirm persists the stable operation key, exact Bearer, and owner ID in device-only Keychain,
   clears/dismisses authenticated presentation, and enters `AccountDeletionView` before calling the
   deletion service.
4. Any non-`204` result keeps all local data/session intact and shows a retryable safe error.
5. A reauthentication-required result runs the Apple flow and resumes only this confirmed deletion;
   it does not resend onboarding.
6. If the app terminates before receiving a response, bootstrap restores `AccountDeletionView`; a
   user-initiated Continue replays the exact confirmed operation without proactive token refresh.
7. After `204`, keep authenticated content hidden while local owner-scoped cleanup runs; transition
   to fresh onboarding when cleanup has reached its durable completion boundary.

Use a confirmation only here because this action is genuinely destructive. No custom confirmation
is added to retry, cancel Apple, decline consent, or review answers.

Identifiers:

```text
account.screen
account.privacyButton
account.deleteButton
account.deleteConfirmButton
account.deleteCancelButton
account.deleteProgress
account.deleteError
account.deleteContinueButton
```

## Existing Onboarding Changes

- The existing final answer no longer displays/suggests server submission before Access.
- Final answer acceptance shows the next phase only after the pending protected write succeeds.
- While editing before initial account commit, “Review answers” preserves `sessionId` and reseals a
  complete replacement payload.
- After backend account commit, the pending snapshot is frozen for idempotent retry; answer editing
  is unavailable unless the backend says onboarding is required and no submission exists.
- Storage failure copy distinguishes “could not save on this device” from network failure and does
  not advance the question.

## Localization Key Inventory

Names are stable implementation keys; both EN and ES values are required in
`Resources/Localizable.xcstrings` before merge.

```text
journey.restoring.title
access.title
access.body.pending
access.body.returning
access.reviewAnswers
access.cancelled
access.error.invalidCredential
access.error.replayed
access.error.rateLimited
access.error.serviceUnavailable
access.error.generic
consent.title
consent.summary
consent.accept
consent.notNow
consent.storageError
consent.outdated
privacy.title
privacy.openExternal
privacy.done
finalization.title
finalization.body.uploading
finalization.body.resume
finalization.retry
finalization.error.network
finalization.error.validation
finalization.error.generic
account.title
account.privacy
account.delete
account.delete.confirm.title
account.delete.confirm.body
account.delete.confirm.action
account.delete.confirm.cancel
account.delete.progress
account.delete.error
account.transfer.title
account.transfer.body
common.continue
common.tryAgain
```

The exact wording may reuse existing generic keys when semantics are identical; implementation must
not duplicate near-identical catalog entries merely to match this namespace.

## DEBUG State Hooks

Add deterministic DEBUG-only launch arguments/dependency fixtures without authoring UI tests:

```text
-journey-state onboarding
-journey-state access-pending
-journey-state access-returning
-journey-state consent
-journey-state finalizing
-journey-state finalizing-error
-journey-state ready
-journey-state deleting-account
-journey-state deleting-account-error
-account-deletion-error
```

Hooks inject fixture services/storage into app composition and never compile into Release behavior.
They must not weaken Keychain, Apple authorization, or server verification in production builds.

## Manual Accessibility and Appearance Acceptance

- EN and ES at default and largest accessibility text size.
- Light and Dark Mode contrast; palette measurement remains at least 4.5:1 for text-bearing tokens.
- VoiceOver reads purpose, state, error, and action in logical order without technical identifiers.
- Reduce Motion enabled: all state changes remain understandable with the vocabulary's substitution.
- Increase Contrast and Reduce Transparency enabled: opaque gates remain legible; native system
  controls honor settings.
- Switch Control/keyboard focus can reach Apple, privacy, consent, retry, and deletion controls.
- Cancelled Apple authorization returns focus predictably to the native button or error/status region.
