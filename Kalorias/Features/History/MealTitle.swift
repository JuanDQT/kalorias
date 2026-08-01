//
//  MealTitle.swift
//  Kalorias
//
//  Pure, testable title derivation (constitution Principle I/II). A single
//  recognized food is treated as the dish name; multiple foods are shown as the
//  ingredient list (FR-007).
//

import Foundation

nonisolated enum MealTitle {
    static func make(from foods: [FoodItem]) -> String {
        if foods.count == 1 { return foods[0].name }
        return foods.map(\.name).joined(separator: ", ")
    }
}
