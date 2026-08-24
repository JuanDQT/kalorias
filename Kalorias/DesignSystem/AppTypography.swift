//
//  AppTypography.swift
//  Kalorias
//
//  The app's type scale: named roles that define size, weight and letter-spacing
//  **together**, so a role is one decision rather than three made separately at
//  each call site (constitution, Design System & Color Tokens).
//
//  EVERY ROLE BUILDS ON A DYNAMIC TYPE TEXT STYLE. Fixed point sizes are
//  forbidden, and for a good reason beyond the rule: a hardcoded size does not
//  grow, so the screen quietly stops working at accessibility sizes rather than
//  failing visibly.
//
//  LETTER-SPACING IS SIZE-SPECIFIC — tighter on large display text, neutral on
//  body, slightly looser on the smallest labels. That is why it belongs to the
//  role and not to the call site.
//
//  ADOPTION IS DELIBERATELY PARTIAL FOR NOW, on the same terms as `AppSpacing`.
//  Feature 009 uses these roles for the copy it adds. Note that
//  `AnalysisResultView`'s total uses a fixed `.system(size: 56)`, which this
//  scale forbids: converting it belongs to the feature that owns that branch,
//  not to this one, which touches only the failure states.
//

import SwiftUI

nonisolated enum AppTypography {}

extension View {
    /// The big number a screen is about — a calorie total.
    func displayRole() -> some View {
        font(.largeTitle.weight(.bold)).tracking(-0.5)
    }

    /// The name of a row's subject: a food, a meal.
    func rowTitleRole() -> some View {
        font(.body.weight(.medium)).tracking(0)
    }

    /// The value a row carries, next to its title.
    func rowValueRole() -> some View {
        font(.body.weight(.semibold)).tracking(0)
    }

    /// A label above or beside a group of content.
    func sectionLabelRole() -> some View {
        font(.subheadline.weight(.semibold)).tracking(0.2)
    }

    /// Explanatory copy, and the label on an action that carries a message —
    /// including this feature's retry countdown.
    func supportingTextRole() -> some View {
        font(.body).tracking(0.1)
    }
}
