//
//  AppColor.swift
//  Kalorias
//
//  Design-system color tokens for Kalorias.
//
//  Per the project constitution (Principle III — Tokenized color), every color
//  used in the UI MUST come from here. These tokens are backed by the color
//  sets in `Assets.xcassets/Palette` and reference the type-safe asset symbols
//  Xcode generates from them, so each one adapts automatically between light
//  and dark appearances (Principle VI). Do NOT use raw
//  `Color(red:green:blue:)` / hex literals inside views — add a new color set
//  to the palette and expose it here instead.
//
//  TEXT TOKENS vs FILL TOKENS
//  --------------------------
//  Principle III requires text and essential icons to measure at least 4.5:1
//  against their background. A hue bright enough to work as a chart bar or a
//  button fill is generally NOT legible as text on `surfacePrimary`, so the
//  palette keeps the two apart:
//
//    `success`      — TEXT and essential icons. Verified >= 4.5:1 against both
//                     surfaces in both appearances by `PaletteContrastTests`.
//    `successFill`  — FILLS ONLY. Never put this behind a glyph. Not contrast
//                     checked, because it is always paired with a legible text
//                     label, which is the non-color cue the palette requires.
//
//  Reach for the `-Fill` variant for bar marks, dots, and `.tint` on a
//  prominent button (where the tint IS the fill and the system picks the
//  label color). Reach for the plain token whenever the color lands on text.
//

import SwiftUI

/// The Kalorias color palette. Reference tokens as `AppColor.brandPrimary`.
enum AppColor {

    // MARK: Brand

    /// Primary brand color, for **text and essential icons** — fresh nutrition
    /// green, darkened to clear 4.5:1 on `surfacePrimary` in light appearance.
    static let brandPrimary = Color(.brandPrimary)
    /// Primary brand color for **fills only** — the app's accent hue at full
    /// vibrancy. Used for `.tint` on prominent buttons, never behind a glyph.
    static let brandPrimaryFill = Color(.brandPrimaryFill)

    // MARK: Macronutrients

    // Fill-only by construction: these are rendered as small dots beside a
    // `textSecondary` label, never as text. No text variant exists because
    // nothing draws a glyph in them.

    /// Protein macro accent. **Fills only.**
    static let macroProtein = Color(.macroProtein)
    /// Carbohydrate macro accent. **Fills only.**
    static let macroCarbs = Color(.macroCarbs)
    /// Fat macro accent. **Fills only.**
    static let macroFat = Color(.macroFat)

    // MARK: Status — text

    /// Positive / on-track status (e.g. within goal), for **text and icons**.
    static let success = Color(.success)
    /// Mild caution — the yellow step between `success` and `warning`, for
    /// **text and icons**. Deliberately a dark goldenrod in light mode: a
    /// brighter yellow is not legible on `surfacePrimary`.
    static let caution = Color(.caution)
    /// Cautionary status (e.g. approaching a limit), for **text and icons**.
    static let warning = Color(.warning)
    /// Negative / destructive status (e.g. over budget, delete actions), for
    /// **text and icons**.
    static let danger = Color(.danger)

    // MARK: Status — fills

    /// Positive / on-track status. **Fills only** (chart marks, badges).
    static let successFill = Color(.successFill)
    /// Mild caution. **Fills only** (chart marks, badges).
    static let cautionFill = Color(.cautionFill)
    /// Cautionary status. **Fills only** (chart marks, badges).
    static let warningFill = Color(.warningFill)
    /// Negative / destructive status. **Fills only** (chart marks, badges).
    static let dangerFill = Color(.dangerFill)

    // MARK: Surfaces & text

    /// App background surface.
    static let surfacePrimary = Color(.surfacePrimary)
    /// Elevated surface for cards and grouped content.
    static let surfaceElevated = Color(.surfaceElevated)
    /// Primary text color.
    static let textPrimary = Color(.textPrimary)
    /// Secondary / supporting text color.
    static let textSecondary = Color(.textSecondary)
}
