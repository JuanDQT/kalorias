# Quickstart and Validation: Sign in with Apple After Local Onboarding

This guide is for implementing and validating the iOS half of the feature. The backend team should
receive [backend-handoff.md](./backend-handoff.md) and implement against
[contracts/auth-api-v1.md](./contracts/auth-api-v1.md).

## Prerequisites

- Xcode 26.6 or newer with the iOS 26.5 runtime. The current workspace was verified with Xcode 26.6.
- An Apple Developer team whose explicit App ID matches `com.quispe.kalorias.Kalorias` and has Sign
  in with Apple enabled.
- A development provisioning profile including the Sign in with Apple entitlement.
- A physical test device signed in to an Apple ID for the authoritative Apple authorization test.
  The simulator is sufficient for deterministic fixture/service tests but is not the release gate
  for real Apple credentials.
- A staging Kalorias backend implementing the V1 contract and configured with its own Apple Team ID,
  Key ID, private key, native client ID, token-signing material, data store, and TLS endpoint.
- Approved English and Spanish privacy/health-consent copy and immutable version identifiers before
  release validation.

No Apple private key, Apple client secret, Kalorias signing key, provider key, or reusable credential
belongs in the app repository or `Secrets.xcconfig`.

## Local Configuration

1. Keep the central environment mechanism already used by `BackendEnvironment`.
2. Copy missing local values from `Config/Secrets.example.xcconfig` into the git-ignored
   `Config/Secrets.xcconfig`; set the Debug backend base URL to staging and Release to production.
3. Do not add endpoint paths to xcconfig. Services append contract paths to the one validated base
   URL.
4. Add `Kalorias/Kalorias.entitlements` with the application entitlement:

   ```text
   com.apple.developer.applesignin = [Default]
   ```

5. Set `CODE_SIGN_ENTITLEMENTS = Kalorias/Kalorias.entitlements` for the app's Debug and Release
   configurations and enable the capability for the App ID/profile in Apple Developer/Xcode signing.
6. Confirm the backend's Apple audience/client ID exactly matches the app bundle identifier. Never
   place the backend Apple private key or generated client secret in the iOS target.

## Build and Unit Tests

From the repository root:

```bash
xcodebuild \
  -project Kalorias.xcodeproj \
  -scheme Kalorias \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.5' \
  build
```

```bash
xcodebuild \
  -project Kalorias.xcodeproj \
  -scheme Kalorias \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.5' \
  test
```

Build and tests must complete with zero warnings under Swift 6 complete concurrency. XCUITest remains
disabled and is neither authored nor run for this feature.

The app source root is filesystem-synchronized, but `KaloriasTests` is a manual Xcode group. Register
each new test file in all three required `project.pbxproj` locations: file reference, test group, and
the test target Sources build phase. A passing test command that never compiled a new file is not a
valid result.

## Required Unit/Integration Coverage

Run the complete suite, with focused coverage for:

- `OnboardingStore`: each answer is persisted before advancement; final answer seals locally and
  performs zero submission calls; storage failure does not advance.
- `PendingOnboardingStorage`: atomic round trip, consent update, corruption, file protection
  attributes, restart recovery, and idempotent cleanup.
- Apple request factory: secure nonce shape, SHA-256 mapping, independent state, exact callback state,
  cancellation, missing credential fields, invalid UTF-8, and no requested name/email scopes.
- `RemoteAuthService`: exact methods/paths/bodies; no answers/email/name/client Apple ID in auth;
  response validation; safe stable error mapping.
- `KeychainCredentialStore`: add/update/read/delete, separate session/known-account records,
  persisted deletion-attempt record, non-synchronizing device-only attributes, decoding failure, and
  no duplicate-item regression.
- `AuthSessionCoordinator`: proactive expiry refresh, one in-flight refresh for concurrent callers,
  token rotation commit, transient versus definitive failure, and reuse-family invalidation.
- `AuthenticatedHTTPClient`: Bearer attachment, single `401` refresh/replay, no loop, no refresh for
  `409`/`422`, and correct session-required event.
- `AppJourneyStore`: every row in the bootstrap table, safe commit ordering, fresh-consent automatic
  upload, relaunch/manual retry, returning-complete discard, revocation, transfer, and deletion.
- `RemoteOnboardingService`: public questionnaire GET remains anonymous; submission is authenticated,
  includes consent, and reuses body/key exactly.
- `RemoteCalorieService`: Bearer required and one replay only after auth-first `401`.
- Meal persistence: active owner required for writes; cross-account rows hidden in repository,
  History, and Progress; legacy ownerless rows hidden; deletion removes only the selected owner.
- Image storage: protected write and current-owner batch deletion remain off the main actor and safe
  to repeat.
- Router: account destination and clearing paths/camera presentation before an identity gate.
- Existing questionnaire, analysis, history, palette, motion, localization, and environment audits.

Use injectable clocks, UUID/random generators, Keychain adapters, URL sessions/protocols, and
credential-state services so tests are deterministic. Tests must not contact Apple or a live backend.

## Manual End-to-End Matrix

Use a staging account and inspect both client proxy traffic and redacted backend logs.

