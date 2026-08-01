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

import SwiftUI

/// The Kalorias color palette. Reference tokens as `AppColor.brandPrimary`.
enum AppColor {

    // MARK: Brand

    /// Primary brand color — fresh nutrition green. Matches the app's accent.
    static let brandPrimary = Color(.brandPrimary)
    /// Secondary brand color — energy amber, for highlights and calls to action.
    static let brandSecondary = Color(.brandSecondary)

    // MARK: Macronutrients

    /// Protein macro accent.
    static let macroProtein = Color(.macroProtein)
    /// Carbohydrate macro accent.
    static let macroCarbs = Color(.macroCarbs)
    /// Fat macro accent.
    static let macroFat = Color(.macroFat)

    // MARK: Status

    /// Positive / on-track status (e.g. within goal).
    static let success = Color(.success)
    /// Mild caution — the yellow step between `success` and `warning`. Used for
    /// the second step of the history calorie scale. Deliberately a dark
    /// goldenrod in light mode: this token is rendered as text, and a brighter
    /// yellow is not legible on `surfacePrimary`.
    static let caution = Color(.caution)
    /// Cautionary status (e.g. approaching a limit).
    static let warning = Color(.warning)
    /// Negative / destructive status (e.g. over budget, delete actions).
    static let danger = Color(.danger)

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
