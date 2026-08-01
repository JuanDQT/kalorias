# Specification Quality Checklist: Camera — Library Picker, Send Framing & Zoom

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

All 16 items pass. **27 functional requirements, 11 success criteria, 0 open markers.**

### A discovery that changes the framing requirement

Reading the camera code before writing this spec turned up something the request did not mention:
the live preview fills the screen by **cropping** the camera feed, while the captured photo is the
full sensor frame. **What the user frames is already not what gets sent.**

That reframes US2 from "add a decoration" to "correct a real mismatch". It is also why FR-010 insists
the sent area match the frame: drawing a frame on top of a preview that already misrepresents the
capture would make the problem worse, not better — the frame would look authoritative while still
being wrong.

### The open question, now resolved

"Un recuadro de lo que se va a enviar" admitted two readings with materially different work:

| Reading | What it means | Effort | Effect on analysis |
|---|---|---|---|
| Honest frame | Frame marks the **full captured area**; nothing cropped | Low | Unchanged |
| **Crop frame — CHOSEN** | Frame defines a **tighter region**; the sent image is cropped to it | Medium | Model receives a tighter picture, less background |
| Adjustable frame | As above, plus drag/resize | High | Same, with more control |

**Answered: the frame crops.** This turns US2 from a visual correction into a real capability, and it
carries consequences now written into the spec: content outside the frame never reaches the analysis
(FR-010), the crop must not be upscaled to hit a fixed size (FR-013), and zoom and the frame must
compose so they cannot disagree about what is sent (FR-021). SC-011 exists to prove the crop is real —
food placed outside the frame must appear in 0% of results.

### One consequence worth watching at plan time

The frame is drawn over a preview that is itself aspect-fill cropped, so mapping "what the user saw
inside the frame" to "what to crop from the captured photo" involves two transforms, not one
(FR-011). That is the part most likely to be got subtly wrong — a crop that is plausible but offset —
and it is why FR-011 is phrased as a correspondence requirement rather than a drawing requirement.

### Favourable facts established while investigating

- **No new permission is needed.** The system picker exposes only the chosen pictures, so there is no
  library-wide authorisation prompt and no new usage description (FR-007). `Info.plist` currently
  declares only a camera usage description, and that stays sufficient.
- **Zoom has no existing implementation** to reconcile with — nothing in the codebase touches zoom
  today, so FR-014–FR-018 are additive.
- **US1 and US3 are unblocked** by the open question and can be planned immediately. US1 is the MVP.

### Deliberate scope boundaries recorded in Assumptions

Front camera, flash, manual focus/exposure, editing picked photos, multi-photo analysis and
re-analysing existing meals are all explicitly out of scope, as is persisting the zoom level between
sessions.

- Items marked incomplete require spec updates before `/speckit-clarify` or `/speckit-plan`
