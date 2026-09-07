<!--
Sync Impact Report
==================
Version change: 3.4.0 → 3.4.1
Bump rationale: PATCH — resincronizado a Template Constitution v3.0.2, que
corrige la clausula Backend Environments en dos puntos sin cambiar lo que exige:
su ALCANCE (gobierna los backends a los que la app llama, no todo string de URL
que guarde; los enlaces legales — politica de privacidad, EULA — son identicos
en debug y produccion y quedan fuera) y su MECANISMO (la propiedad exigida es un
unico punto de decision del que una build de release no pueda salir apuntando a
un backend que no sea produccion; `#if DEBUG`/`#else` y resolver la direccion
desde un ajuste de compilacion valen igual). Paleta sin cambios, sin
re-ratificar.

Version change: 3.3.0 → 3.4.0
Bump rationale: MINOR — sincronizado a Template Constitution v3.0.1, saltando
desde v2.2.0. Lo que entra:
  - v2.3.0, presentacion de bottom sheets. **No abre trabajo de codigo aqui: el
    proyecto no presenta ni una sola sheet.**
  - v2.4.0, Backend Environments: toda URL de red sale de un unico
    `BackendEnvironment`, con produccion en el `#else`.
  - v2.4.1/v3.0.1, clausula "Project extensions" de Governance (incluida
    "Numbering") y disparador de ratificacion de paleta acotado.
El Principio VII (Monetization & In-App Purchase) de v2.4.0 NUNCA llego a este
proyecto: fue retractado en el template en v3.0.0 antes de propagarse.
Paleta: la identidad verde de salud se arrastra sin cambios y NO se re-ratifica,
por la misma razon; pasa 4.5:1 y esta cubierta por PaletteContrastTests.
Deuda de codigo que ESTE sync abre:
  - `Kalorias/Features/Analysis/GeminiCalorieService.swift:68` incrusta la URL
    base de Gemini. Debe pasar a `BackendEnvironment`.
Deuda anterior que sigue abierta (v2.1.0/v2.2.0): sin vocabulario de
movimiento, cero cambios de estado animados y un `.easeInOut` en linea en
CameraCaptureView.

Version change: 1.1.1 → 2.0.0
Bump rationale: MAJOR — synced to Template Constitution v1.0.0
(`~/Projects/TemplateConstitution.md`), which redefines two existing
principles rather than merely extending them:

  1. Principle II — UI tests (XCUITest) are now OFF by default. They are no
     longer authored or executed during regular implementation runs and MUST
     NOT appear in task lists; they are opt-in, on explicit maintainer
     request. Accessibility identifiers and DEBUG launch hooks are still
     added during implementation so the flows stay testable later.
  2. Principle III — Apple's Liquid Glass is **no longer mandated**. Surface
     treatment (glass vs. system material vs. opaque fill) is now decided per
     screen by the `apple-design` skill's guidance on materials and depth.
     What remains binding: when a translucent surface IS used, it must come
     from Apple's own APIs and go through the project's shared helpers, and
     the Reduce Transparency / Increase Contrast fallbacks live inside those
     helpers.
  3. Principle III also gains tokenized color and a measured 4.5:1 contrast
     rule; Principle VI gains the rule that a raw technical identifier must
     never be what VoiceOver reads aloud.

