# Quickstart & Validation: Fix Analysis Reliability, Ingredient Thumbnails & Bottom-Bar Clearance

**Feature**: `007-fix-scroll-and-boxes` | **Date**: 2026-07-26

Signatures in [contracts/ui-contracts.md](./contracts/ui-contracts.md); the measurements behind every
decision in [research.md](./research.md).

> **Read §"Verifying clearance" before validating US3.** Feature 006 shipped broken because its
> verification could not fail. Two specific methods are banned here for that reason.

---

## Prerequisites

- Xcode 26.6+, iOS 26.5 target, Swift 6 strict concurrency
- Scheme `Kalorias`; simulator **iPhone 17 Pro Max**
- A Gemini key in `Config/Secrets.xcconfig` as `GEMINI_API_KEY` — already present and verified
  reaching the app via the generated Info.plist. Needed for US1/US2 live validation only.

New `.swift` files under `Kalorias/` are auto-included; **new test files need a `project.pbxproj`
entry** or they silently never run (a test count that does not grow is the symptom).

---

## Build & test

```bash
xcodebuild -project Kalorias.xcodeproj -scheme Kalorias \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build 2>&1 | tail -20

xcodebuild -project Kalorias.xcodeproj -scheme Kalorias \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test 2>&1 | tail -30
```

**Expected**: `BUILD SUCCEEDED`, zero warnings; `TEST SUCCEEDED` with the **158** existing tests
still green plus the new schema assertions. This feature changes no nutrition behaviour, so any
regression in features 001–006 is a real defect.

> Simulator `... Busy` on launch → `xcrun simctl boot "iPhone 17 Pro Max" && xcrun simctl bootstatus "iPhone 17 Pro Max" -b`

---

## Required unit coverage

Small and targeted — this is a defect fix, and the tests exist to stop these two defects returning.

| Case | Asserts | Contract |
|---|---|---|
| **Schema marks `box` required** | `"box"` is in `foods.items.required` — the precise thing whose absence caused the outage | A1 / FR-001 |
| `box` property shape unchanged | four required integer edges, `ymin`/`xmin`/`ymax`/`xmax` | A2 |
| `maxOutputTokens` present and sane | set, and comfortably above a realistic reply | A3 / FR-003 |
| Reply with no `box` still parses | that food's `region == nil`, meal intact | A4 / FR-005 |
| Reply with malformed `box` still parses | whole meal parses, region `nil` | A5 / FR-005 |
| Truncated/garbage reply | existing analysis error; nothing saved | A6 / FR-004 |
| All existing decoding cases | unchanged | A7 / FR-016 |

**Test A1 and A4/A5 as separate cases.** They encode the two halves of FR-006 — demand the box in the
request, tolerate its absence in the parser. Feature 006 traded one for the other; separate tests make
that trade impossible to make silently.

---

## Verifying clearance (US3) — method matters

### ❌ Banned: content that fits on one screen

Feature 006 was validated with three ingredients. The content ended above the bar on its own, which
says nothing about whether the scrollable range extends past it. **This produced a false pass.**

### ❌ Banned: `.defaultScrollAnchor(.bottom)`

Tried twice, gave contradictory readings, and in one run showed rows 1–9 with the tenth never
visible. It does not reliably land at the true maximum offset.

### ✅ Required: a real scroll to the last element

Either scroll **by hand** on the simulator/device to the very end, or drive it programmatically:

1. Seed a meal with **enough ingredients to require scrolling** (10 is comfortable), give the last one
   a distinctive name such as `ULTIMO`.
2. Reach the details screen **through the real navigation path** (tap the row in the History list, or
   push via the router) — *not* by rendering `MealDetailsView` directly. Rendering it directly bypasses
   the `NavigationStack` whose inset-swallowing is the entire bug.
3. Scroll to the last row (a temporary `scrollPosition(id:)` binding set to the last food's id works,
   and is how the fix was measured).
4. Screenshot and confirm the last row is **fully** visible — name, calorie figure and macro strip all
   readable, none of it under the bar.

Optional numeric check, useful if the screenshot is ambiguous: print the last row's global
`frame(in: .global).maxY` and compare it against the bar's top edge.

---

## Manual validation

### V1 — Clearance on all three screens (US3)

1. **Meal details**: with a scrollable meal, scroll to the end → last ingredient fully visible.
2. While scrolling, content passes **behind** the translucent bar; the bar has not moved or become
   opaque.
3. Details that fit without scrolling → nothing overlapped.
4. **History list**: scroll to the last row → fully visible.
5. **Progress tab**: scroll to the end → last widget fully visible, and **no conspicuous empty gap**
   above the bar (a gap means something is inset twice).
6. Repeat at the largest Dynamic Type size and in landscape — the last row must still clear.

### V2 — Analysis reliability (US1) ⚠️ the regression that matters most

1. Analyze **at least 5 varied food photos**, including one busy plate with several distinct foods.
2. **Expect**: every analysis completes and saves its meal with correct calories and macros.
3. **Expect**: no analysis fails with a truncated or unreadable reply.
4. Cross-check a couple of totals against the ingredient sums shown on the details screen.
5. Deliberately analyze something with **no** food → the existing "no food" outcome, unchanged.

### V3 — Thumbnails on new meals (US2)

1. Open the details of a meal analyzed after this fix.
2. **Expect**: most ingredient rows show a crop of your own photo, not the placeholder.
3. **Expect**: any food the model could not localize shows the placeholder, mixed among cropped rows.
4. **Expect**: the screen appears immediately; thumbnails may fill in a moment later.

### V4 — Axis orientation (US2) ⚠️ use an asymmetric photo

1. Photograph foods in **clearly different corners** — one top-left, one bottom-right. A symmetric
   plate would make a transposed crop look plausible.
2. **Expect**: the top-left food's thumbnail shows the top-left food.
3. Live replies during planning already returned regions matching the foods' real positions, so this
   is a confirmation rather than an open question.

### V5 — Old meals and failure paths

1. A meal saved before regions existed → placeholders on every row, fully readable, no crash.
2. A meal whose photo file is missing → header placeholder **and** row placeholders, no crash.
3. Airplane mode, open an existing meal → details and thumbnails work (crops come from the stored
   photo).
4. Airplane mode, try to analyze → the same clear error as before; no partial meal saved.

### V6 — Appearance and language

1. Both appearances: bar, rows, thumbnails and the coloured calorie figure all legible.
2. Both languages: no raw key strings; the analysis error reads sensibly in each.

---

## Definition of done

- [ ] `BUILD SUCCEEDED`, zero warnings under Swift 6 strict concurrency
- [ ] `TEST SUCCEEDED` — 158 existing tests green plus the new schema assertions
- [ ] `"box"` is in the schema's `required` list, asserted by a test
- [ ] A missing/malformed box still yields a fully saved meal, asserted by a separate test
- [ ] `maxOutputTokens` set
- [ ] V2 passed on ≥ 5 photos with **0** failed analyses
- [ ] V1 verified on all three screens **by a real scroll to the end** — not by short content, not by
      `defaultScrollAnchor`
- [ ] V1 reached the details screen through the real navigation path, not a direct render
- [ ] Exactly one clearance constant in the codebase; root-level `safeAreaInset` removed
- [ ] No screen shows a double inset
- [ ] Thumbnails visible on a newly analyzed meal (V3), correct orientation (V4)
- [ ] Old meals still open with placeholders (V5)
- [ ] No stored-data change, no migration; no new colour token; no unused localization key
