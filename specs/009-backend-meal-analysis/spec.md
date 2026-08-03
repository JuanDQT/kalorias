# Feature Specification: Meal Analysis Moves to the Kalorias Backend

**Feature Branch**: `009-backend-meal-analysis`

**Created**: 2026-08-01

**Status**: Draft

**Input**: User description: "Siguiendo este documento de desktop kalorias-app-integracion.md quiero que lo hagamos en este specify. resumen, la logica de comunciacion con gemini ahora la hace backend"

**Source brief**: [`backend-integration-brief.md`](./backend-integration-brief.md) — the integration
document handed to the app team. The backend contract it links (`analyzeMeal` v1) is the authority
whenever this spec and the brief disagree.

## Context

Until now the app carried the AI provider's API key inside its binary and talked to the provider
directly: it built the prompt, the response schema and the image payload, and it converted the
provider's bounding boxes into the app's own coordinates.

From this feature on, **the Kalorias server is the only party that talks to the AI provider**. The
app sends one photo to a Kalorias endpoint and receives an already-normalized analysis. The
provider, the model, the prompt, the schema and the box conversion all stop being the app's
business — and stop being in the app's binary.

This is a re-plumbing of an existing flow: from the user's point of view, taking a photo and
getting calories must work exactly as it does today, only without a key shipped in the app.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Get calories from a photo, with no key in the app (Priority: P1)

Someone photographs their meal (or picks one from the library) and gets the same calorie and macro
breakdown they get today, with each recognized food showing its thumbnail crop. The difference is
invisible to them: the estimate now comes from the Kalorias service instead of from a provider the
app called itself.

**Why this priority**: This is the app's core flow and the whole point of the migration. Without
it there is no product; everything else in this feature is error handling around it.

**Independent Test**: Point the app at a Kalorias service, photograph a plate, and confirm the
result screen shows the same kinds of values (total, per-food calories, macros, thumbnails) as
before, and that the app binary no longer contains any AI-provider credential.

**Acceptance Scenarios**:

1. **Given** a photo of a plate with several foods, **When** the analysis completes, **Then** the
   result screen shows each food with its name and calories, and a total that matches the value
   the service reported.
2. **Given** a food the service located in the photo, **When** the details screen is shown,
   **Then** that food's thumbnail is cropped from the correct part of the photo — the same region
   the service reported, with no axis swap and no rescaling.
3. **Given** a food the service could not locate (no region), **When** the result is shown,
   **Then** that food still appears with its name, calories and macros, and only its thumbnail is
   missing.
4. **Given** a food whose protein / carbs / fat the analysis did not provide, **When** its macros
   are shown, **Then** the missing values are visibly distinct from a reported zero.
5. **Given** a successful analysis, **When** the meal is saved to history, **Then** it is saved
   exactly as it is today, with photo, foods, macros and regions.

---

### User Story 2 - A photo with no recognizable food is not a failure (Priority: P1)

Someone photographs something that is not food, or a plate the service cannot recognize. The app
tells them nothing was recognized and offers to retake — it does not show an error.

**Why this priority**: Ships with Story 1 by necessity: the service returns "no food" as a normal
successful answer, so treating it as an error would be an immediate regression of behaviour the
app already has today.

**Independent Test**: Photograph a blank wall and confirm the app shows the existing "no food
recognized" state with its retake action, not an error message.

**Acceptance Scenarios**:

1. **Given** the service reports no food was recognized, **When** the analysis completes, **Then**
   the app shows the no-food state, not an error, and offers to retake.
2. **Given** the no-food state, **When** it is shown, **Then** no meal is saved to history.

---

### User Story 3 - Failures explain themselves and the user can recover (Priority: P2)

When the analysis cannot be delivered — no connection, the service is unavailable, too many
requests, or the photo was rejected — the user gets a clear message in their language and a way
forward (retry, or take another photo). No failure ever shows a calorie number, and no failure
ever leaks who the AI provider is.

**Why this priority**: The happy path is testable without it, but the app is unusable in the field
without honest failure states. It is also where this migration adds genuinely new cases (rate
limiting, photo rejection) that did not exist when the app called the provider directly.

**Independent Test**: Exercise each failure the service can return, plus a dead network, and
confirm each produces its own actionable message with a retry or retake action, and no numbers.

