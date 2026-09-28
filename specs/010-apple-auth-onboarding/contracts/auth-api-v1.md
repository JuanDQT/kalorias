# iOS ↔ Kalorias API Contract V1

**Status**: Planned

**Base URL**: Supplied exclusively by `BackendEnvironment`

**Media type**: `application/json` unless the route says otherwise

**Backend authority**: [../backend-handoff.md](../backend-handoff.md)

This document is the contract the iOS implementation codes against. The backend handoff adds
server storage, Apple verification, security, operations, and deployment requirements.

## Shared Rules

- All production requests use TLS.
- JSON keys and stable error codes are case-sensitive.
- Dates are RFC 3339/ISO 8601 UTC instants.
- Backend user and plan identifiers are opaque non-empty strings, even when examples are UUIDs.
- JSON responses containing credentials include `Cache-Control: no-store`.
- iOS may send `X-Request-Id: <UUID>` for diagnostics. Neither side logs auth bodies, Bearer values,
  onboarding answers, photos, free text, or health/profile values.
- Authenticated routes use `Authorization: Bearer <accessToken>`.
- A `401` from an authenticated route permits one refresh and one exact replay. A second `401`, a
  definitive refresh failure, or refresh-token reuse ends the local session; it never loops.
- Error bodies use:

```json
{
  "error": {
    "code": "stable_machine_code",
    "message": "Safe localized-or-localizable public message."
  }
}
```

The client maps `code` to its own EN/ES copy and does not display raw server internals.

## `POST /api/v1/auth/apple`

Creates or restores the backend account only. It never accepts onboarding/health data.

### Request

```http
POST /api/v1/auth/apple
Content-Type: application/json
Accept: application/json
X-Request-Id: 8D011017-EFF5-4D27-A048-A7555B35F651
```

```json
{
  "identityToken": "<compact Apple identity token>",
  "authorizationCode": "<single-use Apple authorization code>",
  "nonce": "<raw nonce generated for this native attempt>"
}
```

No `answers`, `consent`, email, name, or client-declared Apple user ID is accepted. The server
derives the Apple subject from the verified token. The app keeps Apple's returned user identifier
only for local credential-state checks and compares callback `state` before making this request.

### Success

- `201 Created`: newly committed account.
- `200 OK`: existing account restored.

```json
{
  "data": {
    "user": {
      "id": "9d92525d-df31-49d2-9625-ae7a6fb48745"
    },
    "session": {
      "tokenType": "Bearer",
      "accessToken": "<opaque Kalorias access token>",
      "accessTokenExpiresAt": "2026-09-08T17:30:00Z",
      "refreshToken": "<opaque rotating refresh token>",
      "refreshTokenExpiresAt": "2026-12-07T17:15:00Z"
    },
    "onboarding": {
      "status": "required"
    }
  }
}
```

`tokenType` must equal `Bearer`. `onboarding.status` is exactly `required` or `complete`. Unknown or
empty values make the response invalid. Only after validating and persisting this response does iOS
consider registration committed.

### Stable errors

| HTTP | Code | Client behavior |
|---|---|---|
| `400` | `invalid_request` | Stay on Access; allow a fresh Apple attempt |
| `401` | `invalid_apple_credential` | Stay on Access; clear ephemeral attempt only |
| `409` | `auth_attempt_replayed` | Stay on Access; require a fresh Apple attempt |
| `429` | `auth_rate_limited` | Respect `Retry-After`; keep pending answers |
| `503` | `apple_temporarily_unavailable` | Show recoverable service failure |
| `500` | `auth_service_error` | Show recoverable service failure |

No error allows the onboarding payload to be uploaded.

## `POST /api/v1/auth/refresh`

Rotates the Kalorias session. This route does not use the expired access token as its authority.

### Request

```json
{
  "refreshToken": "<current opaque refresh token>"
}
```

### Success: `200 OK`

```json
{
  "data": {
    "session": {
      "tokenType": "Bearer",
      "accessToken": "<new access token>",
      "accessTokenExpiresAt": "2026-09-08T17:45:00Z",
      "refreshToken": "<new refresh token>",
      "refreshTokenExpiresAt": "2026-12-07T17:30:00Z"
    }
  }
}
```

The response must contain a newly rotated refresh token. The actor replaces the whole Keychain
session record before releasing waiting authenticated requests.

