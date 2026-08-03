//
//  CalorieColorStep+Color.swift
//  Kalorias
//
//  Maps the pure `CalorieColorStep` (feature 004) onto the design-system palette.
//
//  The mapping lives here, in the SwiftUI layer, rather than on the step itself:
//  `CalorieColorScale.swift` deliberately imports no SwiftUI so it stays a pure,
//  unit-testable value type. This is the one canonical place the four-step scale
//  becomes color, so History and Progress agree on what "red" means.
//

import SwiftUI

extension CalorieColorStep {
    /// The palette token for this step when the color lands on **text or an
    /// essential icon** — green at the low end, red at the high. These variants
    /// are contrast-checked (Principle III); see `PaletteContrastTests`.
    var textColor: Color {
        switch self {
        case .low: AppColor.success
        case .moderate: AppColor.caution
        case .high: AppColor.warning
        case .veryHigh: AppColor.danger
        }
    }

    /// The palette token for this step when the color is a **fill** — a chart
    /// mark or a badge, never behind a glyph. Full-vibrancy hues, which is why
    /// they are kept apart from `textColor`.
    var fillColor: Color {
        switch self {
        case .low: AppColor.successFill
        case .moderate: AppColor.cautionFill
        case .high: AppColor.warningFill
        case .veryHigh: AppColor.dangerFill
        }
    }
}
