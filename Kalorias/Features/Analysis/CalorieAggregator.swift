//
//  CalorieAggregator.swift
//  Kalorias
//
//  Pure, testable calorie aggregation (constitution Principle I/II). The
//  displayed total is ALWAYS the sum of the items here, guaranteeing it matches
//  the breakdown (FR-006 / SC-002).
//

import Foundation

nonisolated enum CalorieAggregator {
    /// Total kcal = Σ item calories.
    static func total(of items: [FoodItem]) -> Int {
        items.reduce(0) { $0 + $1.calories }
    }

    /// Build an outcome: empty items ⇒ `.noFood`; otherwise a success whose
    /// total is the computed sum.
    static func make(from items: [FoodItem]) -> AnalysisOutcome {
        guard !items.isEmpty else { return .noFood }
        return .success(CalorieAnalysis(items: items, totalCalories: total(of: items)))
    }
}
