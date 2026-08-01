//
//  MealEntry.swift
//  Kalorias
//
//  SwiftData model for a saved meal. The photo is stored as a file on disk
//  (referenced by `imageFileName`), not as a DB blob, so the list stays fast.
//

import Foundation
import SwiftData

@Model
final class MealEntry {
    /// Stable id; also names the on-disk image file.
    var id: UUID
    var capturedAt: Date
    /// Dish name or ingredient list (derived at save via `MealTitle`).
    var title: String
    /// Σ of the foods' calories (stored for cheap list rendering).
    var totalCalories: Int
    /// The foods, persisted as JSON `Data` (a primitive SwiftData stores
    /// reliably); accessed through the `foods` computed property below.
    private var foodsData: Data
    var imageFileName: String

    /// The detected foods, encoded to/decoded from `foodsData`.
    var foods: [StoredFood] {
        get { (try? JSONDecoder().decode([StoredFood].self, from: foodsData)) ?? [] }
        set { foodsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init(
        id: UUID = UUID(),
        capturedAt: Date,
        title: String,
        totalCalories: Int,
        foods: [StoredFood],
        imageFileName: String
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.title = title
        self.totalCalories = totalCalories
        self.foodsData = (try? JSONEncoder().encode(foods)) ?? Data()
        self.imageFileName = imageFileName
    }
}

/// Lets a saved meal be partitioned into week groups (feature 004). Conformance
/// only — `capturedAt` and `totalCalories` already exist, so this adds no stored
/// property and does not touch the SwiftData schema.
extension MealEntry: WeekGroupable {}

/// A persisted per-food snapshot, decoupled from feature 002's `FoodItem`.
nonisolated struct StoredFood: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var calories: Int
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    /// Where in the meal's photo this food was found, for the details thumbnail.
    ///
    /// Adding this needed NO SwiftData migration: foods live as JSON inside
    /// `foodsData`, so the schema never mentioned them, and JSON written before
    /// this field existed decodes with `region == nil`.
    var region: FoodRegion?

    init(
        name: String,
        calories: Int,
        protein: Double? = nil,
        carbs: Double? = nil,
        fat: Double? = nil,
        region: FoodRegion? = nil
    ) {
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.region = region
    }

    init(from item: FoodItem) {
        self.init(
            name: item.name,
            calories: item.calories,
            protein: item.proteinGrams,
            carbs: item.carbsGrams,
            fat: item.fatGrams,
            region: item.region
        )
    }

    var asFoodItem: FoodItem {
        FoodItem(
            name: name,
            calories: calories,
            proteinGrams: protein,
            carbsGrams: carbs,
            fatGrams: fat,
            region: region
        )
    }

    var hasMacros: Bool { protein != nil || carbs != nil || fat != nil }
}
