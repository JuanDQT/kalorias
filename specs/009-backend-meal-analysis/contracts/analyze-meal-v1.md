# Contract: `analyzeMeal` v1, as the app consumes it

**Feature**: `009-backend-meal-analysis` | **Date**: 2026-08-01

The app's side of the agreement. The backend's own contract is the authority; this file records
what the client must send, what it must tolerate, and which properties are asserted by tests.
Source: [backend-integration-brief.md](../backend-integration-brief.md).

---

## Request

```
POST {BASE_URL}/api/v1/kalorias/analyzeMeal
Content-Type: multipart/form-data; boundary=<generated per request>

--<boundary>
Content-Disposition: form-data; name="photo"; filename="meal.jpg"
Content-Type: image/jpeg

<JPEG bytes>
--<boundary>--
```

| Property | Value | Why it matters |
|---|---|---|
| Field name | `photo`, exactly | Any other name returns `422` complaining the photo is missing |
| Format | JPEG only | HEIC/PNG from the library must be converted first |
| Size | ≤ 8 MB; app targets ≤ 7.5 MB | The margin covers multipart overhead |
| `Content-Type` | Set once, with the generated boundary | Hardcoding it, or a boundary mismatch, produces a `422` that reads like a server bug |
| Auth | **None** | Sending an `Authorization` header is a defect, not a precaution |
| Other parameters | **None** | No prompt, model, schema or token limit — the server owns all of it |
| Timeout | 35 s inactivity, 60 s total | The server itself waits up to 30 s for the model |
| Caching | None | Ephemeral session; the server also sends `Cache-Control: no-store, private` |

---

## Response `200`

```json
{
  "data": {
    "foodDetected": true,
    "totalCalories": 615,
    "foods": [
      { "name": "Arroz blanco", "calories": 205, "protein": 4.3, "carbs": 44.5, "fat": 0.4,
        "region": { "x": 0.12, "y": 0.31, "width": 0.4, "height": 0.28 } },
      { "name": "Pechuga de pollo", "calories": 410, "protein": 62.0, "carbs": 0, "fat": 16.2,
        "region": null }
    ]
  }
}
```

**No food** — also a `200`, and not an error:

```json
{ "data": { "foodDetected": false, "totalCalories": 0, "foods": [] } }
```

### The four things that are easy to get wrong

1. **The `data` envelope.** The payload is not at the root. Decoding straight into the payload
   fails every single response.
2. **`region` is already in proportions `0...1`, origin top-left.** It is *not* the provider's
   `{ymin, xmin, ymax, xmax}` on a 0–1000 scale. **Do not divide by 1000. Do not reorder the
   axes.** Swapping x and y raises no error — it silently crops the wrong part of the photo, and
   the result looks plausible. Because they are proportions they apply unchanged to the stored,
   downsized photo, with no offset.
3. **`null` macros are not `0`.** `null` means the analysis did not report it; `0` means the food
   has none. They must look different in the UI (`—` vs `0 g`).
4. **`region: null` is normal.** The food keeps its name, calories and macros; it loses only its
   thumbnail. Never drop a food for lacking a region.

`totalCalories` arrives already computed and is the source of truth (FR-012).

---

## Errors

| Status | Meaning | App outcome | Retry? |
|---|---|---|---|
| `422` | Photo missing, not JPEG, or over 8 MB. Body: `{"message": "…", "errors": {"photo": ["…"]}}` in Spanish | `.photoRejected` | No — retake |
| `413` | Body larger than the web server accepts; may carry no JSON | `.photoRejected` | No — retake |
| `429` | Rate limit (10/min, 100/day per IP). Carries `Retry-After` | `.rateLimited(retryAfter:)` | Yes, after the countdown |
| `503` | `{"message": "El servicio de análisis no está disponible…"}` | `.serviceError` | Manual only |
| other `5xx` / unexpected | — | `.serviceError` | Manual only |
| `200` with unreadable body | — | `.invalidResponse` | Manual only |

**`503` is deliberately opaque.** It covers a provider that is down, slow, out of quota, missing
or invalid credentials, and a truncated or unreadable model reply. The app must not try to infer
which — the cause is in the server's log, where it can actually be acted on.

**The server's message text is never displayed** — it is Spanish-only and the app is bilingual. It
goes to the log with the request id (FR-021a).

---

## `X-Request-Id`

Present on every response. Logged with the outcome, never shown in the UI. It is what makes a user
report traceable in the server's logs, and it is the only thing that can identify a `503`.

---

## Asserted by tests

| # | Property | Where |
|---|---|---|
| A1 | Body has one part named `photo`, correct boundary, CRLF, closing delimiter | `MultipartFormDataTests` |
| A2 | Full success payload decodes: names, calories, macros, regions | `AnalyzeMealResponseTests` |
| A3 | `data` envelope required — a root-level payload is `.invalidResponse` | `AnalyzeMealResponseTests` |
| A4 | `region` proportions map **unscaled**, x→x and y→y | `AnalyzeMealResponseTests` |
| A5 | `region: null`, malformed, or degenerate ⇒ food kept, region `nil` | `AnalyzeMealResponseTests` |
| A6 | `null` macros stay `nil`, distinct from `0` | `AnalyzeMealResponseTests` |
| A7 | `foodDetected: false` and empty `foods` ⇒ `.noFood` | `AnalyzeMealResponseTests` |
| A8 | Missing `name`/`calories`, negative calories, garbage ⇒ `.invalidResponse` | `AnalyzeMealResponseTests` |
| A9 | Reported total is used verbatim, including when it differs from the sum | `AnalyzeMealResponseTests` |
| A10 | Status → outcome for 200/422/413/429/503/418/500 | `RemoteCalorieServiceTests` |
| A11 | `Retry-After` seconds, HTTP-date, absent, garbage, negative, huge | `RetryCooldownTests` |
| A12 | Unknown extra fields are ignored | `AnalyzeMealResponseTests` |