Added sections:
- Product Overview (project-specific; the app's own objective)
- Design System & Color Tokens (project-specific palette; shared rules)
- Design Reference: the `apple-design` skill

Also added, from lessons measured in practice:
- Principle IV — a performance budget is a MEASURED gate, not an assumption.
- Principle V — Stores and services MUST NOT import SwiftUI for convenience.

Shared/project split: every section of this file outside a
`<!-- PROJECT:... -->` block is SHARED and MUST match the template verbatim.
A change to a shared section is made in the template first, then propagated.

Templates requiring updates:
- ✅ .specify/templates/plan-template.md — generic Constitution Check gate;
  enforced by principle text, no edit required.
- ✅ .specify/templates/spec-template.md — no principle-specific references.
- ✅ .specify/templates/tasks-template.md — generic; this constitution now
  instructs it to exclude UI-test tasks from implement-phase plans.

AMENDMENT 3.0.0 (2026-07-27) — synced to Template Constitution v2.0.0
--------------------------------------------------------------------
Bump rationale: MAJOR — backward-incompatible. The previous version *required*
translucent surfaces to be drawn through project helpers such as `glassCard`
and `glassActionButton`; this version **forbids those helpers outright** and
requires them, and every call site, to be deleted. Code that complied before
now violates.

Why: a convenience wrapper turns a design judgement into a default. Once
`glassCard` exists, applying it is easier than deciding not to, and glass
creeps back in by habit — reinstating through the side door exactly the mandate
the previous amendment removed. Where translucency is genuinely warranted,
Apple's API is called at the site that needs it, so the decision is visible in
the code that made it.

Also changed: Reduce Transparency and Increase Contrast are now explicitly the
system's responsibility. Apple's materials and glass already honour those
settings; the project helper re-implemented that and could only drift from it.

Follow-up TODOs: see the TODO(...) markers inside the PROJECT blocks below.

AMENDMENT 3.1.0 (2026-08-01) — TODO(CONTRAST_AUDIT) resolved
------------------------------------------------------------
Bump rationale: MINOR — materially expanded guidance inside a PROJECT block
(the palette). No SHARED section changed, so no template change and no
propagation to other projects is implied.

What changed and why: the measured audit the 3.0.0 amendment deferred was
carried out. 9 of the 11 text-bearing tokens failed the 4.5:1 rule Principle III
requires, all of them in LIGHT appearance only — every dark variant already
passed with room (6.10-12.67). The cause was structural rather than a handful of
bad hexes: the palette used ONE token for both text and fills, and a hue vivid
enough to be a chart bar is not legible as text on `surfacePrimary`.

The fix follows the Template Constitution's own palette, which already
distinguishes `stateCaution` (text and icons) from `stateCautionFill` (fills
only) — a split this project had collapsed. Five `-Fill` tokens now carry the
original vivid hexes unchanged; the five text tokens keep their dark variants
untouched and darken only their light variant, to ~4.6:1 rather than the bare
minimum so the values do not sit on the threshold.

`brandSecondary` was removed: it had zero uses anywhere in the app (Principle I,
no dead code).

Verification is by measurement, not by this table: `PaletteContrastTests`
resolves each token from the asset catalog through `UIColor(resource:)` for an
explicit trait collection and computes the WCAG ratio. A test asserting
hardcoded hexes would audit nothing and would drift from the catalog silently.

Also recorded here: the two surface tokens are only 1.065:1 apart in light,
so card elevation cannot come from tone. Darkening `surfacePrimary` was modelled
and rejected because it pushes the text tokens back below the threshold; the
separation lives in `CardSurface.swift` instead.

AMENDMENT 3.2.0 (2026-08-03) — synced to Template Constitution v2.1.0
--------------------------------------------------------------------
Bump rationale: MINOR — new and materially expanded guidance in SHARED
sections. Nothing that complied under 3.1.0 becomes a violation: Stores, the
"no ViewModel" rule, and the ban on inline `.spring(...)`/`.easeInOut(...)`
were all already mandatory here.

SHARED sections changed (all propagated verbatim from the template):
  1. Principle III gains three motion rules: **motion is the default** — every
     observable state change is animated rather than snapping; **animation comes
     from the vocabulary, never from a literal**; and **fluid is not busy** —
     idle loops, decorative flourishes, and time-filling staggered entrances are
     forbidden, and no animation may delay the user's next action. Its rationale
     gains the paragraph explaining why motion is defaulted *on* while glass is
     defaulted *off*.
  2. Principle V is restated as **MVS (Model–View–Store)**. The Store is now
     named as a layer of the pattern rather than an addition to MV, and each
     layer's responsibilities are spelled out, including that a type backing
     exactly one view is "a ViewModel wearing a Store's name".
  3. Design System — the **Motion** entry now specifies the vocabulary's shape:
     named values from a single type (e.g. `AppMotion`) covering at minimum a
     *standard*, a *gestural*, and a *subtle* animation, each paired with the
     transition it travels with, with the Reduce Motion substitution applied
     inside the vocabulary once. The grep audit adds "zero inline animation
     constructors in the view layer".
  4. Design System — **the palette is ratified with the maintainer, never
     invented**, at project adoption and at every sync, via the Clarification
     Gate format (three complete proposals, one marked Recommended).
  5. Development Workflow gains the **Clarification Gate (NON-NEGOTIABLE)**:
     every `/speckit-specify` and `/speckit-plan` run ends by putting every open
     question to the maintainer as a batch of three-option questions with a
     marked recommendation, answered and written back in the same run; a run
     that surfaces nothing open must say so out loud.
  6. The PR checklist adds the inline-animation audit and the requirement that
     every new or changed observable state transition is animated from the
     vocabulary and checked once with Reduce Motion on.

No PROJECT block changed. The palette was re-ratified with the maintainer at
this sync (see "Design System & Color Tokens"); it was kept unchanged, having
passed the 4.5:1 audit in 3.1.0.

Prior TODO closed: `glassCard`/`glassActionButton` and all call sites are gone;
`CardSurface.swift` carries the opaque replacement.

Follow-up TODOs (code, not constitution):
- TODO(MOTION_VOCABULARY): the app has no motion vocabulary type. Principle III
  now requires one; create `Kalorias/DesignSystem/AppMotion.swift` with the
  standard/gestural/subtle animations and their paired transitions, with the
  Reduce Motion substitution applied inside it.
- TODO(MOTION_ADOPTION): the app currently animates no state change and holds
  one inline constructor at
  `Kalorias/Features/Camera/CameraCaptureView.swift:175`
  (`.easeInOut(duration: 0.15)`). Route it through the vocabulary and animate
  the observable state changes Principle III now defaults on.

Templates reviewed at this sync:
- ✅ .specify/templates/plan-template.md — generic Constitution Check gate.
- ✅ .specify/templates/spec-template.md — no principle-specific references.
- ✅ .specify/templates/tasks-template.md — generic; still correctly excludes
  UI-test tasks from implement-phase plans.

AMENDMENT 3.3.0 (2026-08-04) — synced to Template Constitution v2.2.0
--------------------------------------------------------------------
Bump rationale: MINOR — new guidance added to a SHARED section. Nothing that
complied under 3.2.0 becomes a violation; the clause tells an implementation run
what to do when a required piece of the design system is missing, it does not
change what the design system must contain.

SHARED section changed (propagated verbatim from the template — exactly one,
and the rest of the SHARED body was verified byte-identical to the template
before and after):
  1. Design System & Color Tokens gains **"The design system is a prerequisite,
     not a deliverable of its own."** Where the type scale, the spacing scale,
     or the motion vocabulary does not yet exist, building it belongs to the
     first feature that needs it and MUST happen in the same implementation run
     — not deferred, not filed as a follow-up, and never worked around with a
     literal or an unanimated state change. Judgement the new piece needs (the
     house spring's feel, the ramp's steps) goes through the Clarification Gate.

Why it matters here specifically: v2.1.0 required all motion to come from a
vocabulary but never said who creates that vocabulary or when. Kalorias has
none, so every implement run since has had no legal move — animate and violate
"no literals", or skip the animation and violate "motion is the default". This
clause resolves that: build the vocabulary, in that run.

No PROJECT block changed. The palette was NOT re-ratified at this sync: the
template records that the v2.2.0 clause affects no palette and that propagating
it does not require re-ratification, so the green health identity ratified at
the 3.2.0 sync carries over unchanged and still passes 4.5:1 under
`PaletteContrastTests`.

Status of the 3.2.0 follow-ups, re-stated under the new clause (verified in the
code at this sync — both are still open, and both are now prerequisite work
rather than deferrable TODOs):
- MOTION_VOCABULARY: `Kalorias/DesignSystem/` holds AppColor, BottomBar,
  CalorieColorStep+Color, CardSurface, ReverseMask — there is no `AppMotion`,
  and no type or spacing scale either. The next feature that animates anything
  MUST create `AppMotion.swift` (standard/gestural/subtle, each with its paired
  transition, Reduce Motion applied inside it) in the same run.
- MOTION_ADOPTION: the app still animates zero state changes and still holds
  the one inline constructor at
  `Kalorias/Features/Camera/CameraCaptureView.swift:175`
  (`.easeInOut(duration: 0.15)`). It is routed through the vocabulary by the
  first run that touches that screen.

Templates reviewed at this sync:
- ✅ .specify/templates/plan-template.md — generic Constitution Check gate.
- ✅ .specify/templates/spec-template.md — no principle-specific references.
- ✅ .specify/templates/tasks-template.md — generic; still correctly excludes
  UI-test tasks from implement-phase plans.

AMENDMENT 4.0.0 (2026-09-01) — analysis moved to the Kalorias backend
--------------------------------------------------------------------
Bump rationale: MAJOR — backward-incompatible, by this file's own test: code
that complied before now violates. Under 3.4.1 the approved architecture was the
app calling **Google Gemini** directly with a key read from a build setting, and
4.0.0 forbids precisely that. Feature 002 was compliant when it shipped and
would not be accepted today. No SHARED section changed — both edits are PROJECT
blocks — so there is no template change and no propagation to other projects.

What changed and why: feature 009 moved photo analysis to the Kalorias backend.
The app uploads the photo to a service the project owns and receives foods,
calories, macros and regions back; the prompt, the response schema and the
provider credential all live on the server. The driver was the credential. A key
in a distributed binary is extractable and cannot be rotated without an App
Store release, so confining it to a git-ignored file was never enough — it kept
the key out of the repository while shipping it to every user. Two PROJECT
blocks are restated:
  1. **Product Overview** — step 2 of the core flow names the Kalorias backend
     rather than Google Gemini, and records that the app holds neither the
     prompt, the schema, nor a provider credential.
  2. **Technology Constraints / external services** — the Kalorias backend is
     the one approved external service; the ban on *committing* credentials is
     widened to holding one at all, in the binary or in a build setting; and the
     provider's identity, HTTP status codes and internal identifiers are barred
     from the UI, which `CalorieAnalysisErrorMappingTests` already enforces.

The palette was NOT re-ratified: this amendment changes no palette rule and no
token, so the green health identity ratified at the 3.2.0 sync carries over
unchanged and still passes 4.5:1 under `PaletteContrastTests`.

Prior debt closed, verified in the code at this amendment:
- The 3.4.0 record above lists
  `Kalorias/Features/Analysis/GeminiCalorieService.swift:68` as embedding a base
  URL that must move to `BackendEnvironment`. That file no longer exists;
  `Kalorias/Support/BackendEnvironment.swift` resolves the address from the
  `KaloriasAPIBaseURL` build setting and `BackendEnvironmentTests` proves it
  parses to an absolute URL. **The 3.4.0 record is left standing as written** —
  it was true when it ran, and this project supersedes its history rather than
  rewriting it.
- MOTION_VOCABULARY and MOTION_ADOPTION, open since 3.2.0, are closed:
  `Kalorias/DesignSystem/AppMotion.swift` exists with standard/gestural/subtle
  and the Reduce Motion substitution applied inside the vocabulary once, and the
  inline `.easeInOut(duration: 0.15)` in `CameraCaptureView` is gone. The grep
  audit returns zero inline animation constructors in the view layer.

Templates reviewed at this amendment:
- ✅ .specify/templates/plan-template.md — generic Constitution Check gate; no
  provider-specific text.
- ✅ .specify/templates/spec-template.md — no principle-specific references.
- ✅ .specify/templates/tasks-template.md — generic; still correctly excludes
  UI-test tasks from implement-phase plans.
- ✅ .specify/workflows/speckit/workflow.yml names "gemini", but as an *agent
  integration* choice (the Gemini CLI), unrelated to the app's external service.
  Left unchanged deliberately.

Follow-up TODO (code and operations, not a constitution change):
- TODO(REVOKE_GEMINI_KEY): specs/009 task T053 is still open. The key was never
  committed, but it shipped inside every build made before feature 009 and is
  still live at the provider. It MUST be revoked there; deleting it from the
  project does not stop it working.
  **RESOLVED the same day (2026-09-01), by maintainer decision, without
  revoking**: the app was never distributed — no build ever left the
  maintainer's machine, so the embedded key never reached anyone else's device
  and the exposure the TODO guards against never materialised. The TODO text
  above is left standing as written rather than deleted, so the reasoning is
  auditable: the key remains valid at the provider, and this closure holds only
  while no pre-009 build is distributed. Distributing one reopens it.
  This changes no normative clause, so it carries no version bump of its own.
-->

# Kalorias Constitution

## Product Overview

<!-- PROJECT:overview -->
Kalorias is a native iOS app for counting calories that starts from a
**photo**. The core flow is:

1. The user takes or picks a **photo of their food**.
2. The app sends the image to the **Kalorias backend**, which analyzes it and
   returns the food's **calorie count** (and macronutrients). The backend owns
   the analysis prompt, the response schema and the AI-provider credential; the
   app holds none of the three and never calls a provider directly.
3. Kalorias returns that estimate to the user and logs it toward their daily
   and goal totals.

Because the primary input is a networked AI call, calorie/macro values are
**estimates**, image analysis is asynchronous and can fail, and every such
action MUST show a loading state and surface a clear, actionable error on
failure (see Principle III).
<!-- /PROJECT:overview -->

## Core Principles

### I. Code Quality

All code merged into the project MUST meet a consistent, reviewed quality bar
before it ships:

- Code MUST compile with zero warnings; new warnings introduced by a change
  MUST be resolved before merge, not suppressed.
- Swift code MUST follow the Swift API Design Guidelines and the project's
  linting configuration; force-unwraps (`!`), force-casts (`as!`), and
  force-tries (`try!`) are forbidden outside of test code unless the
  invariant that makes them safe is documented in an adjacent comment.
- Every change MUST go through review (self-review at minimum for a
  single-maintainer project, peer review when more than one contributor is
  active) before merging to `main`. No direct, unreviewed pushes to `main`.
- No dead code, commented-out code, or TODO-without-tracking is left in
  merged code. If work is deferred, it is tracked as a task, not a comment.

<!-- PROJECT:core-logic -->
- Nutrition math (turning per-item estimates into daily and goal aggregates,
  remaining budgets, and macro breakdowns) MUST live in dedicated,
  unit-testable functions/types separate from view code — never computed
  inline inside SwiftUI view bodies.

**Rationale**: Kalorias exists to give the user a number they act on; a wrong
aggregate silently misleads them about their day and is expensive to debug
once scattered through UI code.
<!-- /PROJECT:core-logic -->

A consistent, warning-free, reviewed codebase is the cheapest way to prevent
that class of bug.

### II. Testing Standards (NON-NEGOTIABLE)

<!-- PROJECT:test-scope -->
- Any logic that computes, aggregates, converts, or persists calorie and
  macronutrient values (per-item estimates, daily and goal totals, remaining
  budgets, macro breakdowns, logged history) MUST have unit tests covering the
  normal case, the zero/empty case, and at least one boundary or error case,
  written before or alongside the implementation.
<!-- /PROJECT:test-scope -->

- Every bug fix MUST include a regression test that fails before the fix and
  passes after it, in the same PR as the fix.
- **UI tests (XCUITest) are OFF by default.** They MUST NOT be authored,
  modified, or executed during regular implementation runs (e.g.
  `/speckit-implement`), and implementation plans and task lists MUST NOT
  include UI-test tasks and MUST NOT block on missing UI coverage. UI tests
  are authored and run EXCLUSIVELY when the maintainer explicitly requests
  UI-test work (if a `/speckit-tests` command is installed, that command is
  the vehicle for it). To keep flows testable later, accessibility
  identifiers and any DEBUG launch-argument hooks that future UI tests will
  need MUST still be added during implementation.
- A pull request that touches business logic without an accompanying unit
  test change MUST justify why no test was needed in the PR description;
  "hard to test" is not sufficient justification — the code should be
  restructured to be testable instead.
- Tests MUST be deterministic and independent of wall-clock time, locale, or
  network access unless the feature explicitly under test is one of those.

**Rationale**: Core domain logic cannot be verified by inspection alone.
Test-first for that logic and mandatory regression tests keep the same bug
from resurfacing and keep confidence high as the app grows past a single
maintainer's working memory. UI tests are slower and flakier than unit tests,
so keeping them off by default and behind an explicit maintainer request keeps
implementation iterations fast while preserving end-to-end coverage as a
deliberate, opt-in gate.

### III. User Experience Consistency

- The app follows Apple's Human Interface Guidelines for iOS; navigation
  patterns, typography, spacing, and color usage MUST be consistent across
  every screen, driven by shared design-system assets rather than ad hoc,
  per-screen values.
- **Tokenized color.** Every color used in the UI MUST come from the
  design-system color tokens defined in "Design System & Color Tokens" below,
  never from raw `Color(red:green:blue:)` or hex literals inside views. New
  colors are added to the palette first, then referenced by token. The only
  permitted runtime color decode is a value the user themselves chose and the
  app persisted.
- **Contrast is measured, not eyeballed.** Text and essential icons MUST meet
  at least 4.5:1 contrast against their background in both light and dark
  appearances. Where the app derives a foreground color from an arbitrary
  background (e.g. a user-picked color), that derivation MUST be covered by a
  test that computes the ratio rather than asserting it by inspection.
- **Surface treatment is decided by the `apple-design` skill, not mandated
  here.** Whether a given surface is Liquid Glass, a system material, or a
  plain opaque fill is a design judgement made against that skill's guidance
  on materials and depth (see the apple-design section below). Translucency is
  used where it conveys hierarchy and earns its place — not by default, not
  everywhere, and not as a quota. Liquid Glass is a tool available to the app,
  never an obligation.
- **When a translucent surface is used**, it MUST be produced with Apple's own
  APIs (`.glassEffect(...)`, `GlassEffectContainer`, the `.glass` /
  `.glassProminent` button styles, or the system materials) rather than
  hand-rolled from blurs, gradients, strokes, and opacity.
- **`glassCard` and `glassActionButton` are forbidden.** Wherever they exist
  they MUST be deleted, along with every call site. No project may define a
  convenience wrapper of this kind, under these or any other names: a helper
  whose whole job is to apply glass to a card or a button turns a design
  judgement into a default, which is precisely what the rule above rejects.
  Where a surface genuinely warrants translucency, call Apple's API at the
  site that needs it, so the decision is visible in the code that made it.
- Accessibility behaviour for translucency (Reduce Transparency, Increase
  Contrast) is **the system's job, not the app's**. Apple's materials and
  glass already honour those settings; re-implementing that behaviour in a
  project helper duplicates the platform and drifts from it. Do not hand-roll
  fallbacks. Every surface, translucent or not, MUST remain legible in both
  light and dark appearances (Principle VI), and that legibility is verified,
  not assumed.
- **A bottom sheet's content IS the sheet, not a card floating inside it.**
  A view presented as a bottom sheet MUST NOT apply a translucent surface
  (`.glassEffect(...)`, a system material, or any other fill) to its own root,
  and MUST NOT wrap that root in outer insets that hold the card away from the
  sheet's edges. The presentation already draws a surface; a second one inside
  it is decoration stacked on decoration, and the inset that separates them is
  wasted height on the screen size that has least of it. Interior padding
  *within* the content is normal and expected — what is forbidden is a second
  surface and the outer inset around it.
- **A sheet's root fills the presented height.** It MUST carry
  `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)` so the
  content grows from the top edge of the detent rather than centring itself in
  it. Without this a short sheet floats its content mid-height and a bottom-
  pinned action lands wherever the content happens to end.
- **A half-height sheet is fixed, not expandable.** A sheet presented at half
  height MUST declare exactly one detent and MUST NOT be draggable to a larger
  one, unless a feature spec states otherwise **and says why** — content that
  demonstrably cannot fit at half height on some supported device is the kind of
  reason that qualifies; "the user might want more room" is not. Downward
  swipe-to-dismiss is unaffected by this rule. A sheet whose whole purpose is
  long-form reading is presented at large from the start rather than made
  resizable.
- **Motion is the default, not an extra.** Every observable state change MUST
  be animated rather than snapping into place, so the app reads as continuous:
  a value updating, a row inserted, removed, or reordered, a sheet or detail
  appearing and dismissing, a tab or filter switching, content arriving after
  a load, an error or empty state appearing, a control changing its pressed or
  selected appearance. Where a screen changes state instantly today, adding
  the animation is part of the work, not a follow-up pass.
- **Animation comes from the vocabulary, never from a literal.** All motion
  MUST use the named animations and paired transitions defined in the Motion
  entry of "Design System & Color Tokens" below. Views MUST NOT construct
  `.spring(...)` or `.easeInOut(...)` inline and MUST NOT invent per-screen
  durations; a new kind of motion is added to the vocabulary first, then used.
- **Fluid is not busy.** Motion earns its place by showing where something
  came from and where it went. Idle loops, decorative flourishes, and staggered
  entrances that merely fill time are forbidden, and no animation may delay the
  user's next action: every animated flow stays interruptible, stays inside the
  frame budget of Principle IV, and remains fully completable under Reduce
  Motion (see the apple-design section).

<!-- PROJECT:vocabulary -->
- The app's domain terminology (e.g. "calorías", "macros", "proteínas",
  "carbohidratos", "grasas", "alimento", "registro" and their English
  equivalents) MUST be used consistently everywhere it appears: in-app copy,
  VoiceOver labels, and error messages use the same term for the same concept
  throughout the app.
