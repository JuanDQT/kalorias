//
//  GlassCard.swift
//  Kalorias
//
//  The app's shared Liquid Glass card surface.
//
//  Constitution Principle III requires that glass be produced with Apple's own
//  Liquid Glass APIs — never a hand-rolled imitation out of blurs, gradients and
//  opacity — AND that it be drawn "through the project's shared helpers rather
//  than by scattering `.glassEffect(...)` ad hoc per screen, so tinting,
//  hit-testing, and grouping stay consistent". This file is that helper: it is
//  the one place the app's card glass is defined.
//
//  No tint is applied, so the system material shows through as Apple intends. If
//  a tint is ever needed it MUST come from `AppColor`, never a raw literal.
//

import SwiftUI

/// Applies the app's standard glass card treatment.
private struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

extension View {
    /// Wraps the view in the app's standard Liquid Glass card.
    ///
    /// - Parameters:
    ///   - cornerRadius: corner radius of the glass shape. The default matches
    ///     the card radius already used elsewhere in the app.
    ///   - padding: inset applied inside the glass. Pass `0` when the call site
    ///     already provides its own padding — which is what makes this a
    ///     drop-in replacement for an existing bare `.glassEffect(...)` call.
    func glassCard(cornerRadius: CGFloat = 18, padding: CGFloat = 16) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, padding: padding))
    }
}
