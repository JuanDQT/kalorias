# Quickstart & Validation: Meal Analysis Moves to the Kalorias Backend

**Feature**: `009-backend-meal-analysis` | **Date**: 2026-08-01

Types and rules in [data-model.md](./data-model.md); the wire agreement in
[contracts/analyze-meal-v1.md](./contracts/analyze-meal-v1.md); screen behaviour in
[contracts/ui-contracts.md](./contracts/ui-contracts.md); the reasoning in
[research.md](./research.md).

> **You can validate this feature without the real backend.** A local stub covering every status
> code is faster and more complete than a live server, which cannot be made to return `429` and
> `503` on demand. §3 gives one.

---

## 1. Prerequisites

- Xcode 26.6+, iOS 26.5 target, Swift 6 strict concurrency, scheme `Kalorias`
- A Kalorias server, or the stub in §3
- New `.swift` files under `Kalorias/` are auto-included; **new test files need a
  `project.pbxproj` entry** or they silently never run — a test count that does not grow is the
  symptom

## 2. Configure the address

`Config/Secrets.xcconfig` is git-ignored and already the base configuration for both Debug and
Release. Replace its Gemini settings with:

```
SLASH = /
KALORIAS_API_BASE_URL_Debug   = http:$(SLASH)$(SLASH)localhost:8000
KALORIAS_API_BASE_URL_Release = https:$(SLASH)$(SLASH)www.quispe.com
KALORIAS_API_BASE_URL = $(KALORIAS_API_BASE_URL_$(CONFIGURATION))
```

> **`$(SLASH)` is not decoration.** In an xcconfig file `//` starts a comment *inside a value*, so
> a literal `https://www.quispe.com` becomes `https:` — a URL that parses and resolves to nothing,
> producing a generic service error with no clue why. `AppConfigurationTests` exists to catch
> exactly this.

Mirror the same three lines (with placeholder hosts) into the tracked
`Config/Secrets.example.xcconfig`, which must contain **no key and no real host**.

**On a physical device**, `localhost` is the phone, not your Mac. Use the Mac's LAN address —
`http://192.168.x.x:8000` — which is why `NSAllowsLocalNetworking` is in the Info.plist.

## 3. A stub server that can fail on demand

```bash
mkdir -p /tmp/kalorias-stub && cd /tmp/kalorias-stub
cat > stub.py <<'PY'
from http.server import BaseHTTPRequestHandler, HTTPServer
import json, sys, uuid

MODE = sys.argv[1] if len(sys.argv) > 1 else "ok"

BODIES = {
 "ok": (200, {"data": {"foodDetected": True, "totalCalories": 615, "foods": [
     {"name": "Arroz blanco", "calories": 205, "protein": 4.3, "carbs": 44.5, "fat": 0.4,
      "region": {"x": 0.12, "y": 0.31, "width": 0.4, "height": 0.28}},
     {"name": "Pechuga de pollo", "calories": 410, "protein": 62.0, "carbs": 0, "fat": 16.2,
      "region": None}]}}),
 "nofood": (200, {"data": {"foodDetected": False, "totalCalories": 0, "foods": []}}),
 "nomacros": (200, {"data": {"foodDetected": True, "totalCalories": 300, "foods": [
     {"name": "Plato sin macros", "calories": 300, "protein": None, "carbs": 0,
      "fat": None, "region": None}]}}),
 "422": (422, {"message": "La foto no es válida.", "errors": {"photo": ["Debe ser JPEG."]}}),
 "429": (429, {"message": "Demasiadas peticiones."}),
 "503": (503, {"message": "El servicio de análisis no está disponible. Inténtalo de nuevo más tarde."}),
 "garbage": (200, {"nope": True}),
}

class H(BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        status, body = BODIES[MODE]
        raw = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store, private")
        self.send_header("X-Request-Id", str(uuid.uuid4()))
        if status == 429:
            self.send_header("Retry-After", "20")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)
    def log_message(self, *a): pass

print(f"stub mode={MODE} on :8000")
HTTPServer(("0.0.0.0", 8000), H).serve_forever()
PY
python3 stub.py ok      # swap "ok" for nofood | nomacros | 422 | 429 | 503 | garbage
```

Verify it independently before blaming the app:

```bash
curl -s -X POST http://localhost:8000/api/v1/kalorias/analyzeMeal -F "photo=@plato.jpg" | jq .
```

## 4. Build & test

```bash
xcodebuild -project Kalorias.xcodeproj -scheme Kalorias \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build 2>&1 | tail -20

xcodebuild -project Kalorias.xcodeproj -scheme Kalorias \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test 2>&1 | tail -30
```

**Expected**: `BUILD SUCCEEDED`, zero warnings, `TEST SUCCEEDED`.

The count moves in three directions at once, so check it deliberately: **22 functions are deleted**
(all 16 in `CalorieAnalysisDecodingTests`, plus 6 `gemini*` cases in `FoodRegionTests`), **13 of
them reappear** in `AnalyzeMealResponseTests` covering the same behaviours against the new
contract, and the six new suites add the rest. Only **9 behaviours genuinely disappear**: the 3
provider-request assertions and the 6 obsolete 0–1000 region conversions.

Every other pre-existing test must still pass **unmodified** — that is the evidence the domain
layer really was decoupled.

## 5. Required unit coverage

