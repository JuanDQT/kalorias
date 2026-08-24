//
//  CalorieAnalysis.swift
//  Kalorias
//
//  Domain models for a photo calorie analysis. Pure, nonisolated, Sendable
//  value types — decoupled from the wire format (see AnalyzeMealResponse) and
//  usable/testable from any context. That decoupling is why moving the analysis
//  to the Kalorias backend left every type in this file untouched.
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
    /// The total the server reported, taken as received and never recomputed
    /// (see `CalorieAggregator.make(from:reportedTotal:)`).
    ///
    /// It is NOT derived from `items`, and the two can legitimately disagree —
    /// the server owns the arithmetic, and substituting the app's own would put
    /// a number on screen that contradicts the list beneath it. A mismatch is
    /// logged in DEBUG and shown anyway (FR-012).
    let totalCalories: Int
}

/// The outcome of one analysis attempt (failures are thrown as `AnalysisError`).
nonisolated enum AnalysisOutcome: Equatable, Sendable {
    case success(CalorieAnalysis)
    case noFood
}

extension AnalysisOutcome {
    /// A one-word label for the log. Names the shape of the answer only —
    /// never a food name, which FR-026 keeps out of the log entirely.
    var logDescription: String {
        switch self {
        case .success: "success"
        case .noFood: "noFood"
        }
    }

    /// How many foods came back. A count, not the contents.
    var foodCount: Int {
        switch self {
        case .success(let analysis): analysis.items.count
        case .noFood: 0
        }
    }
}
