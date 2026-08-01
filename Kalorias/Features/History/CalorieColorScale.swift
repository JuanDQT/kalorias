//
//  CalorieColorScale.swift
//  Kalorias
//
//  Pure, testable mapping from a meal's calorie total to one of four ordered
//  steps, relative to the lowest and highest totals in ITS OWN week group
//  (FR-011 … FR-014). Each week is therefore judged against itself: the same
//  kcal figure may land on a different step in a different week.
//
//  This file imports no SwiftUI — it yields a domain enum, and the view layer
//  maps that to `AppColor` tokens (constitution Principle I/III).
//

import Foundation

/// The four steps of the calorie scale, ordered lowest → highest so callers and
/// tests can reason about monotonicity without knowing any colors.
nonisolated enum CalorieColorStep: Int, Comparable, CaseIterable {
    case low = 0
    case moderate = 1
    case high = 2
    case veryHigh = 3

    static func < (lhs: CalorieColorStep, rhs: CalorieColorStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

nonisolated enum CalorieColorScale {

    private static let bandCount = 4

    /// Which step `value` falls into, given its group's bounds.
    ///
    /// The span `lowest ... highest` is divided into four equal bands. The
    /// mapping is monotonic by construction: `position` is non-decreasing in
    /// `value`, and neither truncation nor clamping can reorder two values.
    static func step(for value: Int, lowest: Int, highest: Int) -> CalorieColorStep {
        // Covers the single-meal group, the all-totals-equal group, and any
        // inverted bounds — and is what makes the division below safe (FR-014).
        guard highest > lowest else { return .low }

        let position = Double(value - lowest) / Double(highest - lowest)
        let index = Int(position * Double(bandCount))

        // `value == highest` gives a position of exactly 1.0 and so an index of
        // 4, one past the last band; clamping is the only thing that lands the
        // top of the range on `.veryHigh` (FR-011).
        let clamped = max(0, min(bandCount - 1, index))
        return CalorieColorStep(rawValue: clamped) ?? .low
    }
}
