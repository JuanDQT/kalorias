# Research: Meal Analysis Moves to the Kalorias Backend

**Feature**: `009-backend-meal-analysis` | **Date**: 2026-08-01

Everything the spec left to the implementation, resolved. Each entry is a decision, why it was
taken, and what was rejected. Ordered by how expensive the decision is to reverse later.

---

## 1. Where the base URL lives, and the `//` trap

**Decision**: two values in `Config/Secrets.xcconfig` (already the base configuration for both
Debug and Release — `project.pbxproj:437,477`), selected by `$(CONFIGURATION)`, surfaced through
`Info.plist` as `KaloriasAPIBaseURL`, read by `BackendEnvironment`.

```
SLASH = /
KALORIAS_API_BASE_URL_Debug   = http:$(SLASH)$(SLASH)localhost:8000
KALORIAS_API_BASE_URL_Release = https:$(SLASH)$(SLASH)www.quispe.com
KALORIAS_API_BASE_URL = $(KALORIAS_API_BASE_URL_$(CONFIGURATION))
```

**Rationale**: the file, the plist plumbing and the git-ignore rule all exist already — this reuses
the exact mechanism the Gemini key used, so nothing new has to be explained to a future
contributor. `$(SETTING_$(CONFIGURATION))` is the standard xcconfig idiom for a per-configuration
value and needs no scheme or target changes.

**The `//` trap is the whole reason this entry is first.** In an xcconfig file `//` begins a
comment, *including inside a value*. Written literally, `KALORIAS_API_BASE_URL = https://x.com`
silently becomes `https:` — a URL that parses fine and resolves to nothing, producing a generic
service error on every analysis with no clue as to why. The `$(SLASH)` indirection is the standard
workaround. A test asserting the built URL is well-formed catches a regression here (see
data-model.md, `BackendEnvironment`).

**Alternatives rejected**:

- *Hardcode with `#if DEBUG`* — violates FR-007 (switching must not need a code change) and puts
  the production address in the repository.
- *Two `Info.plist` files, one per configuration* — duplicates 40 lines of plist to vary one
  string, and they drift.
- *User-entered address in a settings screen* — the spec rules it out; the address is a build
  property, not a user preference.

---

## 2. Reaching an unencrypted `localhost` (FR-007a)

**Decision**: add `NSAllowsLocalNetworking = true` to the single `Info.plist`. Do **not** add
`NSAllowsArbitraryLoads`, and do **not** add an `NSExceptionDomains` entry.

**Rationale**: `NSAllowsLocalNetworking` relaxes App Transport Security for loopback, private
address ranges and `.local` names *only*. Public hosts keep full ATS, so the release build's
`https://` address is unaffected — which is precisely FR-007a's requirement, satisfied by the
shape of the key rather than by remembering to strip something before release. That is why it
beats a per-configuration plist: there is nothing to forget. It is also an Apple-sanctioned key
that does not draw App Review attention, unlike `NSAllowsArbitraryLoads`.

**Loopback may not need it at all** — ATS is widely documented as not applying to loopback
connections. The key is kept regardless, because it costs nothing and it *is* required for the
case that actually bites: a **physical device** cannot reach the Mac's `localhost` and must use
the Mac's LAN address (`http://192.168.x.x:8000`), which is a private range and therefore
squarely inside what this key permits. Verified at implementation time by the quickstart's
first-run check; the symptom of getting it wrong is unmistakable (an ATS error in the console and
a `.serviceError` on screen).

**Alternatives rejected**:

- *`NSAllowsArbitraryLoads`* — disables ATS for every host including production. Directly
  contradicts FR-007a.
- *`NSExceptionDomains` for `localhost`* — narrower than needed in one direction (misses the LAN
  address a device needs) and it would ship in the release binary unless split per configuration.

---

## 3. Building the multipart body

**Decision**: build the `multipart/form-data` body by hand in a small pure `MultipartFormData`
type, one part named `photo`, and send it with `URLSession.upload(for:from:)`.

**Rationale**: Foundation has no multipart encoder, and the contract needs exactly one part — the
whole body is a boundary line, three headers, the JPEG, and a closing boundary. That is ~20 lines
and a unit test, against which any third-party dependency fails the constitution's
justification bar (Technology Constraints). Keeping it a pure value type (`Data` in, `Data` out,
plus its `Content-Type` value) makes the two things most likely to be wrong — the exact CRLF
placement and the closing `--boundary--` — assertable in a test rather than debuggable against a
live server.

Two details the contract is explicit about and the implementation must honour:

