# Specification Quality Checklist: Meal Details Refinements

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-07-26
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Notes

All 16 items pass. 22 functional requirements, 10 success criteria, 0 open markers.

### Iteration history

1. **Fix**: a requirement block had been written inside User Story 3's acceptance scenarios;
   moved into the Requirements section.
2. **Clarification resolved (was FR-013)**: the thumbnail source was genuinely open, because the
   codebase has **no per-ingredient image data at all** — `MealEntry` stores one `imageFileName`
   for the whole meal, `StoredFood` holds only name/calories/macros, and the analysis prompt never
   requests per-food regions. Answered: **crops of the meal's own photo**, via regions requested
   from the analysis and stored per food. Rejected alternatives are recorded in Assumptions
   (category icons: not a picture of the user's food; third-party image lookup: adds a networked
   external service the constitution restricts and breaks SC-006 offline).
3. **Fix**: renumbered success criteria so SC-001…SC-010 read in order after insertion.

### What the clarification changed about scope

This is no longer a presentation-only feature. US3 now reaches into the analysis pipeline (a new
per-food region in the prompt and response) and the persisted per-food data. Two guardrails were
added specifically so that reach cannot cause harm:

- **FR-021**: a failed or partial region response MUST NOT prevent a meal being saved. Regions are
  an enhancement, never a condition for recording calories.
- **FR-017**: regions are additive; meals saved without them stay valid and openable.

### Risks carried forward into planning, deliberately not designed away

- **Existing meals will never show crops.** Regions cannot be recovered without re-analyzing, so
  every already-saved meal shows placeholders permanently. Accepted in Assumptions; a backfill is
  out of scope.
- **Region accuracy is a model guess.** Loose boxes, overlaps and omissions are expected; the spec
  degrades to a placeholder rather than insisting on a crop, and treats a slightly loose crop as
  acceptable.
- **Regions must be stored proportionally**, not in pixels, because feature 003 saves a downsized
  JPEG rather than the original photo. A pixel-based region would silently mis-crop.

### Note on priority ordering

US1 (the bottom-bar defect) is P1 ahead of the two cosmetic/feature items, because it hides
information the user opened the screen to read. US1 and US2 are also independent of the analysis
work in US3, so the first two stories remain shippable on their own.

- Items marked incomplete require spec updates before `/speckit-clarify` or `/speckit-plan`
