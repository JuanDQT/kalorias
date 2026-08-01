# Phase 1 Contracts: Fix Analysis Reliability, Ingredient Thumbnails & Bottom-Bar Clearance

**Feature**: `007-fix-scroll-and-boxes` | **Date**: 2026-07-26

Two contracts change: the **request** sent to the analysis service, and the **layout clearance** each
scrolling screen must reserve. Nothing else in the app's surface moves.

---

## 1. Analysis request contract (US1)

### 1.1 Schema delta

```
foods.items.required :  ["name", "calories"]
                    →  ["name", "calories", "box"]
```

`box`'s own shape is **unchanged** from feature 006 — an `OBJECT` with required integer `ymin`,
`xmin`, `ymax`, `xmax` on Gemini's 0–1000 normalized scale, measured from the top and left edges.

### 1.2 Generation config addition

```
generationConfig.maxOutputTokens = <bound sized for dozens of foods>
```

### 1.3 Contract guarantees

| # | Guarantee | Requirement | How it is checked |
|---|---|---|---|
| A1 | `"box"` appears in `foods.items.required` | FR-001 | **regression test on the schema** |
| A2 | `box`'s property shape is unchanged (four required integer edges) | FR-008 | regression test |
| A3 | `maxOutputTokens` is set and is far above a realistic reply | FR-003 | test asserts presence and a sane floor |
| A4 | A reply with **no** `box` on a food still parses; that food gets `region == nil` | FR-005 | existing decoding test, kept |
| A5 | A reply with a **malformed** `box` still parses the whole meal | FR-005 | existing decoding test, kept |
| A6 | A truncated/unparseable reply raises the existing analysis error and saves nothing | FR-004 | existing decoding test, kept |
| A7 | Name/calories/macro decoding is byte-for-byte unchanged | FR-016 | existing tests must stay green |

### 1.4 The rule that must not be collapsed again

> **A1 (the request demands a box) and A4/A5 (the parser tolerates its absence) must both hold.**

Feature 006 satisfied A4/A5 by *breaking* A1, on the reasoning that a required field could block a
save. It cannot: the parser never consults the schema. The measured consequence of relaxing A1 was a
runaway reply that lost the meal entirely. A1 and A4/A5 are therefore tested **separately**, so no
future change can trade one for the other silently.

---

## 2. Bottom-bar clearance contract (US3)

### 2.1 The shared constant

```swift
extension BottomBar {
    /// Vertical space a scrolling screen must reserve so its last element can
    /// clear the floating bar.
    static let scrollClearance: CGFloat = <value>
}
```

**One** declaration. All three scroll containers reference it. No screen may hardcode its own number.

### 2.2 Application points

| Screen | Container | Applies clearance |
|---|---|---|
| Meal details | `ScrollView` in `MealDetailsView` | yes |
| History list | `List` in `HistoryView` | yes |
| Progress tab | `ScrollView` in `ProgressTabView` | yes |
| Root | `ZStack` in `RootView` | **no — the root-level `safeAreaInset` is removed** |

### 2.3 Contract guarantees

| # | Guarantee | Requirement |
|---|---|---|
| C1 | Each scroll container's scrollable range extends past the bar, so its final element can be brought fully into view | FR-011 |
| C2 | Content that fits without scrolling is not overlapped | FR-012 |
| C3 | The bar keeps its position, size, translucency and native Liquid Glass treatment; content still passes behind it while scrolling | FR-013 |
| C4 | Exactly one clearance mechanism is in effect — the root-level inset is gone, so nothing is inset twice | FR-015 |
| C5 | Exactly one clearance value exists in the codebase | Principle I |
| C6 | The camera `fullScreenCover` and the surface background are unaffected | FR-016 |

### 2.4 Why not at the root — measured

```
root ZStack content   safeAreaInsets.bottom = 148.0   height = 746.0
pushed detail view    safeAreaInsets.bottom =   0.0   height = 956.0
```

`NavigationStack` consumes the inset and hands its destination a full-screen, zero-bottom-inset
environment. Both tabs wrap themselves in a `NavigationStack`, so a root-level inset is unreachable
from any scrolling content. This is why feature 006's change had no effect.

---

## 3. Screen state contracts

No screen gains or loses a state. Only two behaviours change:

| Screen | Change | Unchanged |
|---|---|---|
| `MealDetailsView` | bottom content margin added | header photo, calorie figure and its colour, date line, row layout, thumbnails, placeholder, glass treatment, accessibility identifiers |
| `HistoryView` | bottom content margin added on the `List` | week sections, ordering, headers, row colours, empty state, navigation |
| `ProgressTabView` | bottom content margin added | both widgets, empty state |
| `RootView` | root `safeAreaInset` removed; bar returns to a floating overlay | bar appearance and position, tab switching, camera flow |

**Thumbnails (US2)** require **no view change at all**. The crop pipeline was verified working; it
was starved of regions. Once US1 lands, rows populate on their own.

---

## 4. Accessibility contract

Unchanged. All existing identifiers stay: `screen.progress`, `progress.*`, `history.*`,
`mealDetails.screen`, `mealDetails.total`, `mealDetails.foodList`, `mealDetails.food.thumbnail`.
Thumbnails remain decorative and hidden from assistive technology.

---

## 5. Localization contract

**No new keys expected.** This feature adds no visible copy — a truncated reply reuses the existing
analysis error message. If implementation finds that error too vague for the truncation case, any new
key needs EN + ES with a translator comment (FR-019), and must not be left unused (Principle I).

---

## 6. Design-system contract

**No new token.** No colour, palette or constitution-table change. The only design-system edit is the
`scrollClearance` constant on `BottomBar`, which describes existing geometry rather than introducing
a new visual value.
