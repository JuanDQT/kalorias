//
//  MealEntry.swift
//  Kalorias
//
//  SwiftData model for a saved meal. The photo is stored as a file on disk
//  (referenced by `imageFileName`), not as a DB blob, so the list stays fast.
//
//  A MEAL BELONGS TO AN ACCOUNT (feature 010, FR-042). The rows never leave the
//  device, but two people can sign in to the same installation over time, and
//  the second must not see the first's food. Ownership is therefore a stored
//  property and every read filters on it in the SwiftData predicate — not in
//  Swift after fetching, which would load the other account's rows into memory
//  to then hide them.
//
//  IT IS OPTIONAL, AND `nil` MEANS "NOBODY". Optionality buys a lightweight
//  inferred migration of the existing store. It does **not** mean "the current
//  user": rows written before accounts existed are shown to no one, because
//  handing them to whoever signs in first is a guess, and the thing it would be
//  guessing about is somebody's food diary. The constitution records that no
//  pre-feature build was distributed, so those rows only exist in development.
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

    /// The opaque Kalorias user this meal belongs to. Required for every new
    /// insert; `nil` only on rows that predate accounts, which stay hidden.
    var ownerUserID: String?

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
        imageFileName: String,
        ownerUserID: String? = nil
    ) {
        self.ownerUserID = ownerUserID
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