### Stable errors

| HTTP | Code | Client behavior |
|---|---|---|
| `400` | `invalid_request` | End active session |
| `401` | `invalid_refresh_token` | End active session; preserve pending answers |
| `409` | `refresh_token_reused` | End the whole local family; preserve pending answers |
| `429` | `refresh_rate_limited` | Do not fan out retries; surface recoverable result |
| `500/503` | `auth_service_error` | Preserve session/pending; allow later retry if refresh has not been definitively rejected |

The backend distinguishes transient service failure from an invalid/reused refresh credential.

## `POST /api/v1/auth/logout`

Invalidates the current Kalorias session family. Account deletion, not logout, revokes the Apple
relationship.

```http
POST /api/v1/auth/logout
Authorization: Bearer <access token>
Content-Type: application/json
```

```json
{
  "refreshToken": "<current refresh token>"
}
```

Success is `204 No Content`. V1 does not require a user-facing logout entry point, but the service
contract exists for session lifecycle and future account UI.

## `GET /api/v1/kalorias/onboarding?stage=onboarding`

Public questionnaire content. This is the only onboarding call allowed before registration.

```http
GET /api/v1/kalorias/onboarding?stage=onboarding
Accept-Language: es
```

- No Authorization, user ID, device ID, answers, or analytics identity is sent.
- The client accepts a complete `200` response and does not persist, bundle, or reuse questionnaire
  content through an HTTP cache.
- A network or service failure produces a retryable error. Locally protected answers remain intact
  and resume after a later successful fetch of the matching questionnaire version.
- An unsupported `schemaVersion`, question `type`, or closed structural value produces a mandatory
  app-update gate before any question is displayed; the client must not continue with older content.

## `POST /api/v1/kalorias/onboarding`

Creates the initial plan for the authenticated account after separate consent.

### Request

```http
POST /api/v1/kalorias/onboarding
Authorization: Bearer <access token>
Content-Type: application/json
Idempotency-Key: 5C2F0B1E-9A3D-4E77-9E21-2F3A9C1B7D40
```

```json
{
  "sessionId": "5C2F0B1E-9A3D-4E77-9E21-2F3A9C1B7D40",
  "onboardingId": "plan_v1",
  "schemaVersion": 1,
  "contentVersion": 5,
  "locale": "es",
  "startedAt": "2026-09-07T10:14:02Z",
  "completedAt": "2026-09-07T10:16:41Z",
  "consent": {
    "privacyNoticeVersion": "2026-09-08",
    "healthDataConsentVersion": "2026-09-08",
    "grantedAt": "2026-09-08T17:15:30Z"
  },
  "answers": [
    {
      "questionId": "goal_primary",
      "type": "single_choice",
      "optionId": "lose_weight"
    },
    {
      "questionId": "first_session_at",
      "type": "date",
      "value": "2026-09-27T18:30:00+02:00",
      "timeZone": "Europe/Madrid"
    }
  ]
}
```

Contract invariants:

- `Idempotency-Key` exactly equals body `sessionId` on every retry.
- Registration and Keychain session persistence happened before this request is constructible.
- A consent receipt is mandatory and must reference accepted versions.
- The request shape for `answers` remains the questionnaire V1 contract; no Apple credentials are
  attached.
- A plain `date` answer uses `yyyy-MM-dd`. A `dateTime` answer uses an RFC 3339 `value` with an
  explicit numeric offset plus its IANA `timeZone`; the backend must preserve the represented
  instant and zone context.
- Same user/key plus identical canonical body returns the original result. Same user/key plus a
  different body returns a conflict without changing the account.

### Success: `200 OK`

Used both for the first commit and an identical idempotent replay:

```json
{
  "data": {
    "onboardingStatus": "complete",
    "planId": "89c941df-5897-4222-9397-1d7d444d6c8d"
  }
}
```

The app validates `complete`, writes that status to AuthSession and KnownAccount, then removes the
local pending/draft files.

### Stable errors

| HTTP | Code | Client behavior |
|---|---|---|
| `401` | `authentication_required` | Refresh/replay once; then return to Access while preserving payload |
| `409` | `onboarding_already_complete` | Reconfirm authenticated complete status, then discard redundant pending data |
| `409` | `idempotency_payload_mismatch` | Stop retrying and surface a safe support/recovery error; never generate a new key |
| `409` | `consent_version_outdated` | Return to Consent with updated approved content; do not upload old receipt |
| `422` | `invalid_onboarding` | Preserve local answers; expose a recoverable validation error without raw values |
| `429/500/503` | existing safe code | Preserve session/payload and require visible manual retry |