<!-- /PROJECT:vocabulary -->

<!-- PROJECT:latency-destructive -->
- Every user-initiated action with observable latency (photo analysis, calorie
  and macro estimation) MUST show a loading state; every failure MUST surface
  a clear, actionable error message instead of failing silently.
- Destructive actions (deleting a food entry, clearing a day's log, resetting
  goals) MUST require explicit confirmation before taking effect.
<!-- /PROJECT:latency-destructive -->

- New screens and components MUST support Dynamic Type and VoiceOver at a
  baseline usable level before merge; this is not deferred to a later pass.

**Rationale**: These apps are used habitually and often quickly. Inconsistent
patterns or unclear feedback increase mistakes exactly where they matter most.
A single tokenized palette keeps color coherent and themable. What the
constitution deliberately does *not* fix is which surface treatment a screen
uses: mandating glass everywhere produces decoration rather than hierarchy, so
that judgement belongs to the `apple-design` guidance, applied per screen.

A convenience wrapper such as `glassCard` is how that mandate creeps back in
through the side door — once it exists, applying it is easier than deciding not
to, and every new screen inherits glass by default. Banning the wrapper is not
a style preference: it forces the decision to be made, and made visibly, at the
one place that has the context to make it.

Motion is treated the opposite way, and for the same reason. A UI that snaps
between states makes the user re-read the screen after every tap to work out
what changed; animating the change carries that information for them, which is
why the default here is *animate*, not *consider animating*. That default is
safe only because the motion comes from one shared vocabulary: a per-screen
`.easeInOut(duration: 0.3)` is how an app ends up with fifteen slightly
different senses of "fast", and how ornament creeps in behind the word
"fluid".

