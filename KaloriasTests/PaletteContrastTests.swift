//
//  PaletteContrastTests.swift
//  KaloriasTests
//
//  Constitution Principle III: "Contrast is measured, not eyeballed. Text and
//  essential icons MUST meet at least 4.5:1 contrast against their background in
//  both light and dark appearances."
//
//  This suite READS THE ASSET CATALOG. It resolves each token through
//  `UIColor(resource:)` for an explicit `UITraitCollection`, then computes the
//  WCAG ratio from the resolved components. It deliberately does NOT assert a
//  hardcoded table of hexes: such a test audits nothing — it restates itself,
//  and silently desynchronises from `Assets.xcassets` the moment someone edits
//  a colorset. The catalog is the thing under test.
//
//  SCOPE — text tokens only. The constitution mandates 4.5:1 for "text and
//  essential icons" and nothing more. The `-Fill` tokens and the three macro
//  accents carry no assertion here: they are never drawn behind a glyph, and
//  each is paired with a legible text label, which is the non-color cue the
//  palette block requires. Applying WCAG 1.4.11 (3:1) to fills was considered
//  and deliberately not adopted; see tasks.md T047.
//

import UIKit
import XCTest
@testable import Kalorias

nonisolated final class PaletteContrastTests: XCTestCase {

    /// Principle III's floor.
    private let minimumRatio: Double = 4.5

    // MARK: Surfaces text is drawn on

    private static let surfaces: [(name: String, resource: ColorResource)] = [
        ("surfacePrimary", .surfacePrimary),
        ("surfaceElevated", .surfaceElevated)
    ]

    /// Every token that lands on text or an essential icon.
    private static let textTokens: [(name: String, resource: ColorResource)] = [
        ("textPrimary", .textPrimary),
        ("textSecondary", .textSecondary),
        ("brandPrimary", .brandPrimary),
        ("success", .success),
        ("caution", .caution),
        ("warning", .warning),
        ("danger", .danger)
    ]

    private static let appearances: [(name: String, style: UIUserInterfaceStyle)] = [
        ("light", .light),
        ("dark", .dark)
    ]

    // MARK: The audit

    func testEveryTextTokenMeetsMinimumContrastOnEverySurfaceInBothAppearances() {
        for (appearanceName, style) in Self.appearances {
            let traits = UITraitCollection(userInterfaceStyle: style)

            for (surfaceName, surfaceResource) in Self.surfaces {
                let surface = UIColor(resource: surfaceResource).resolvedColor(with: traits)

                for (tokenName, tokenResource) in Self.textTokens {
                    let token = UIColor(resource: tokenResource).resolvedColor(with: traits)
                    let ratio = Self.contrastRatio(token, surface)

                    XCTAssertGreaterThanOrEqual(
                        ratio,
                        minimumRatio,
                        """
                        \(tokenName) on \(surfaceName) in \(appearanceName) is \
                        \(String(format: "%.2f", ratio)):1, below the \(minimumRatio):1 \
                        Principle III requires. Either darken/lighten the token in \
                        Assets.xcassets/Palette, or — if this token is only ever a fill — \
                        move it out of `textTokens` and name it with the `-Fill` suffix.
                        """
                    )
                }
            }
        }
    }

    /// Guards the guard: a known-failing pair must actually fail, otherwise the
    /// suite above could be passing because the maths is wrong rather than
    /// because the palette is right.
    func testContrastRatioDiscriminates() {
        // Identical colors are the 1:1 floor.
        XCTAssertEqual(Self.contrastRatio(.white, .white), 1.0, accuracy: 0.001)
        // Black on white is the 21:1 ceiling.
        XCTAssertEqual(Self.contrastRatio(.black, .white), 21.0, accuracy: 0.01)
        // The pre-audit light `brandPrimary` (#2FB457) measured 2.53:1 on
        // `surfacePrimary` (#F7F8F6) — the failure that motivated this suite.
        let oldBrand = UIColor(red: 0x2F / 255, green: 0xB4 / 255, blue: 0x57 / 255, alpha: 1)
        let lightSurface = UIColor(red: 0xF7 / 255, green: 0xF8 / 255, blue: 0xF6 / 255, alpha: 1)
        XCTAssertEqual(Self.contrastRatio(oldBrand, lightSurface), 2.53, accuracy: 0.01)
    }

    // MARK: WCAG maths

    /// WCAG 2.1 contrast ratio: `(L1 + 0.05) / (L2 + 0.05)`, lighter over darker.
    private static func contrastRatio(_ a: UIColor, _ b: UIColor) -> Double {
        let la = relativeLuminance(a)
        let lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// WCAG 2.1 relative luminance. The components must be linearized first —
    /// `getRed` hands back gamma-encoded sRGB.
    private static func relativeLuminance(_ color: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            XCTFail("Color is not RGB-convertible: \(color)")
            return 0
        }
        return 0.2126 * linearized(r) + 0.7152 * linearized(g) + 0.0722 * linearized(b)
    }

    private static func linearized(_ component: CGFloat) -> Double {
        let c = Double(component)
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
}
