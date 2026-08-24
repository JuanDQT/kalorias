//
//  AppSpacing.swift
//  Kalorias
//
//  The app's spacing ramp. Every padding, inset and gap comes from here — the
//  design system "owns, in one place each", a single ramp that all spacing is
//  drawn from (constitution, Design System & Color Tokens).
//
//  A 4-POINT RAMP, ratified with the maintainer at feature 009's Clarification
//  Gate. It was chosen because it is the ramp the app is already closest to:
//  the paddings in place read 4, 6, 12, 14, 16, 20, 24 and 32, and all but two
//  of those are already steps of it.
//
//  ADOPTION IS DELIBERATELY PARTIAL FOR NOW. The constitution requires the
//  missing piece to be built by the feature that needs it, "minimally and in one
//  place", not adopted app-wide in the same run. Feature 009 uses it for the
//  copy it adds; converting the rest is the business of the features that own
//  those screens.
//

import Foundation

nonisolated enum AppSpacing {
    /// Hairline gaps: between a glyph and the word next to it.
    static let xs: CGFloat = 4
    /// Within a single control or label group.
    static let sm: CGFloat = 8
    /// Between related rows.
    static let md: CGFloat = 12
    /// Between a control and its neighbour.
    static let lg: CGFloat = 16
    /// Between sections of a screen.
    static let xl: CGFloat = 24
    /// Screen margins on a focused, single-purpose view.
    static let xxl: CGFloat = 32
}