| Case | Procedure | Expected result |
|---|---|---|
| Backend unavailable | Disable network before loading onboarding | Retryable questionnaire error; no cached/bundled questions; saved answers remain intact |
| Questionnaire incompatible | Return a higher schema version or unknown question type | Mandatory update gate before any question; no retry or stale questionnaire path |
| Date and time | Serve a `date` question with `mode: dateTime`, answer it, relaunch and submit | Same local wall time and zone resume; payload contains RFC 3339 offset plus IANA `timeZone` |
| Mid-draft termination | Kill after several answers and relaunch | Same session/version/answers and correct next question resume |
| Final-answer boundary | Accept final answer, kill during transition, relaunch | Complete protected pending payload exists; Access is shown |
| Apple cancellation | Cancel native sheet | Access remains; every answer stays local; no backend auth request if no credential |
| New registration | Complete Apple auth against staging | `/auth/apple` commits first with no answers; then Consent appears |
| Consent declined | Choose Not now | No onboarding POST; session and pending payload remain |
| Consent accepted | Accept approved notice | Receipt persists before authenticated onboarding POST; success opens app |
| Auth backend failure | Make `/auth/apple` fail | No onboarding POST; Access offers retry; pending data remains |
| Submission failure | Let auth succeed, fail onboarding POST, then retry | Apple is not reopened; identical session ID/key/body are reused |
| Lost success response | Backend commits then drop response; retry | Backend returns original plan; no duplicate plan is created |
| Relaunch after failed upload | Kill on finalization error and relaunch | No silent upload; visible Continue/Try again performs retry |
| Returning complete account | Create local pending, then sign into already-complete account | Local pending is discarded only after complete status persists; existing plan is unchanged |
| Access expiry | Expire access while refresh is valid | Exactly one refresh and one request replay occur |
| Concurrent expiry | Start two authenticated calls together | One refresh is sent; both use the rotated session |
| Refresh rejected | Invalidate refresh before pending upload | Returns to Access; pending answers/consent remain |
| Apple revoked | Revoke authorization and foreground/relaunch | Definitive revoked/not-found gates app behind Access; local history is not leaked/deleted |
| Credential check unavailable | Make state lookup fail transiently | Session/local data are not erased solely for that failure |
| Second user on device | Authenticate a different staging identity | First user's local meals never appear in History or Progress |
| Deletion failure | Fail Apple revocation/server deletion | Account screen shows retry; no local record/token is deleted |
| Lost deletion response | Let server delete, drop first `204`, terminate/relaunch, then continue | Deletion gate replays exact bearer/key; tombstone returns `204`; local cleanup finishes |
| Deletion success | Confirm deletion and receive `204` | Current owner server/local data and credentials clear; fresh onboarding starts |

## Privacy Boundary Audit

Before registration succeeds, allow only the public questionnaire GET and Apple's system-controlled
authorization traffic. In a network proxy, backend access logs, crash reports, and app console, verify:

- No onboarding answer, date, measurement, condition, free text, or derived profile is sent during
  questionnaire entry or `/auth/apple`.
- `/auth/apple` contains only identity token, authorization code, and raw nonce.
- Onboarding POST appears only after backend auth success and affirmative versioned consent.
- Every onboarding/analysis/deletion request has Bearer authentication.
- No request URL/query string contains credentials or answers.
- No response/request body is captured by proxy/APM production logging.
- Console logs contain no Apple/Kalorias token, nonce, email, subject, answer, photo, or raw backend ID.

Inspect app persistence on a development device/simulator:

- `UserDefaults` has no completion authority, tokens, Apple identifier, answers, or consent receipt.
- Keychain items use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and are not synchronizable.
- Draft/pending and saved meal images have complete file protection; no questionnaire cache or
  bundled questionnaire exists.
- Owner-filtered SwiftData queries do not materialize another user's or legacy unowned rows.

## UX, Localization, and Accessibility Pass

Exercise every new DEBUG fixture state from [contracts/ui-contracts.md](./contracts/ui-contracts.md)
and the real flow where available:

- English and Spanish, including long error/rate-limit copy.
- Light and Dark appearances.
- Default and largest accessibility Dynamic Type sizes.
- VoiceOver labels/order, especially native Apple, consent, retry, privacy, and destructive actions.
- Reduce Motion, Increase Contrast, and Reduce Transparency.
- Small phone and iPad layouts, portrait and landscape.
- Slow/offline network and repeated taps while operations are in flight.

There must be no clipped text, raw technical identifier, unlocalized string, inline animation
constructor, custom Apple branding, or authenticated content visible behind a root gate.

## Performance Measurements

Measure a representative Release build rather than asserting by inspection:

- Cold launch from process start to stable restored root phase: under 2 seconds on the project's
  reference device.
- Accepted answer through protected durable write and next-state publication: under 100 ms at p95.
- History/progress fetch and local meal mutation with 10,000 mixed-owner rows: existing budget under
  100 ms for local mutation and no cross-owner materialization in presentation.
- Expired-token burst: one refresh regardless of concurrent authenticated callers.
- Account deletion local cleanup: heavy image enumeration/deletion off main actor with responsive
  progress UI.

Record device, build configuration, data size, iterations, median/p95, and result in the change/PR.

## Release Gate

- Apple App ID, entitlement, signing profile, and production backend audience agree exactly.
- Real-device Apple sign-in passes for new and returning users.
- Backend Apple key rotation/JWKS cache, nonce replay, refresh reuse, idempotency, auth-before-work,
  revocation, and synchronous deletion contract tests pass.
- Approved consent/privacy copy and version IDs ship in both locales; privacy-policy URL is live.
- App Store privacy answers include linked account identifiers and health/profile data as applicable.
- Production build resolves only the production `BackendEnvironment` address.
- Full unit suite and zero-warning Release build pass; no secret/source/binary scan finding remains.
