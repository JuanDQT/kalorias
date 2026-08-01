# Specification Quality Checklist: Fix Analysis Reliability, Ingredient Thumbnails & Bottom-Bar Clearance

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

All 16 items pass. 20 functional requirements, 9 success criteria, 0 open markers.

### Both root causes were reproduced before this spec was written

No clarification markers were needed because nothing was left to guess — the causes were measured.

**1. The analysis regression (severe).** Three variants of the same request were sent to the real
analysis service with the same photo:

| Region field in the request | Outcome |
|---|---|
| **Optional** — what feature 006 shipped | Reply ran away: hit the output-token ceiling, returned ~65,000 characters of malformed digits, **unusable → analysis fails, no meal saved** |
| Absent — the pre-006 behaviour | Clean reply, 3 foods, works |
| **Required** | Clean reply, 3 foods, **a region for every food** |

This is a regression in the app's core function, not a cosmetic issue, which is why it is US1/P1
ahead of the two symptoms the user actually reported. A failed analysis loses a calorie record.

The same replies also **confirmed the coordinate interpretation**: returned regions matched where
the foods actually sat in the photo, so no coordinate change is expected.

**2. The clearance failure.** Feature 006's safe-area inset does not reach the scrolling content of
a details screen pushed inside the History tab's navigation. Reproduced with a scrollable meal
through the real navigation path: a middle row sits entirely behind the bar and the final row cannot
be brought clear.

### A process defect is specified as a requirement

**FR-014** requires the clearance fix to be verified by scrolling each screen to its end, and
explicitly rejects any verification that cannot tell "content is inset" from "content happens to be
short enough to fit". This is in the spec because feature 006 was verified with three ingredients
that fitted on one screen — a test incapable of detecting the bug it was meant to confirm was fixed.
Treating that as a requirement rather than a note is deliberate.

### The design error worth carrying forward

**FR-006** states that demanding the region in the *request* and tolerating its absence in the
*parser* must both hold at once. Feature 006 conflated the two: it relaxed the request in order to
make the parser's tolerance meaningful, and that single decision caused the outage. The distinction
is now a requirement so it cannot be collapsed again.

### Deliberately left open for planning

The clearance *mechanism* is not prescribed. FR-011 to FR-015 constrain the outcome — scrollable
range extends past the bar, nothing overlapped, bar stays floating and translucent, no double
inset — and leave the technique to the plan, since the previous attempt failed on a subtlety of how
insets propagate.

- Items marked incomplete require spec updates before `/speckit-clarify` or `/speckit-plan`
