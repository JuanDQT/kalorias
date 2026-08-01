<!--
Sync Impact Report
==================
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
-->

# Kalorias Constitution

## Product Overview

<!-- PROJECT:overview -->
Kalorias is a native iOS app for counting calories that starts from a
**photo**. The core flow is:

1. The user takes or picks a **photo of their food**.
2. The image is sent to **Google Gemini**, which analyzes it and estimates the
   food's **calorie count** (and macronutrients).
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
- The app MUST follow the MV (Model–View) pattern with observable State:
  views are thin and derive their content from state, and there is no separate
  per-view ViewModel/Controller layer (no MVVM). Views observe state directly.
- Mutable application and feature state MUST live in **Stores** — observable,
  `@MainActor`-isolated reference types (e.g. `@Observable` classes) that own a
  slice of state and expose the intents that mutate it. Business logic and
  mutations MUST NOT live in view bodies; views call Store intents.
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
opinionated MV + Stores + Router architecture keeps state ownership and
navigation predictable, makes logic unit-testable, and prevents the codebase
from drifting into inconsistent patterns as it grows.

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
**Google Gemini** is the one approved external service: it powers the core
photo-to-calories estimation (see Product Overview) and cannot be replaced by
an on-device Apple framework at the required quality. Its use MUST be confined
to a dedicated service/Store boundary (never called from view bodies), MUST
run off the main thread, and MUST degrade gracefully when the network or the
model is unavailable. API keys and credentials MUST NOT be committed to the
repository. Any additional external/networked dependency beyond Gemini still
requires the justification above.
<!-- /PROJECT:external-services -->

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
- **Motion** — the app's animation vocabulary (see the apple-design section
  below). Views MUST NOT construct `.spring(...)`/`.easeInOut(...)` inline.

These are auditable by grep, and that is the point: a review MUST be able to
confirm zero color literals, zero raw `.font(.body)`-style calls, and zero
numeric spacing literals in the view layer.

<!-- PROJECT:palette -->
This project's ratified palette — a green health identity.

Tokens live as color sets in `Kalorias/Assets.xcassets/Palette/` (each with a
light and dark variant) and are exposed in
`Kalorias/DesignSystem/AppColor.swift` as `AppColor.<token>`.

| Token             | Role                                   | Light     | Dark      |
| ----------------- | -------------------------------------- | --------- | --------- |
| `brandPrimary`    | Primary brand; matches AccentColor     | `#2FB457` | `#3DDC6E` |
| `brandSecondary`  | Energy accent / calls to action        | `#FF8A0A` | `#FFB340` |
| `macroProtein`    | Protein macro accent                   | `#E8384F` | `#FF6B7F` |
| `macroCarbs`      | Carbohydrate macro accent              | `#F5A623` | `#FFC24D` |
| `macroFat`        | Fat macro accent                       | `#5A6CEA` | `#8A97FF` |
| `success`         | On-track / within goal                 | `#2EA84C` | `#4CD469` |
| `caution`         | Mild caution (yellow step)             | `#B8860B` | `#F2D24B` |
| `warning`         | Approaching a limit                    | `#E8890C` | `#FFB84D` |
| `danger`          | Over budget / destructive              | `#D93A3A` | `#FF5C5C` |
| `surfacePrimary`  | App background                         | `#F7F8F6` | `#0E120F` |
| `surfaceElevated` | Cards / grouped content                | `#FFFFFF` | `#1A1F1B` |
| `textPrimary`     | Primary text                           | `#10140F` | `#F2F5F0` |
| `textSecondary`   | Secondary / supporting text            | `#6B6F6A` | `#A2A8A0` |

`macroProtein`/`macroCarbs`/`macroFat` are the app's central visual signal and
MUST be paired with a non-color cue (label or value) wherever a macro
breakdown is shown, so the signal survives color-blindness.

TODO(CONTRAST_AUDIT): several tokens above were chosen before the measured
4.5:1 rule in Principle III existed and have not been verified against both
surfaces in both appearances. They MUST be audited, and adjusted where they
fail, in the first feature that touches them.
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

Pull requests MUST confirm, before merge:

- build succeeds with **zero warnings** under Swift 6 strict concurrency;
- all unit tests pass, and new/changed business logic has corresponding unit
  tests;
- all new user-facing strings have English **and** Spanish values;
- all colors come from the tokenized palette, and the design-system audits
  (no color literals, no raw font calls, no numeric spacing literals in the
  view layer) come back clean;
- any translucent surface uses Apple's own APIs directly, and its use is
  justifiable against the `apple-design` guidance rather than applied by
  default;
- no `glassCard`, `glassActionButton`, or equivalent glass-convenience wrapper
  exists anywhere in the project;
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

All plans and PRs MUST verify compliance with this constitution; any
deviation MUST be justified in the plan's Complexity Tracking section rather
than silently introduced.

**Version**: 3.0.0 | **Ratified**: 2026-07-24 | **Last Amended**: 2026-07-27
**Template**: TemplateConstitution v1.0.0