- The field name is exactly `photo`.
- `Content-Type` is set **once**, to `multipart/form-data; boundary=<generated>`, by the code that
  owns the boundary. It must never be hardcoded, and the boundary in the header must be the same
  string used in the body — the classic failure, and it returns `422` with a message about a
  missing photo, which reads like a bug in the wrong place entirely.

**Alternatives rejected**: a networking library (unjustifiable for one request); base64/JSON (not
what the contract accepts).

---

## 4. Timeouts: 35 s is not one number

**Decision**: a dedicated `URLSession` for analysis with
`timeoutIntervalForRequest = 35` **and** `timeoutIntervalForResource = 60`.

**Rationale**: `timeoutIntervalForRequest` is an *inactivity* timer, not a total-duration budget —
it resets on every byte received. Setting only that satisfies FR-005's letter while allowing a
slow-drip response to hang far longer than 35 s. `timeoutIntervalForResource` is the wall-clock
ceiling for the whole transfer and is what actually bounds the user's wait. Both are needed: the
first gives the 35 s of patience FR-005 requires while the server waits on the model, the second
guarantees the flow terminates. `URLError.timedOut` from either maps to `.timeout`, which already
has a message and a retry action.

---

## 5. Never cached (FR-006)

**Decision**: build that session from `URLSessionConfiguration.ephemeral`.

**Rationale**: three independent reasons a response could persist — `URLCache`, cookie storage,
credential storage — and `.ephemeral` removes all three with one line, keeping no on-disk cache at
all. The server already sends `Cache-Control: no-store, private` and `POST` responses are not
cached by default, so this is belt-and-braces; the point is that FR-006 becomes a property of the
session's construction, provable by reading one line, instead of a chain of assumptions about
defaults. It also keeps meal photos out of any shared cookie/credential state.

---

## 6. `Retry-After`, and a countdown that is testable

**Decision**: parse `Retry-After` as delay-seconds first, then as an HTTP-date; clamp to
`1...3600`; default to **60 s** when absent or unparseable (FR-020a). The countdown lives in a
pure `RetryCooldown` value type that answers `secondsRemaining(at: Date)`; the store owns a
`Task` that ticks it once a second and publishes the number.

**Rationale**: `Retry-After` is defined as *either* a number of seconds *or* an HTTP-date, and
servers behind proxies send both — parsing only the integer form yields `nil` exactly when a proxy
is involved, i.e. in production. Clamping guards against a nonsense value pinning the retry button
off for hours.

The pure/impure split is what makes this pass the constitution's ban on wall-clock-dependent tests
(Principle II): every rule — remaining seconds, expiry, "already expired", clamping, both header
formats — is asserted by feeding `RetryCooldown` explicit dates. The only untested part is a
`Task.sleep` loop with no logic in it. Tests never sleep.

**Alternatives rejected**: `Timer`/`TimelineView` in the view (puts logic in the view layer,
Principle V, and makes it untestable); trusting the header unclamped.

---

## 7. Photo preparation: 1024 and a quality ladder

**Decision**: a pure `AnalysisPhotoEncoder` that downsizes to a longest side of 1024 with the
existing `ImageCropper.downsized`, encodes at quality 0.8, and — only if the result still exceeds
the cap — re-encodes at 0.6 then 0.4, giving up with `nil` after that. Cap enforced at **7.5 MB**,
not 8.

**Rationale**: the server analyses a copy whose longest side is 1024, so sending more resolution
buys no accuracy and only costs upload time on a phone connection. At that size a JPEG is
typically 100–300 KB, so the ladder is a guard that should never fire rather than a routine path.
The margin exists because the 8 MB limit applies to the multipart body, which is the JPEG plus
boundary and headers, and because the server's check may be on the raw byte count — sizing the
photo to exactly the limit is how you get a `422` on the one photo that matters.

This closes the real defect noted in the spec: `CameraCaptureView.swift:74` currently sends
`jpegData(compressionQuality: 0.8)` at full capture resolution, which on a 48 MP device can exceed
the cap outright (SC-006).

**Placement**: at the capture site, not inside the network service, so `CalorieAnalyzing` keeps
its `analyze(imageData:)` shape, the service stays free of UIKit, and a retry re-sends the bytes
already prepared instead of re-encoding the image every attempt.

---

## 8. Status codes → user-facing outcomes

**Decision**:

| Response | Outcome | User action |
|---|---|---|
| `200` + `foodDetected: true` | `.success` | — |
| `200` + `foodDetected: false` | `.noFood` | Retake |
| `422`, `413` | `.photoRejected` | **Retake** (not retry) |
| `429` | `.rateLimited(retryAfter:)` | Retry, disabled until the countdown expires |
| `503`, any other `5xx`, any unexpected status | `.serviceError` | Retry |
| Unreadable/mismatched body on a `200` | `.invalidResponse` | Retry |
| `URLError` | `.noConnection` / `.timeout` / `.serviceError` | Retry |

