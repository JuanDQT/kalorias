# Phase 1 Data Model: Fix Analysis Reliability, Ingredient Thumbnails & Bottom-Bar Clearance

**Feature**: `007-fix-scroll-and-boxes` | **Date**: 2026-07-26

> **No stored data changes at all.** No new field, no new type, no migration, no store version bump.
> The `region` field added by feature 006 already exists on `StoredFood` and `FoodItem`. What changes
> is **how the region is requested** from the analysis, and **where the layout clearance is applied**.
> This section therefore documents a *request contract* change and a *layout constant*, not entities.

---

## Unchanged types (listed so their stability is explicit)

| Type | Status | Why it is not touched |
|---|---|---|
| `FoodRegion` | **unchanged** | Real replies returned regions whose positions matched the foods in the photo, confirming the existing top/left, 0–1000, proportional interpretation. No coordinate change is warranted. |
| `FoodThumbnailCropper` | **unchanged** | Verified working: seeded regions produced correct per-quadrant crops through the real persistence and navigation path. It was never the broken part. |
| `StoredFood.region` | **unchanged** | Already optional and already persisted inside the `foodsData` JSON. |
| `FoodItem.region` | **unchanged** | Already optional. |
| `MealEntry` | **unchanged** | No stored property added; no migration. |
| `CalorieColorStep` / `CalorieColorScale` | **unchanged** | Colour behaviour is out of scope (FR-016). |

---

## The request contract change (US1)

### Per-food `box` — from optional to **required**

| Aspect | Before (feature 006) | After |
|---|---|---|
| Present in `foods.items.properties` | yes | yes (identical shape: `ymin`, `xmin`, `ymax`, `xmax`, integers) |
| Listed in `foods.items.required` | **no** | **yes** |
| Parser behaviour on a missing box | tolerated → `region == nil` | **tolerated → `region == nil` (unchanged)** |
| Parser behaviour on a malformed box | tolerated → `region == nil` | **tolerated → `region == nil` (unchanged)** |
| Observed effect | runaway reply, `MAX_TOKENS`, meal lost | clean reply, a box for every food |

**The invariant that matters**

> Strictness of the **request** and tolerance of the **parser** are independent, and both must hold.

Feature 006 relaxed the request in order to make the parser's tolerance meaningful. That single
conflation caused the outage. Stated as a rule (FR-006):

1. The schema **demands** a box for every food. This is what keeps generation stable.
2. The parser **never requires** one. A missing, incomplete or wrong-typed box costs that food's
   thumbnail and nothing else.
3. Neither property may be weakened to achieve the other.

### New generation bound

| Setting | Value | Purpose |
|---|---|---|
| `maxOutputTokens` | generous for dozens of foods, far below the default ceiling | Converts a runaway reply from "burn the whole budget, then fail" into "fail fast and cheaply" (FR-003). Observed healthy replies were 256–388 characters, so legitimate output is nowhere near the bound. |

A reply truncated by this bound is malformed, so it takes the **existing** failure path: an
actionable error, nothing saved (FR-004).

---

## The layout constant (US3)

### `BottomBar` clearance

| Aspect | Value / rule |
|---|---|
| What it is | The vertical space a scrolling screen must reserve at its bottom so its final element can clear the floating bar |
| Where it lives | **One** constant, owned by `BottomBar` — the type whose height it describes |
| Who reads it | The three scroll containers: meal details, the history list, the progress tab |
| Where it is applied | **Inside** each scroll container, as a bottom content margin on the scroll content |
| Where it is **not** applied | Not at the root. A root-level safe-area inset is consumed by `NavigationStack` and never reaches the scrolling content (research R3) |

**Measured justification**

```
root ZStack content   safeAreaInsets.bottom = 148.0   height = 746.0   ← inset applied
pushed detail view    safeAreaInsets.bottom =   0.0   height = 956.0   ← inset gone, full screen
```

**Invariants**

1. Exactly **one** source of truth for the value. It has already been duplicated once (feature 005
   hardcoded it in one screen; feature 006 deleted that and replaced it with an inset that did
   nothing, leaving details with no clearance).
2. Exactly **one** mechanism. The root-level inset is removed, not left underneath, so no screen can
   be inset twice (FR-015).
3. The bar itself is unchanged — same position, same translucency, content still passes behind it
   while scrolling (FR-013).

---

## Validation rules summary

| Rule | Source | Enforced by |
|---|---|---|
| `box` is required in the schema | FR-001 | schema `required` list; asserted by a regression test |
| A missing/garbage box never blocks a save | FR-005 | existing lenient parse, kept and re-tested |
| Request-strictness and parser-tolerance both hold | FR-006 | the two rules above are tested separately |
| A runaway reply fails fast | FR-003 | `maxOutputTokens` |
| A truncated reply is a clean failure | FR-004 | existing error path; nothing saved |
| Clearance reaches the scrollable range | FR-011 | content margin inside each scroll container |
| One clearance value | Principle I | single constant on `BottomBar` |
| No double inset | FR-015 | root-level inset removed |
| No stored-data change | FR-016, FR-017 | no field, type or migration touched |
