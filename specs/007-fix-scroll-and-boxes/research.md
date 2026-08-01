# Phase 0 Research: Fix Analysis Reliability, Ingredient Thumbnails & Bottom-Bar Clearance

**Feature**: `007-fix-scroll-and-boxes` | **Date**: 2026-07-26

Every decision below was **measured**, not reasoned. That is deliberate: feature 006 shipped broken
because both of its claims rested on inference and on a test incapable of failing.

---

## R1 — Why the analysis broke, and the fix (FR-001, FR-002, FR-006)

**Decision**: mark the per-food `box` object **required** in the response schema, keep the parser's
tolerance for a missing or malformed box exactly as it is.

**Rationale — measured.** Three variants of the same request were sent to the live service with the
same photo (a synthetic plate with broccoli top-left, chicken centre-left, tomatoes lower-right):

| `box` in the request schema | `finishReason` | Reply | Boxes returned |
|---|---|---|---|
| **Optional** (feature 006 shipped this) | `MAX_TOKENS` | ~65,000 chars; the model got stuck emitting an endless digit run inside the first food's `protein` value; **unparseable** | none — it never reached `box` |
| Absent (pre-006 behaviour) | `STOP` | 256 chars, clean | n/a |
| **Required** | `STOP` | 388 chars, clean | **3 of 3 foods** |

So the optional field did not merely get omitted — it destabilised generation badly enough to
**lose the meal**. The user's report of "images don't show" was the visible tip of an outage in the
app's core function.

**Why 006 chose optional, and why that was the error**: to guarantee a missing box could never block
a save (FR-021 of feature 006). The goal was right; the location was wrong. **Schema strictness and
parser tolerance are independent.** Demanding the field in the request costs nothing in safety as
long as the parser still shrugs off absence — which it already does, via `try?` on the box decode.
FR-006 now states both must hold at once so they cannot be collapsed again.

**Alternatives considered**:
- *Keep optional and add retry-on-degeneration* — rejected: papers over a defect that has a
  one-line fix, and doubles latency and cost on the failing path.
- *Drop boxes entirely and revert to pre-006* — would restore reliability but abandons the feature
  the user asked for, when the evidence shows it works when asked for properly.
- *A second, separate localization call* — rejected: doubles cost and failure modes for a
  decorative thumbnail.

---

## R2 — Guarding against a runaway reply (FR-003, FR-004)

**Decision**: set an explicit `maxOutputTokens` in the generation config, sized generously for a
realistic meal (dozens of foods) but far below the model's default ceiling.

**Rationale**: the failing reply consumed the entire default output budget producing garbage. Even
with `box` required, no evidence proves degeneration can never recur — degeneration is a property of
the model, not of one schema. A ceiling converts a worst case of "tens of thousands of wasted tokens,
then failure" into "fail fast, cheaply". The existing failure path already surfaces an actionable
error and saves nothing, so a truncated reply lands somewhere safe (FR-004).

The observed clean replies were 256–388 characters, so the realistic ceiling is orders of magnitude
above normal output — it will not truncate legitimate answers.

**Alternatives considered**:
- *No ceiling* — status quo; leaves the pathological path unbounded in time and cost.
- *A response-length check after the fact* — rejected: the tokens are already spent by then; the
  ceiling is what avoids paying for them.
- *Constraining the macro fields to integers to prevent the float degeneration* — a plausible
  contributing fix, but it changes stored nutrition precision. Out of scope for a defect fix, and
  the required-`box` change already resolves the observed failure. Noted as a follow-up if
  degeneration is ever seen again.

---

## R3 — Why the clearance fix failed, root-caused numerically (FR-011)

**Decision**: apply the clearance **inside** each scroll container with
`.contentMargins(.bottom, …, for: .scrollContent)`. Remove the root-level `safeAreaInset`.

**Rationale — measured.** A probe printed the safe-area geometry at two levels:

```
rootContentSafeAreaBottom = 148.0   height = 746.0     ← the ZStack content IS inset
detailSafeAreaBottom      =   0.0   height = 956.0     ← the pushed detail view is NOT
```