## `POST /api/v1/kalorias/analyzeMeal`

The existing multipart request/response contract from feature 009 is unchanged except that Bearer
authentication is mandatory.

```http
POST /api/v1/kalorias/analyzeMeal
Authorization: Bearer <access token>
Content-Type: multipart/form-data; boundary=<generated>
```

- The server authenticates and enforces size/rate limits before parsing the image or invoking the
  analysis provider.
- `401` means no image was processed/stored and no provider quota was consumed, allowing one
  refresh and exact replay by the client.
- Product rate limiting uses backend `userId`, optionally with network/device abuse ceilings.
- Success, normalized analysis body, timeouts, `Retry-After`, and `X-Request-Id` behavior otherwise
  remain the feature 009 contract.

## `DELETE /api/v1/account`

Revokes Sign in with Apple, invalidates all Kalorias sessions, and removes/anonymizes server data as
specified by policy. The app presents a destructive system confirmation before calling it.

```http
DELETE /api/v1/account
Authorization: Bearer <access token>
Idempotency-Key: 91488C49-4DB0-41ED-AC10-1B8C9E30E25C
```

After destructive confirmation and before the first request, iOS stores the operation key, exact
presented Bearer, and owner ID as `AccountDeletionAttempt` in device-only Keychain, then hides the
authenticated app shell. Retries of an ambiguous completed request bypass ordinary proactive refresh
and present those exact values so they can match the deletion tombstone.

### Success: `204 No Content`

For client V1, `204` means server-side Apple revocation and account deletion are complete. Only then
does iOS remove current-owner meals/images, pending/draft data, AuthSession, KnownAccount, and the
persisted AccountDeletionAttempt.

`DELETE` is idempotent for the same operation key. iOS retains the exact operation key and presented
access token until it receives `204`. If the first response is lost after deletion, the route checks
a bounded server deletion tombstone (HMAC of both values) before ordinary auth failure and returns
the cached `204`. This route-specific replay grants no other API access and cannot resurrect data.

### Stable errors

| HTTP | Code | Client behavior |
|---|---|---|
| `401` | `authentication_required` | Refresh once; if needed return to Apple reauthentication without local deletion |
| `403` | `reauthentication_required` | Invoke Apple; retry deletion only after fresh Kalorias authority |
| `409/503` | `apple_revocation_pending` | Preserve all local/session data and offer retry |
| `429` | `account_action_rate_limited` | Respect `Retry-After`; preserve data |
| `500` | `account_deletion_error` | Preserve data and offer retry |

`202 Accepted` is not a valid success for this V1 app. Supporting asynchronous deletion requires a
separately versioned response plus a status endpoint and authenticated/resumable polling semantics.

## Authenticated Client Algorithm

For each authenticated request:

1. Ask `AuthSessionCoordinator` for a valid access token.
2. If near expiry, join/create the actor's single refresh operation.
3. Attach the returned Bearer token and send once.
4. If response is not `401`, return it unchanged to the feature service.
5. If `401`, force exactly one coalesced refresh and replay exactly once.
6. If refresh is definitively rejected or replay is `401`, invalidate the active session and emit
   `authenticationRequired` to `AppJourneyStore`.
7. Never retry `409`, `422`, or other domain failures as authentication failures.

Requests that cannot be safely replayed must opt out. The onboarding request is safe through its
stable idempotency key; analysis is safe after auth-first server rejection; account deletion uses its
own stable operation idempotency key.

## Contract Test Matrix

- Exact request path/method/headers/body for all routes.
- `/auth/apple` body proves no onboarding/name/email/client Apple ID is encoded.
- Auth response rejects unknown status, wrong token type, empty opaque values, or invalid dates.
- Single-flight refresh serves concurrent requests with one refresh call and rotated persisted data.
- Authenticated client replays at most once and does not turn domain errors into refresh attempts.
- Onboarding reuses identical body/key after timeout and recognizes complete replay.
- Analysis sends Bearer and replays only after auth-first `401`.
- Deletion performs no local cleanup for any non-`204` result.