| Suite | Cases | Contract |
|---|---|---|
| `MultipartFormDataTests` | field name is `photo`; boundary in header matches body; CRLF endings; closing `--boundary--`; image bytes unaltered | A1, M1–M5 |
| `AnalyzeMealResponseTests` | full payload; `data` envelope required; regions unscaled x→x/y→y; `region: null`, malformed, degenerate; `null` vs `0` macros; no-food both ways; missing name/calories; negative calories; garbage; reported total ≠ sum; unknown fields ignored | A2–A9, A12, D1–D8 |
| `RemoteCalorieServiceTests` | 200/422/413/429/503/500/418 → outcome; missing base URL ⇒ `.serviceError`; no `Authorization` header sent; request id captured; session config asserts `timeoutIntervalForRequest == 35`, `timeoutIntervalForResource == 60`, `urlCache == nil` | A10, E1–E4, C1, FR-004/005/006 |
| `RetryCooldownTests` | `Retry-After` seconds; HTTP-date; absent; garbage; negative; 99999 clamped; `secondsRemaining` rounds up, floors at 0 | A11, R1–R6 |
| `AnalysisPhotoEncoderTests` | longest side ≤ 1024; no upscaling; output is JPEG; result under the cap; PNG/HEIC source converts | P1–P6 |
| `AppConfigurationTests` | configured value is an absolute URL with scheme **and host** (the `//` guard); blank ⇒ `nil` | C3 |
| `CalorieAnalysisStoreTests` *(mod)* | `.rateLimited` starts a cooldown; `retry()` is a no-op while cooling; zero re-enables; `cancel()` cancels both; `.photoRejected` never retries | S1–S6 |

**No test may sleep, hit the network, or read the wall clock.** Time is injected; the network is a
`URLProtocol` stub.

## 6. Manual validation

Run the stub in each mode and take one photo per row.

| # | Stub mode | Expected on screen | Requirement |
|---|---|---|---|
| 1 | `ok` | Total **615**, two foods, thumbnail cropped for the first, none for the second, macros shown | US1, FR-012/13/15/16 |
| 2 | `nomacros` | The `0` carbs reads `0 g`; the absent protein and fat read `—`, **not** `0 g` | FR-014 |
| 3 | `nofood` | The no-food state with **Retake** — not an error. Nothing appears in History | US2, FR-011 |
| 4 | `422` | "That photo can't be analyzed…" with **Retake**, not Retry. No Spanish text in an English UI | US3, FR-019, FR-021a |
| 5 | `429` | "Too many analyses…", retry **disabled**, counting down from 20, re-enabled in place at 0 | FR-020 |
| 6 | `503` | Generic unavailable message + Retry. No provider name, no model, no status code | FR-022 |
| 7 | `garbage` | Generic failure + Retry. Never a partial result | FR-017 |
| 8 | stub stopped | Same generic failure — never a crash, never a Gemini call | C1, FR-009 |
| 9 | Airplane mode | Connection error + Retry | US3 |
| 10 | *(no stub)* an image the encoder cannot fit under the cap | The rejected-photo state with **Retake** — the flow must not dismiss silently | data-model S7–S9, FR-023 |

For every failure row: **no calorie number on screen and no new History entry** (FR-023, FR-024).

Repeat rows 1, 4 and 5 in **Spanish** and in **dark mode**, and row 5 at an accessibility Dynamic
Type size — the countdown is the one new string that grows and must not truncate its button
(Principle VI).

## 7. Verifying the things that fail silently

**Regions (SC-003)** — an axis swap or a stray ÷1000 raises no error; it crops the wrong part of a
plausible-looking photo. Photograph a plate where two foods sit in clearly different corners and
confirm each thumbnail shows *its own* food. Do this on at least 10 photos. A region test passing
is not evidence here; the crop on screen is.

**No credential left (SC-001)** — must return nothing:

```bash
grep -ril "gemini\|generativelanguage\|GEMINI_API_KEY\|x-goog-api-key" \
  --include="*.swift" --include="*.plist" --include="*.xcconfig" Kalorias/ KaloriasTests/ Config/

strings "$(xcodebuild -project Kalorias.xcodeproj -scheme Kalorias -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2}')/Kalorias.app/Kalorias" \
  | grep -i "generativelanguage\|goog-api-key"
```

**The request id (US4)** — `xcrun simctl spawn booted log stream --predicate 'category == "analysis"'`
while running row 6. The id must appear in clear, not as `<private>`, and no photo or food name
may appear anywhere in the stream.

**Photo size (SC-006)** — on a physical device, capture at full resolution and confirm the upload
is a few hundred KB, not megabytes, and that the server never answers `422`.

## 8. Before merge

- [ ] `Config/Secrets.example.xcconfig` contains no key and no real host
- [ ] `GeminiAPIKey` / `GeminiModel` gone from `Config/Info.plist`
- [ ] `GeminiCalorieService.swift` and `AppSecrets.swift` deleted, not orphaned
- [ ] `FoodRegion.init(geminiTop:…)` deleted along with its six tests
- [ ] The 6 new test files are registered in `project.pbxproj` and actually ran
- [ ] **The Gemini API key is revoked at the provider** — deleting it from the project does not
      stop it working, and it has shipped inside every build made so far
- [ ] `/speckit-constitution` scheduled: Product Overview and External Services still name Gemini
      as the app's direct dependency
