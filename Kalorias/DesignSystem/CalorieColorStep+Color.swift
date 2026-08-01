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
    /// The palette token for this step — green at the low end, red at the high.
    var color: Color {
        switch self {
        case .low: AppColor.success
        case .moderate: AppColor.caution
        case .high: AppColor.warning
        case .veryHigh: AppColor.danger
        }
    }
}
