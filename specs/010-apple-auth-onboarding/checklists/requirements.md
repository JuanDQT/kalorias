# Specification Quality Checklist: Sign in with Apple After Local Onboarding

**Purpose**: Validate specification completeness and quality before planning

**Created**: 2026-09-08

**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] User value and the requested onboarding-first sequence are explicit.
- [x] Client behavior is separated from the self-contained backend handoff.
- [x] The first-run state transitions are understandable without reading source code.
- [x] All mandatory specification sections are complete.

## Requirement Completeness

- [x] No `[NEEDS CLARIFICATION]`, TODO or placeholder markers remain.
- [x] Requirements are testable and use stable MUST/SHOULD language.
- [x] Registration and onboarding upload are explicitly separate operations.
- [x] Zero answer transmission before committed registration is measurable.
- [x] Cancellation, termination, timeout, duplicate/replay and returning-user cases are defined.
- [x] Session storage, credential revocation, account deletion and log redaction are covered.
- [x] Existing onboarding/analysis authentication contracts that change are identified.
- [x] Local meal data remains local and is isolated between authenticated users.
- [x] Spanish/English, accessibility and appearance requirements are included.
- [x] Scope, assumptions, dependencies and out-of-scope work are explicit.

## Backend Handoff Completeness

- [x] Apple Developer configuration and server-only secrets are listed.
- [x] Apple credential/nonce verification and code exchange are defined.
- [x] Auth, refresh, logout, onboarding, analysis and deletion contracts are defined.
- [x] Database invariants and idempotency ownership are defined.
- [x] Health-data consent is separate, versioned and auditable.
- [x] Error codes, logging/redaction, revocation and deployment checks are defined.
- [x] A backend test matrix is included.

## Feature Readiness

- [x] Every user story is independently testable.
- [x] Success criteria are measurable.
- [x] The clarification gate is explicitly passed with no remaining open product question.
- [x] The spec is ready for `/speckit-plan`.

## Notes

- The previous `onboarding.completed` Boolean cannot express the new state machine. The spec makes
  it a derived/migration concern rather than the new source of truth.
- Feature 009's “no Authorization header” rule for `analyzeMeal`, and the current onboarding POST's
  equivalent rule, are deliberately superseded. The public questionnaire GET remains anonymous.
- V1 requests no Apple name/email scopes. This is a data-minimization decision, not an omission.
- Exact legal consent wording is not authored here; product/legal approval remains a release gate.