**Acceptance Scenarios**:

1. **Given** the device has no network connection, **When** an analysis is attempted, **Then** the
   app shows the connection error with a retry action.
2. **Given** the service reports it is temporarily unavailable, **When** the analysis fails,
   **Then** the app shows a "try again later" message with a retry action, and the message does
   not name any AI provider, model, or upstream cause.
3. **Given** the user has exceeded the allowed number of analyses, **When** the analysis fails,
   **Then** the app states how long they must wait, counts that wait down, and keeps the retry
   action unavailable until it reaches zero.
4. **Given** a countdown from a request limit is running, **When** it reaches zero, **Then** the
   retry action becomes available again without the user having to leave and re-enter the screen.
5. **Given** the service reports a limit but no wait time, **When** the message is shown, **Then**
   the app still refuses to retry immediately and applies its own short wait.
6. **Given** the service rejects the photo itself, **When** the analysis fails, **Then** the app
   asks for a different photo rather than offering to retry the same one.
7. **Given** any failure state, **When** it is shown, **Then** no calorie total is displayed and
   nothing is saved to history.
8. **Given** the analysis takes longer than the app is willing to wait, **When** the wait expires,
   **Then** the app shows the timeout message with a retry action.

---

### User Story 4 - A reported problem can be traced (Priority: P3)

When an analysis fails on a device the maintainer can inspect, the failure can be matched to the
exact request in the server's logs, because the app wrote the identifier the service returned into
the device's diagnostic log.

**Why this priority**: Pure operability, and deliberately the cheap version of it. Nothing
user-facing depends on it, but without it a temporarily-unavailable service is untraceable, since
the service reveals no cause by design.

**Independent Test**: Force a failing analysis and confirm the request identifier the service
returned appears in the device's diagnostic log, attached to that failure.

**Acceptance Scenarios**:

1. **Given** any response from the service, **When** it carries a request identifier, **Then** the
   app writes that identifier to the diagnostic log alongside the outcome.
2. **Given** a failed analysis, **When** the identifier is logged, **Then** the log entry contains
   no photo and no personal data.
3. **Given** any analysis outcome, **When** it is shown to the user, **Then** the request
   identifier is not part of the interface.

---

### Edge Cases

- **Photo larger than the service accepts.** A full-resolution capture can exceed the service's
  size limit. The app must send a photo within the limit rather than letting the user discover it
  as a rejection.
- **Photo that is not in the accepted format.** Whatever the source (camera or library, including
  formats like HEIC or PNG), the app must convert before sending; the service accepts only JPEG.
- **The service is reachable but answers something the app cannot read.** Treated as a service
  failure with a retry action — never as a partial result.
- **A successful answer whose total does not match the sum of its foods.** The reported total is
  the value the user sees; the app does not silently substitute its own arithmetic.
- **A food region that reaches outside the photo's edges.** The thumbnail is cropped to the photo;
  the food is not discarded.
- **The user cancels while the analysis is in flight.** The in-flight request is abandoned and
  nothing is shown or saved, exactly as today.
- **The user retries repeatedly and hits the request limit.** The app respects the wait the
  service asks for instead of hammering it.
- **The app is pointed at a service address that does not exist or is misconfigured.** Every
  analysis fails with the generic service message; the app never falls back to calling an AI
  provider directly.
- **A response arrives after the app stopped waiting.** It is discarded; the timeout state stands.

## Requirements *(mandatory)*

### Functional Requirements

#### Talking to the service

- **FR-001**: The app MUST obtain every meal analysis by sending the photo to the Kalorias
  analysis service, and MUST NOT contact any AI provider directly.
- **FR-002**: The app MUST send exactly one photo per analysis and no other analysis parameters —
  no prompt, no schema, no model selection, no token limits.
- **FR-003**: The app MUST send the photo in the single format the service accepts (JPEG) and
  within the service's maximum size (8 MB), converting and downscaling as needed before sending.
- **FR-004**: The app MUST NOT send authentication credentials to the service; the service
  requires none.
- **FR-005**: The app MUST wait at least 35 seconds for an answer before treating an analysis as
  timed out, because the service itself may wait up to 30 seconds for the model.