The bottom-sheet rules are the same argument applied to a surface rather than
to a colour or a curve. A sheet is *already* a floating, layered surface — the
system drew it, at the right elevation, honouring the accessibility settings.
Putting a glass card inside it does not add hierarchy, because there is no
second level of hierarchy to express; it adds a border, an inset, and a
translucency stacked over translucency that reads as haze on the one screen
size with no height to spare. And a half sheet that can be dragged taller
offers a gesture with two meanings — resize or dismiss — at the exact moment
the reader is deciding whether they are done. Fixing the height removes the
ambiguity rather than documenting it.

### IV. Performance Requirements

- Cold app launch to first interactive frame MUST stay under 2 seconds on the
  minimum supported device/OS combination.
- Scrolling lists MUST sustain 60fps; any list-heavy feature MUST be profiled
  with Instruments before shipping if it changes how list rows are rendered
  or loaded.
- Local data mutations and local computations MUST complete in under 100ms
  for datasets up to at least 10,000 records; any operation that cannot meet
  this MUST run off the main thread (e.g. via `async`/`await` or a background
  queue) so the UI never blocks.
- A performance budget in this principle is a **measured** gate, not an
  assumption. When a design's cost is not obvious, it MUST be measured
  against the budget before the design is accepted; a design that misses the
  budget is changed, not waived.
