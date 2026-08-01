//
//  MealTitleTests.swift
//  KaloriasTests
//

import XCTest
@testable import Kalorias

nonisolated final class MealTitleTests: XCTestCase {

    func testSingleFoodUsesItsNameAsDish() {
        let title = MealTitle.make(from: [FoodItem(name: "Caesar salad", calories: 350)])
        XCTAssertEqual(title, "Caesar salad")
    }

    func testMultipleFoodsListIngredientsInOrder() {
        let foods = [
            FoodItem(name: "Chicken", calories: 280),
            FoodItem(name: "Rice", calories: 240),
            FoodItem(name: "Broccoli", calories: 55)
        ]
        XCTAssertEqual(MealTitle.make(from: foods), "Chicken, Rice, Broccoli")
    }
}
