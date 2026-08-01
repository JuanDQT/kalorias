//
//  CalorieAnalysis.swift
//  Kalorias
//
//  Domain models for a photo calorie analysis. Pure, nonisolated, Sendable
//  value types — decoupled from the Gemini wire format (see GeminiCalorieService)
//  and usable/testable from any context.
//

import Foundation

/// One recognized food item.
nonisolated struct FoodItem: Equatable, Sendable, Identifiable {
    let id = UUID()
    let name: String
    /// Estimated calories for this item (≥ 0).
    let calories: Int
    let proteinGrams: Double?
    let carbsGrams: Double?
    let fatGrams: Double?
    /// Where in the analyzed photo this food was found, when the analysis reported
    /// it. Optional everywhere: a response without boxes still yields a complete,
    /// saveable meal (FR-021).
    let region: FoodRegion?

    init(
        name: String,
        calories: Int,
        proteinGrams: Double? = nil,
        carbsGrams: Double? = nil,
        fatGrams: Double? = nil,
        region: FoodRegion? = nil
    ) {
        self.name = name
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.region = region
    }

    var hasMacros: Bool {
        proteinGrams != nil || carbsGrams != nil || fatGrams != nil
    }

    /// Value equality ignores the synthesized `id` (used for `Identifiable`) and
    /// `region`: two foods with the same nutrition are the same food regardless of
    /// where in the photo they were spotted.
    static func == (lhs: FoodItem, rhs: FoodItem) -> Bool {
        lhs.name == rhs.name
            && lhs.calories == rhs.calories
            && lhs.proteinGrams == rhs.proteinGrams
            && lhs.carbsGrams == rhs.carbsGrams
            && lhs.fatGrams == rhs.fatGrams
    }
}

/// A successful, food-bearing analysis.
nonisolated struct CalorieAnalysis: Equatable, Sendable {
    let items: [FoodItem]
    /// Derived total = Σ items.calories (see CalorieAggregator); never taken
    /// from the wire payload.
    let totalCalories: Int
}

/// The outcome of one analysis attempt (failures are thrown as `AnalysisError`).
nonisolated enum AnalysisOutcome: Equatable, Sendable {
    case success(CalorieAnalysis)
    case noFood
}