- Persistence and computation work MUST NOT block the main thread; this is
  verified before merge, not assumed.

**Rationale**: Perceived slowness in a habit-forming utility app drives
abandonment faster than missing features. Explicit, testable budgets prevent
performance from silently degrading as data grows — and measuring rather than
assuming is what makes the budget real.

### V. Architecture & Concurrency (NON-NEGOTIABLE)

- The app MUST be built and MUST compile under Swift 6 language mode with
  strict concurrency checking enabled (`SWIFT_STRICT_CONCURRENCY = complete`).
  Concurrency warnings MUST NOT be silenced with blanket `@unchecked
  Sendable`, `nonisolated(unsafe)`, or `@preconcurrency` escapes unless the
  safety invariant is documented in an adjacent comment and justified in the
  PR.
- The app MUST follow the **MVS (Model–View–Store)** pattern. Its three layers,
  and nothing between them:
  - **Model** — the domain types and the pure logic over them (Principle I):
    value types where possible, no knowledge of the UI, unit-testable on their
    own.
  - **View** — thin SwiftUI views that render the state they observe and send
    intents. A view holds no business logic and owns no state beyond what is
    purely local to its own presentation (e.g. a text field's in-progress
    text, an animation flag).
  - **Store** — the observable, `@MainActor`-isolated reference types (e.g.
    `@Observable` classes) that own a slice of application or feature state and
    expose the intents that mutate it. Every mutation the user can cause goes
    through a Store intent.
- There is **no per-view ViewModel or Controller layer** — MVVM is explicitly
  not the pattern here. A type that exists to back exactly one view, mirroring
  its properties, is a ViewModel wearing a Store's name; Stores are owned by a
  feature and are shared by the views of that feature.
- Business logic and mutations MUST NOT live in view bodies. A view body
  computes layout from state and calls intents — nothing else.
- Navigation MUST be driven by a dedicated **Router** that owns navigation
  state (paths, presented sheets, modals). Views MUST NOT construct ad hoc
  navigation destinations inline; they request navigation through the Router.
- Store and service code MUST NOT import SwiftUI to borrow a convenience;
  logic that lives below the view layer stays independent of it.
- Core domain, aggregation, and persistence logic remain in testable types
  owned by Stores or dedicated services (per Principle I), not in the Router
  or views.

**Rationale**: Strict concurrency catches data races at compile time, which is
exactly the class of bug that silently corrupts user data. A single,
opinionated MVS + Router architecture keeps state ownership and navigation
predictable, makes logic unit-testable, and prevents the codebase from drifting
into inconsistent patterns as it grows. Naming the Store as a layer of the
pattern rather than an addendum to it is deliberate: it is the only place
mutable state lives, so "where does this state belong?" and "who is allowed to
change it?" have one answer on every screen of every project. MVVM's answer —
one object per view — multiplies state owners as the app grows and pushes
logic back toward the view it is named after.

### VI. Localization & Appearance (NON-NEGOTIABLE)

- Every user-facing string MUST be localized and MUST ship with both English
  and Spanish translations. No hardcoded, untranslated user-facing text is
  merged. Strings MUST be sourced from the localization catalog
  (e.g. `Localizable.xcstrings`), never string literals inside views.
- Adding or changing user-facing copy MUST update both language values in the
  same change; a missing translation in either language blocks merge.
- Accessibility labels are user-facing text. A raw technical identifier (an
  SF Symbol name, an enum case, a key) MUST NEVER be what VoiceOver reads
  aloud.
- The app MUST fully support Dark Mode. Every screen and component MUST render
  correctly and legibly in both light and dark appearances, using the
  tokenized palette and semantic/asset-catalog colors that adapt automatically
  rather than hardcoded color values (see Principle III).
- New screens and components MUST be verified in both appearances and both
  languages before merge; this is not deferred to a later pass.

**Rationale**: These apps serve both English- and Spanish-speaking users, and a
partially translated or light-only UI reads as broken. Enforcing bilingual
localization and Dark Mode at merge time keeps every screen consistent instead
of accumulating gaps that are expensive to retrofit.

## Technology Constraints

The app is built with **Swift 6 and SwiftUI**, structured as a standard Xcode
project, with strict concurrency checking enabled project-wide (see Principle
V). Persistence MUST use a native, supported Apple framework (e.g. SwiftData
or Core Data) rather than a custom serialization scheme, unless a documented
requirement makes that insufficient. Third-party dependencies MUST be
justified — prefer Apple frameworks (Foundation, SwiftUI, Observation,
SwiftData) over external packages unless a dependency provides functionality
that would otherwise require significant, hard-to-maintain custom code.