- **FR-006**: The app MUST NOT cache analysis responses.
- **FR-007**: The address of the analysis service MUST be configurable per build configuration —
  a development build reaching a server on the developer's own machine, a release build reaching
  production — and switching between them MUST NOT require a code change.
- **FR-007a**: The release build MUST only reach the service over an encrypted connection. Any
  exemption allowing an unencrypted connection MUST apply to local development addresses alone and
  MUST NOT be present in the released app.

#### Removing the old integration

- **FR-008**: The app MUST NOT contain an AI-provider API key, in the binary, in the project
  configuration, or in the repository, and the configuration files and documentation that
  described one MUST be removed or repurposed for the service address.
- **FR-009**: The prompt, response schema, output-token limit, image encoding and provider
  envelope handling MUST be deleted from the app; the app MUST NOT retain a direct-to-provider
  path as a fallback.
- **FR-010**: Tests that asserted properties of the provider request (schema shape, token ceiling,
  provider envelope) MUST be removed or replaced by tests of the new service contract, leaving no
  test that would pass only because dead code still exists.

#### Reading the answer

- **FR-011**: A successful answer MUST be presented as either a food-bearing analysis or a
  "no food recognized" outcome; the latter MUST NOT be shown as an error and MUST NOT be saved to
  history.
- **FR-012**: The total the app displays and saves MUST be the total the service reported, not a
  value the app recomputes.
- **FR-013**: Each food MUST carry its name and calories; a food MUST NOT be discarded for lacking
  a region or lacking macros.
- **FR-014**: A missing macro value MUST remain distinguishable from a reported zero, in the UI,
  in what is saved, and in what is later shown from history.
- **FR-015**: Food regions MUST be used as the service reports them — proportions of the photo's
  width and height, measured from the top-left corner — with no division by any scale factor and
  no reordering of axes.
- **FR-016**: A region that cannot yield a usable crop MUST cost only that food's thumbnail, never
  the food itself and never the meal.
- **FR-017**: An answer the app cannot read MUST produce a failure state, never a partial or
  half-populated result.

#### Failing well

- **FR-018**: The app MUST distinguish at least these outcomes for the user: no connection,
  timeout, service unavailable, request limit reached, and photo rejected.
- **FR-019**: A rejected photo MUST be presented as "use a different photo" and MUST NOT be
  retried automatically with the same photo.
- **FR-020**: When the service reports the request limit was reached, the app MUST show the wait
  the service asked for, count it down as it elapses, and keep the retry action unavailable until
  it reaches zero — at which point retry MUST become available again without leaving the screen.
- **FR-020a**: If the service reports a limit without stating a wait, the app MUST apply its own
  wait rather than allowing an immediate retry.
- **FR-021**: All user-facing failure messages MUST be available in every language the app
  supports, and MUST NOT be shown in a language the user did not choose.
- **FR-021a**: The message text the service itself returns MUST NOT be shown to the user; the app
  shows its own localized message for every failure. The service's text may be logged.
- **FR-022**: No failure message MUST reveal the AI provider, the model, or any upstream error
  text or code.
- **FR-022a**: The app MUST NOT retry a failed analysis on its own. Every retry MUST come from the
  user acting on the retry control.
- **FR-023**: Every failure state MUST offer a way forward — retry for transient failures, retake
  for a rejected photo — and MUST NOT display a calorie value.
- **FR-024**: A failed or cancelled analysis MUST NOT be saved to history.

#### Support

- **FR-025**: The app MUST write the request identifier the service returns to the device's
  diagnostic log alongside each analysis outcome, so a failure inspected on a device can be traced
  in the server's logs.
- **FR-026**: Log entries MUST NOT include the photo or any personal data.
- **FR-027**: The request identifier MUST NOT appear anywhere in the user interface.

### Key Entities

- **Analysis request**: one photo, in the accepted format and within the size limit. Carries
  nothing else.
- **Analysis result**: whether food was recognized, the total calories, and the list of recognized
  foods. Replaces the provider-shaped payload the app used to parse.
- **Recognized food**: a name, calories, optionally each of protein / carbs / fat in grams, and
  optionally the region of the photo it occupies. "Optional" here means genuinely absent, not zero.