`NavigationStack` **consumes** the inset and re-propagates a full-screen height (956 vs the 746 its
parent had) with **zero** bottom inset. Because both tabs wrap themselves in a `NavigationStack`, a
root-level inset can never reach any scrolling content in this app. That is the whole bug, and it
explains why feature 006's change looked plausible and did nothing.

**Verified fix**: with `.contentMargins(.bottom, 96, for: .scrollContent)` on the details
`ScrollView` and a real programmatic scroll to the last row, the last row renders **fully visible**
above the bar (name, calories and macros all readable). Before the change the same row could not be
brought into view at all.

**Alternatives considered**:
- *Keep the root `safeAreaInset` as well* — rejected: measured ineffective, and keeping two
  mechanisms for one job risks double-insetting any future screen not inside a `NavigationStack`
  (FR-015). Principle I forbids leaving a hack beside the real fix.
- *Move the bar inside each tab's `NavigationStack`* — would let the inset apply, but duplicates the
  bar per tab and puts app chrome inside a navigation hierarchy where pushes could cover it.
- *Replace the custom bar with a native `TabView` tab bar* — the framework would handle insets
  properly and is the cleanest long-term answer, but replacing the custom Liquid Glass bar with its
  centre camera action is a redesign, not a defect fix. Recorded as the future option.
- *`.safeAreaPadding(.bottom, …)` on the scroll content* — insets the content but not the
  scrollable range in the same way `contentMargins(for: .scrollContent)` does; the latter is the API
  intended for exactly this, and it is the one that measured correct.

---

## R4 — One clearance value, not three (Principle I)

**Decision**: expose the required clearance once as a constant on `BottomBar`, and reference it from
all three scroll containers.

**Rationale**: this number has already been duplicated once. Feature 005 hardcoded
`.padding(.bottom, 96)` in `ProgressTabView`; feature 006 deleted it and replaced it with a
root-level inset that did nothing, leaving the details screen with no clearance at all. Putting the
value on the type whose height it describes gives one place to change it if the bar's design changes,
and makes a mismatch between screens impossible.

**Alternatives considered**:
- *A free-standing constant elsewhere in the design system* — acceptable, but the bar is the natural
  owner; a reader looking at `BottomBar` should see what it costs the screens beneath it.
- *Measure the bar's height at runtime and publish it through the environment* — more "correct" and
  self-maintaining, but adds a preference/environment plumbing layer for a value that is currently
  a fixed design constant. Rejected as disproportionate to a defect fix; revisit if the bar becomes
  dynamically sized.

---

## R5 — How to verify clearance so the verification can actually fail (FR-014)

**Decision**: verify by **programmatically scrolling to the last row and screenshotting**, using a
scroll-position binding driven from a temporary probe, or by scrolling by hand on device. Explicitly
reject two methods that were tried and proved incapable of detecting the bug.

**Rationale**: this is in Phase 0 because the verification method is itself a design decision that
feature 006 got wrong twice.

- **Rejected: content that fits on one screen.** Feature 006 checked clearance with three
  ingredients. The content ended above the bar naturally, which proves nothing about whether the
  scrollable range extends past it. This produced a false pass.
- **Rejected: `.defaultScrollAnchor(.bottom)`.** Tried twice, gave contradictory readings, and in
  one run showed rows 1–9 with the tenth never visible — it does not reliably land at the true
  maximum offset.
- **Accepted: a real scroll.** Driving `scrollPosition(id:)` to the last row's id performs an actual
  scroll that honours content margins, then a screenshot shows unambiguously whether that row
  cleared the bar. This detected both the failure (row unreachable) and the fix (row fully visible)
  on the same build, which is the property a verification needs.

**Alternatives considered**:
- *A UI test* — would automate it, but UI tests are OFF by default under Principle II and must not
  be authored during regular implementation.
- *Asserting the content-margin value in a unit test* — would confirm the modifier is applied but
  not that it produces the intended layout, which is the actual requirement.