<!-- PROJECT:external-services -->
The **Kalorias backend** is the one approved external service: it powers the
core photo-to-calories estimation (see Product Overview), which cannot be
replaced by an on-device Apple framework at the required quality. Its use MUST
be confined to a dedicated service/Store boundary (never called from view
bodies), MUST run off the main thread, and MUST degrade gracefully when the
network or the service is unavailable.

**The app MUST NOT hold an AI-provider credential, and MUST NOT call an AI
provider directly.** The backend owns the prompt, the response schema and the
provider key. Keeping a key out of the repository is necessary but not
sufficient: a key inside a distributed binary is extractable by anyone who
installs the app and cannot be rotated without an App Store release, so it MUST
also be out of the build. API keys and credentials MUST NOT be committed to the
repository **and MUST NOT be read into the app from a build setting** —
`Config/Secrets.xcconfig` carries a service address and nothing else.

The app MUST NOT disclose which provider the backend uses. Provider names, HTTP
status codes and internal identifiers MUST NOT reach the UI; the user sees a
plain, actionable message instead (`CalorieAnalysisErrorMappingTests` enforces
this, and Principle VI's rule that a raw technical identifier is never what
VoiceOver reads aloud applies to these too).

Any additional external/networked dependency beyond the Kalorias backend still
requires the justification above.
<!-- /PROJECT:external-services -->

### Backend Environments

- Every URL the app talks to MUST be built from a single `BackendEnvironment`
  type. Base URLs, hosts, and scheme+host string literals MUST NOT appear in
  Stores, services, views, or anywhere else; call sites build a request by
  appending a path to `BackendEnvironment.current.baseURL`, never by writing a
  whole URL.
- `BackendEnvironment` is an enum of the environments the app actually has —
  at minimum `debug` and `production`, plus `staging` where one exists — and
  each case exposes that environment's configuration together: base URL and
  anything else that legitimately differs per environment (timeouts, logging
  verbosity, where credentials are read from).
- **The debug/production decision is made in exactly one place**, and a release
  build MUST NOT be able to resolve to a non-production backend. Two mechanisms
  satisfy this and a project may use either: a single `current` guarded by
  `#if DEBUG` with **production as the `#else`**, so the production case is the
  compiled-in fallback; or resolving the address from a build setting — an
  xcconfig value read from the bundle at launch — which moves the choice into
  the build configuration instead of the source. What is forbidden is the same
  under both: a runtime default that something else can override, and more than
  one place that decides.
- A runtime override for switching environment while testing (a launch
  argument, a hidden developer setting) is permitted **only** inside `#if
  DEBUG`, so it is compiled out of release builds entirely.
- **This governs the backends the app calls, not every URL it holds.** A link
  the app merely opens — a privacy policy, an EULA, a support page — does not
  vary by environment and does not belong here; such links live together in
  their own constant, out of view bodies, and are not a violation of this rule.
  The moment a link *does* differ between debug and production it has stopped
  being a link and become configuration, and this rule applies to it.
- `BackendEnvironment` says *where*, never *what*: API keys and credentials
  MUST NOT be literals in it (see the external-services rule above). It may
  name where a secret is read from; it may not contain one.
- This is auditable by grep, and that is the point: a review MUST be able to
  confirm zero `URL(string: "http...")` and zero base-URL literals outside
  `BackendEnvironment`.
- An app that makes no network call owes no `BackendEnvironment` yet. Like the
  design system, it is a prerequisite of the first feature that needs one —
  the first networked call builds it in the same run rather than hardcoding a
  URL "for now".

**Rationale**: A base URL written at the call site is how a build ships
pointing at a developer's machine, and how switching backends becomes a
find-and-replace across the app instead of an edit in one file. Making
production the `#else` rather than the default value inverts the failure: the
mistake a tired maintainer makes at 2am is forgetting to flip a flag back, and
under this rule forgetting is safe.

## Design System & Color Tokens

Every color in the UI MUST come from the tokenized palette (Principle III),
not from raw literals. Tokens live as color sets in the asset catalog — each
with a light **and** a dark variant — and are exposed through a single
design-system type (e.g. `AppPalette` / `AppColor`). To add a color, create
the color set first, then expose it as a token; never inline a new literal.

The design system also owns, in one place each and drawn from nowhere else:

- **Type scale** — named roles (display/total, row title, row value, section
  label, supporting text) defining size, weight, and letter-spacing
  *together*. Every role builds on a Dynamic Type text style; fixed point
  sizes are forbidden. Letter-spacing is size-specific: tighter on large
  display text, neutral on body, slightly looser on the smallest labels.
- **Spacing scale** — one ramp that all padding, insets, and gaps come from.
- **Motion** — the app's animation vocabulary, exposed as named values from a
  single type (e.g. `AppMotion`) and covering at minimum: a **standard**
  transition (the house critically-damped spring, used for almost everything),
  a **gestural** response for motion a drag or flick actually threw (the only
  place overshoot is permitted), and a **subtle** change for small in-place
  updates such as a number, badge, or selection. Each named animation is paired
  with the transition it travels with, so a surface leaves along the path it
  arrived by. Views MUST NOT construct `.spring(...)`/`.easeInOut(...)` inline,
  and the Reduce Motion substitution is applied inside the vocabulary once —
  never re-checked view by view.

These are auditable by grep, and that is the point: a review MUST be able to
confirm zero color literals, zero raw `.font(.body)`-style calls, zero numeric
spacing literals, and zero inline animation constructors in the view layer.

**The design system is a prerequisite, not a deliverable of its own.** Where a
required piece of it — the type scale, the spacing scale, the motion vocabulary
— does not yet exist, building it is part of the first feature that needs it,
not a reason to defer the rule and not a follow-up task. An implementation run
that encounters a missing piece MUST create it in the same run, minimally and
in one place, rather than reaching for a literal or leaving the state change
unanimated. The Clarification Gate carries any judgement the new piece needs
(the house spring's feel, the ramp's steps); everything else is already settled
by the definitions above.

**The palette is ratified with the maintainer, never invented.** There are
exactly two moments this question is asked, and it MUST be asked at both:

1. when a project first adopts this template, and
2. every time a project syncs to a template version that changed what a palette
   must satisfy, or which tokens the table holds.

A sync that leaves both untouched carries the existing palette over unchanged
and MUST record that in its Sync Impact Report rather than re-opening the
question. Asking with nothing to decide trains the answer "same as before" and
spends the gate's credibility on the sync that does have something at stake.
The one exception is failure, below: a palette that misses 4.5:1 anywhere is
re-opened on **any** sync.