- **Food region**: the part of the photo a food occupies, expressed as proportions of the photo's
  width and height from the top-left corner. Unchanged in meaning from today; only its source
  changes.
- **Analysis failure**: the reason an analysis produced no result, chosen from the set the user
  can act on, plus the request identifier for support.
- **Service address**: the per-build location of the Kalorias analysis service.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Zero AI-provider credentials are present in the shipped app: a search of the built
  app and of the repository for provider keys, provider hostnames and model identifiers returns
  nothing.
- **SC-002**: 100% of successful analyses show a total equal to the sum of the foods listed on
  screen, as verified against the service's own answer.
- **SC-003**: For a set of at least 10 test photos with located foods, every thumbnail crops the
  correct food — no axis-swapped or scale-shifted crops.
- **SC-004**: Every failure the service can return, plus a disconnected device and a stalled
  request, produces a distinct, actionable message in both supported languages: 100% coverage of
  the failure set, verified case by case.
- **SC-005**: No failure path anywhere in the flow displays a calorie number or saves a meal.
- **SC-006**: A photo taken at the device's full resolution is accepted by the service on the
  first attempt — 0 rejections for size or format across the supported capture and library
  sources.
- **SC-007**: The end-to-end wait from taking the photo to seeing a result is no worse than the
  current app's on the same network, measured as a median over at least 10 runs.
- **SC-008**: A maintainer with access to a device that just failed an analysis can locate the
  matching server-side record from the device's diagnostic log alone, with no extra instrumentation.
- **SC-009**: The saved history of an analysis is indistinguishable in content from what the
  previous integration saved for an equivalent photo — same foods, same macros (including absent
  ones), same regions.

## Assumptions

- **The service exists and its contract is fixed.** This feature covers only the app side; the
  endpoint, its behaviour and its versioning are the backend's responsibility, per the linked
  contract.
- **The service address is supplied per build configuration**, in the same way the provider key
  was supplied before — a build-time setting outside version control, not a hardcoded literal and
  not something the user types. Two addresses: a development build points at a server running on
  the developer's own machine (`http://localhost:8000`), a release build at production
  (`www.quispe.com` stands in until the real deployment exists).
- **The development address is not encrypted.** A server on the developer's own machine is reached
  over plain HTTP, which iOS blocks by default. The exemption must be scoped to local development
  only and must never widen to the release build, whose address is always encrypted.
- **A missing or unreachable address fails like any other service failure.** A build whose address
  was never filled in, or a development machine with no server running, shows the generic
  "unavailable" message — there is no separate "you forgot to configure it" state for users, only
  a developer-visible one.
- **The photo is downscaled before sending**, to a size well inside the 8 MB limit. The service
  works from a copy whose longest side is 1024 points, so sending more resolution than that buys
  no accuracy and only costs upload time on a phone connection.
- **Every user-facing message is the app's own, not the service's.** The service returns Spanish
  text; the app supports Spanish and English, so an English-speaking user would otherwise be shown
  Spanish. The service's text goes to the log instead. This costs some specificity about *why* a
  photo was rejected, which is acceptable because the app controls the format and size it sends —
  a rejection means the app has a bug, not that the user chose a bad photo.
- **Retrying is always the user's decision.** No failure triggers an automatic retry, so no
  failure can silently consume the request budget or double the user's wait while the service is
  genuinely down.
- **"Too large a request" and "photo rejected" are one outcome for the user.** They differ only in
  which layer refused; the user's action is the same — use a different photo.
- **No offline queue.** An analysis attempted without a connection fails and is retried by the
  user; queuing meals for later analysis is out of scope.
- **No change to capture, history, progress or the design system.** Photo capture, framing, zoom,
  the library picker, persistence and every screen keep their current behaviour; only the source
  of the analysis changes.
- **Rate limiting is per IP, not per user**, so several people on one network share a budget. The
  app cannot detect this and simply reports the limit honestly.

## Dependencies

- A reachable Kalorias analysis service (`analyzeMeal` v1) for development, testing and production.
- The project constitution's **Product Overview** and **External Services** sections still name
  the AI provider as the app's direct dependency. They describe the world before this feature and
  must be amended once it lands: the app's one external service becomes the Kalorias backend.
