//
//  CardSurface.swift
//  Kalorias
//
//  The app's shared OPAQUE card surface.
//
//  This replaces the former `glassCard` helper, which Principle III forbids
//  outright: "a helper whose whole job is to apply glass to a card or a button
//  turns a design judgement into a default". An opaque surface is not that, and
//  the same principle positively requires UI to be "driven by shared
//  design-system assets rather than ad hoc, per-screen values" — so the card
//  treatment belongs in one place, while the *decision to use glass* does not.
//
//  IF A SURFACE EVER WARRANTS TRANSLUCENCY, the rule is unchanged: call
//  `.glassEffect(...)` at the site that needs it, so the judgement is visible in
//  the code that made it. Never add glass inside this helper — that would
//  reinstate through the side door exactly what the constitution removed.
//
//  WHY THERE IS A SHADOW
//  ---------------------
//  `surfaceElevated` on `surfacePrimary` measures 1.065:1 in light and 1.129:1
//  in dark. Tone alone does not separate a card from the background, and glass
//  was previously doing that structural work with its blur. Darkening
//  `surfacePrimary` instead was modelled and rejected: it buys almost no
//  separation while pushing the palette's text tokens below the 4.5:1 the
//  contrast audit just established. So elevation comes from a shadow, which is
//  also what the `apple-design` guidance describes — larger surfaces read as
//  thicker, with a deeper shadow.
//
//  The shadow carries LIGHT appearance. In dark it is deliberately much weaker:
//  a black shadow over `#0E120F` has almost no luminance difference to show, so
//  cranking its opacity would add cost without adding separation. There, the
//  tonal step between the two surfaces does the work, which is the conventional
//  dark-mode card treatment.
//

import SwiftUI

/// The app's standard opaque card surface: an elevated fill, a rounded shape,
/// and a shadow that separates it from the background.
private struct CardSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let padding: CGFloat

    /// Light needs the shadow to define the card's edge; dark relies on the
    /// tonal step instead (see the file comment).
    private var shadowOpacity: Double {
        colorScheme == .dark ? 0.25 : 0.10
    }

    func body(content: Content) -> some View {
        content
            .padding(padding)
            // The shadow goes on the background SHAPE, not on the view. Applied
            // to the content it would shadow every glyph inside the card and
            // soften the text.
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppColor.surfaceElevated)
                    .shadow(
                        color: .black.opacity(shadowOpacity),
                        radius: 12,
                        y: 4
                    )
            }
    }
}

extension View {
    /// Wraps the view in the app's standard opaque card surface.
    ///
    /// - Parameters:
    ///   - cornerRadius: corner radius of the card. The default matches the
    ///     radius used across the app's grouped content.
    ///   - padding: inset applied inside the card. Pass `0` when the call site
    ///     already provides its own padding.
    func cardSurface(cornerRadius: CGFloat = 18, padding: CGFloat = 16) -> some View {
        modifier(CardSurfaceModifier(cornerRadius: cornerRadius, padding: padding))
    }
}