The question follows the Clarification Gate format below — three complete,
concrete palette proposals, each with the light and dark hex for every token in
the table, each described by the mood and purpose it fits, with one marked
**Recommended** and the reason given. The maintainer may of course answer with
their own colors instead. Until it is answered, no UI work proceeds: the
`PROJECT:palette` table MUST NOT be left with `#______` placeholders, filled in
from another project's palette, or chosen unilaterally by tooling. Every
proposal offered MUST already meet the 4.5:1 requirement of Principle III in
both appearances; on a sync, if the palette already in the project fails that
anywhere, keeping it is not one of the options and the failure MUST be stated
in the question.

<!-- PROJECT:palette -->
This project's ratified palette — a green health identity. Ratified unchanged
by the maintainer at the v2.1.0 sync (2026-08-03), against two alternative
full proposals that also met 4.5:1; the green identity and the already-paid
contrast audit carried the decision.

Tokens live as color sets in `Kalorias/Assets.xcassets/Palette/` (each with a
light and dark variant) and are exposed in
`Kalorias/DesignSystem/AppColor.swift` as `AppColor.<token>`.

The palette separates **text tokens** from **fill tokens**. A hue vivid enough
to work as a chart bar or a button fill is generally not legible as text on
`surfacePrimary`, so the two are not the same value. A `-Fill` token MUST NEVER
be placed behind a glyph; a text token MAY be used as a fill, but there is
rarely a reason to.

**Text and essential icons** — every one of these is verified ≥ 4.5:1 against
both surfaces in both appearances by `KaloriasTests/PaletteContrastTests`,
which resolves them from the asset catalog rather than from a copy of this
table:

| Token             | Role                                   | Light     | Dark      |
| ----------------- | -------------------------------------- | --------- | --------- |
| `brandPrimary`    | Primary brand text / selected tab      | `#22813F` | `#3DDC6E` |
| `success`         | On-track / within goal                 | `#23813B` | `#4CD469` |
| `caution`         | Mild caution (yellow step)             | `#916A09` | `#F2D24B` |
| `warning`         | Approaching a limit                    | `#A36108` | `#FFB84D` |
| `danger`          | Over budget / destructive              | `#D62D2D` | `#FF5C5C` |
| `textPrimary`     | Primary text                           | `#10140F` | `#F2F5F0` |
| `textSecondary`   | Secondary / supporting text            | `#6B6F6A` | `#A2A8A0` |

**Fills only** — chart marks, badges, macro dots, and `.tint` on a prominent
button (where the tint is the button's fill and the system derives a
contrasting label). Carry no contrast assertion, because each is always paired
with a legible text label:

| Token              | Role                                  | Light     | Dark      |
| ------------------ | ------------------------------------- | --------- | --------- |
| `brandPrimaryFill` | Brand fill; matches AccentColor       | `#2FB457` | `#3DDC6E` |
| `successFill`      | On-track fill                         | `#2EA84C` | `#4CD469` |
| `cautionFill`      | Mild-caution fill                     | `#B8860B` | `#F2D24B` |
| `warningFill`      | Approaching-a-limit fill              | `#E8890C` | `#FFB84D` |
| `dangerFill`       | Over-budget fill                      | `#D93A3A` | `#FF5C5C` |
| `macroProtein`     | Protein macro accent                  | `#E8384F` | `#FF6B7F` |
| `macroCarbs`       | Carbohydrate macro accent             | `#F5A623` | `#FFC24D` |
| `macroFat`         | Fat macro accent                      | `#5A6CEA` | `#8A97FF` |

**Surfaces**:

| Token             | Role                                   | Light     | Dark      |
| ----------------- | -------------------------------------- | --------- | --------- |
| `surfacePrimary`  | App background                         | `#F7F8F6` | `#0E120F` |
| `surfaceElevated` | Cards / grouped content                | `#FFFFFF` | `#1A1F1B` |

`macroProtein`/`macroCarbs`/`macroFat` are the app's central visual signal and
MUST be paired with a non-color cue (label or value) wherever a macro
breakdown is shown, so the signal survives color-blindness. That pairing is
also why they carry no contrast assertion — they are dots beside a legible
label, never the carrier of the information themselves.

The two surfaces above are only 1.065:1 apart in light and 1.129:1 in dark, so
**tone alone does not separate a card from the background**. Card elevation
comes from the shadow in `Kalorias/DesignSystem/CardSurface.swift`, not from
the palette. Darkening `surfacePrimary` to buy separation was measured and
rejected: it gains almost nothing while pushing the text tokens above back
below 4.5:1.
<!-- /PROJECT:palette -->

Changing a token's hex or adding a token is a design-system change and MUST
update both this table and the corresponding color set in the same change.

## Design Reference: the `apple-design` skill

Every project MUST install the `apple-design` skill from
<https://github.com/emilkowalski/skills/tree/main/skills> at
`.claude/skills/apple-design/SKILL.md`, and UI work MUST follow its
principles.

**Read this caveat before applying it.** The skill is written for the web —
its examples are CSS, Pointer Events, `requestAnimationFrame`, and JS spring
libraries. Its *principles* transfer to SwiftUI; its *code* does not. Porting
a CSS snippet into this codebase is a misapplication of the skill.

**This skill is the authority on surface treatment.** Principle III delegates
to it deliberately: the constitution does not decide that a card is glass, a
material, or an opaque fill — the skill's guidance on materials and depth
does, screen by screen.

The principles that bind here:

- **Materials and depth decide surfaces.** Translucency is a functional layer
  that conveys hierarchy, not a finish applied everywhere. Heavier materials
  separate structural regions; lighter ones draw attention to interactive
  elements. A light translucent surface is never stacked on another —
  legibility collapses. Larger surfaces read as thicker (stronger blur, deeper
  shadow) than small chips. A focused, blocking task pairs its surface with a
  dimming scrim; a parallel, non-blocking panel uses translucency and offset
  *without* one, so the flow is not broken. Where content meets floating
  chrome, fade the edge rather than drawing a hairline divider. Where none of
  this applies, an opaque surface is the correct answer — and choosing it is
  not a compromise.
- **Response.** Feedback appears on touch-**down**, not on release. Every
  interactive control is a `Button` with a style that reads
  `configuration.isPressed`; a bare `.onTapGesture` on an interactive element
  is forbidden, because it gives neither touch-down feedback nor
  cancel-by-dragging-away.
- **Direct manipulation and interruptibility.** Anything the user can drag
  tracks the finger 1:1 and can be grabbed and redirected mid-flight, starting
  from its current on-screen value rather than jumping.
- **Prefer the platform's gestures.** Where UIKit/SwiftUI already implements
  an interaction (list reordering, sheet dismissal, scrolling), use it rather
  than hand-rolling a `DragGesture`. The system already ships the velocity
  handoff, momentum projection, rubber-banding at boundaries, edge
  auto-scroll, and haptics that the skill asks for; a bespoke reimplementation
  is worse on every one of those axes.