**Rationale**: this is the spec's failure set (FR-018) mapped onto exactly what the contract can
return. `413` joins `422` because the user's move is identical — a different photo — and the
distinction is which layer refused, which is meaningless to them. Unexpected statuses fall to
`.serviceError` rather than crashing or inventing a case; the contract may add codes and the app
must not break when it does.

**The server's message text is never displayed** (FR-021a). It arrives in Spanish only and the app
is bilingual, so it goes to the log with the request id. This costs specificity about *why* a
photo was rejected, which is acceptable because the app controls the format and size it sends: a
`422` means the app has a bug, not that the user chose a bad photo.

---

## 9. `X-Request-Id`: `os.Logger`, and what must not be logged

**Decision**: one `Logger(subsystem: <bundle id>, category: "analysis")`. Log at `.info` on
success and `.error` on failure: outcome, duration, HTTP status, `X-Request-Id`, and for a
rejected photo the server's message. Interpolate the request id with `privacy: .public`.

**Rationale**: `os.Logger` redacts interpolated values by default in release builds — an id that
comes out as `<private>` when you finally get hold of the device is a log entry that cost effort
and answers nothing. The id is server-generated and identifies nothing about the user, so
`.public` is correct here. Everything else stays default-redacted, which is what keeps FR-026
true. The photo is never logged; neither are food names.

**Not built**: no crash reporter, no analytics, no on-screen id, no persisted log file. Per the
maintainer's decision, the system log is the whole mechanism (FR-027).

---

## 10. The reported total, and what happens if it disagrees

**Decision**: display and store `data.totalCalories` exactly as received (FR-012). In DEBUG only,
compare it with the sum of the items and log a warning on mismatch. Never substitute the app's own
arithmetic, and never fail the analysis over it.

**Rationale**: the spec's edge case is explicit — the reported total is what the user sees. The
server guarantees the invariant, so a mismatch means the contract is broken, and the useful
response to that is a log entry aimed at whoever can fix it, not a failed meal for the user or a
number on screen that contradicts the list beneath it.

`CalorieAggregator` is therefore reshaped rather than deleted: `make(from:reportedTotal:)` keeps
ownership of the empty-items ⇒ `.noFood` rule, and `total(of:)` survives as the DEBUG cross-check.
Deleting it outright would strand its test suite and scatter the `.noFood` rule into the decoder.

---

## 11. Regions need no conversion — and the old initializer must go

**Decision**: decode `region` straight into the existing `FoodRegion(clampingX:y:width:height:)`.
Delete `FoodRegion.init(geminiTop:left:bottom:right:)` and the six tests that cover it.

**Rationale**: the server sends proportions in `0...1` from the top-left, which is exactly what
`FoodRegion` stores — the 0–1000 scaling and the y-first axis order are now the server's problem.
The clamping initializer already handles edges slightly outside the frame and already rejects
degenerate rects, so FR-015 and FR-016 are satisfied by reuse, not new code.

Deleting the old initializer is not tidiness, it is FR-009 and Principle I: left in place it is
dead code that still compiles, and its tests would keep passing while testing a path no request
can reach — coverage that measures nothing. The clamping tests stay; only the `gemini*` cases go.

---

## 12. What gets deleted

`GeminiCalorieService.swift` (prompt, response schema, `maxOutputTokens`, base64 encoding, the
`GeminiEnvelope`/`FoodPayload` DTOs), `AppSecrets.swift`, the `GeminiAPIKey`/`GeminiModel` keys in
`Info.plist`, both `GEMINI_*` settings in the xcconfig pair, `FoodRegion.init(geminiTop:…)`, and
the tests asserting provider-request properties (`testSchemaRequiresBoxForEveryFood`,
`testSchemaBoxDeclaresFourRequiredIntegerEdges`, `testOutputTokenCeilingIsSetAndGenerous`).

**No fallback path is kept** (FR-009). A build with a blank or unreachable address fails every
analysis with the generic service message — it does not quietly call a provider directly, which
would reintroduce the key this feature exists to remove.

**Also required**: revoke the Gemini key at the provider once the backend is live. The key was
never committed — `Config/Secrets.xcconfig` is git-ignored (`.gitignore:25`) and untracked — but
it has been embedded in every build made so far, and an API key inside a distributed binary is
extractable. Deleting it from the project does not make the key stop working; only revoking does.
Tracked as a task, not left as a comment (Principle I).
