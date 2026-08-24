//
//  CalorieAggregator.swift
//  Kalorias
//
//  Pure, testable calorie aggregation (constitution Principle I/II).
//
//  THE TOTAL IS REPORTED, NOT DERIVED. Until feature 009 the app summed the
//  items itself; now the server sends `totalCalories` already computed and that
//  figure is the source of truth (FR-012). `total(of:)` survives as the DEBUG
//  cross-check below — a disagreement means the contract is broken, and the
//  useful response to that is a log entry aimed at whoever can fix the server,
//  not a failed meal for the user or a number on screen that contradicts the
//  list beneath it.
//

import Foundation
import os

nonisolated enum CalorieAggregator {
    /// Σ item calories. Kept as the DEBUG cross-check against the reported
    /// total, no longer as the displayed value.
    static func total(of items: [FoodItem]) -> Int {
        items.reduce(0) { $0 + $1.calories }
    }

    /// Build an outcome: empty items ⇒ `.noFood`; otherwise a success carrying
    /// the **reported** total verbatim.
    static func make(from items: [FoodItem], reportedTotal: Int) -> AnalysisOutcome {
        guard !items.isEmpty else { return .noFood }

        #if DEBUG
        let sum = total(of: items)
        if sum != reportedTotal {
            // Logged, never corrected, never fatal. The server guarantees this
            // invariant, so a mismatch is a contract break to be fixed there.
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "Kalorias", category: "analysis")
                .warning("reported total \(reportedTotal) differs from the item sum \(sum)")
        }
        #endif

        return .success(CalorieAnalysis(items: items, totalCalories: reportedTotal))
    }
}