- **Motion is behaviour, not decoration.** Springs, not fixed-duration
  curves, for anything a user can touch. The house default is critically
  damped (no overshoot). Bounce is reserved for motion a gesture actually
  threw — a flick or a drag release.
- **Spatial consistency.** A surface leaves along the path it arrived by.
- **Restraint in feedback.** Haptics are reserved for meaningful moments
  (commit, success, error, snap). Where the system already emits a haptic,
  the app MUST NOT add a second one on the same event.
- **Reduced motion is a first-class path.** Under Reduce Motion, springs,
  slides, parallax, and overshoot are replaced by a short cross-fade or an
  immediate state change, and every interaction remains fully completable.
  This MUST be routed through one shared animation helper, not checked per
  view.
- **Typography.** Size-specific letter-spacing and the platform system font,
  as encoded in the type scale above.

## Development Workflow

Features are developed on a branch per feature (`###-feature-name`), following
the spec → plan → tasks → implement flow. Every feature's plan MUST pass the
Constitution Check gate (defined in `.specify/templates/plan-template.md`)
before implementation begins and again after design is complete.

### Clarification Gate (NON-NEGOTIABLE)

At the end of **every** `/speckit-specify` run and **every** `/speckit-plan`
run — before the next command in the flow begins — every open question,
ambiguity, contradiction, missing decision, or error discovered MUST be put to
the maintainer and answered. Nothing is left in doubt and nothing is settled by
assumption.

- Each question MUST offer **exactly three** concrete options wherever the
  problem admits three, with one marked **Recommended** and a one-line reason
  for that recommendation. Where three genuinely distinct options do not exist,
  the question says so and offers the ones that do — padding a question with a
  straw option is worse than offering two.
- Options MUST be real, mutually exclusive, and specific enough to act on
  ("store the total as `Decimal` in minor units" — not "handle money
  correctly"). The maintainer may always answer something outside the three;
  that possibility is implicit and need not be listed as an option.
- Questions MUST be asked as a batch at the gate rather than dribbled out
  mid-run, and each one MUST say what it blocks, so the maintainer can see the
  cost of each answer.
- Answers MUST be written back into the spec or plan **in the same run**, in
  the maintainer's words where they gave them. No `[NEEDS CLARIFICATION]`
  marker, TODO, placeholder, or open question may survive into
  `/speckit-tasks` or `/speckit-implement`.
- If a run genuinely surfaces nothing open, that MUST be stated explicitly —
  the gate is passed out loud, never skipped in silence.

Pull requests MUST confirm, before merge:

- build succeeds with **zero warnings** under Swift 6 strict concurrency;
- all unit tests pass, and new/changed business logic has corresponding unit
  tests;
- all new user-facing strings have English **and** Spanish values;
- all colors come from the tokenized palette, and the design-system audits
  (no color literals, no raw font calls, no numeric spacing literals, no inline
  `.spring(...)`/`.easeInOut(...)` in the view layer) come back clean;
- every new or changed observable state transition is animated from the motion
  vocabulary, and the flow was checked once with Reduce Motion on;
- any translucent surface uses Apple's own APIs directly, and its use is
  justifiable against the `apple-design` guidance rather than applied by
  default;
- no `glassCard`, `glassActionButton`, or equivalent glass-convenience wrapper
  exists anywhere in the project;
- no networked URL is built from a literal — every one comes from
  `BackendEnvironment`, and the release path resolves to production;
- new/changed UI has been verified in both light and dark appearances.

UI tests (Principle II) are off by default and are authored and run only when
the maintainer explicitly requests UI-test work; when that happens, the UI
suites MUST pass before the corresponding work is considered release-ready.

Git commits and pushes are exclusively a human, manually-initiated action.
Automated tooling and assistants MUST NOT run `git commit` or `git push`
automatically, and MUST NOT proactively offer or prompt to do so. They may
stage or describe changes only when the maintainer explicitly requests that
specific action; absent such an explicit request, they leave version-control
operations entirely to the maintainer.

## Governance

This constitution supersedes any conflicting practice, tooling default, or
ad hoc convention. Amendments require:

1. A documented rationale for the change (what problem it solves or what
   gap it closes).
2. An update to this file, including the Sync Impact Report header and a
   version bump following semantic versioning:
   - **MAJOR**: backward-incompatible governance changes or removal/
     redefinition of an existing principle.
   - **MINOR**: a new principle or materially expanded guidance added.
   - **PATCH**: clarifications, wording, or non-semantic fixes.
3. A review of dependent templates (`plan-template.md`, `spec-template.md`,
   `tasks-template.md`) to confirm they remain consistent with the change.

A change to a SHARED section is a change to the **Template Constitution**
(`~/Projects/TemplateConstitution.md`) first; it is then propagated to every
project, and each project bumps its own version and records the sync. A
project MUST NOT quietly diverge from a SHARED section: if a project needs
different behaviour, either the template changes for everyone or the project
documents the deviation in its plan's Complexity Tracking section.

A change to a PROJECT block affects only that project.

**Project extensions.** A project MAY add PROJECT blocks beyond the ones this
template defines, on one condition: the extension is **additive**. It MUST
satisfy the SHARED rule it extends and then go further — never relax it, narrow
it, or replace it. An app shipping a third language on top of the mandatory
English and Spanish is additive and needs no permission; an app declaring it
ships Spanish only is not, and that is either a change to the template for
everyone or a documented deviation in Complexity Tracking, never a local block.

An extension block MUST state, inside the block, which SHARED rule it extends
and what it adds on top. Given that, it is an extension and not a divergence,
and the sync tooling MUST NOT report it as one — the check that matters is that
no required block is missing and no shared text was edited. What an extension
block may never be is a rule that contradicts the shared text, filed under a
name the tooling does not recognise.

**Numbering.** An extension that adds a principle and numbers it in the shared
Roman sequence is inviting a collision: the next principle this template adds
takes the next free numeral, and the project then holds two principles with the
same number and a spec history pointing at the wrong one. Prefer a distinct
label over a number in the shared run. Where a collision does happen anyway,
renumbering the extension is right in principle and usually not worth it in
practice — cross-references in closed feature specs recorded a decision under
the number it had at the time, and rewriting them rewrites the record.

All plans and PRs MUST verify compliance with this constitution; any
deviation MUST be justified in the plan's Complexity Tracking section rather
than silently introduced.

**Version**: 4.0.0 | **Ratified**: 2026-07-24 | **Last Amended**: 2026-09-01
**Template**: TemplateConstitution v3.0.2
