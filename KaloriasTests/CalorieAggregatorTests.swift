//
//  CalorieAggregatorTests.swift
//  KaloriasTests
//

import XCTest
@testable import Kalorias

nonisolated final class CalorieAggregatorTests: XCTestCase {

    func testTotalIsSumOfItems() {
        let items = [
            FoodItem(name: "Chicken", calories: 280),
            FoodItem(name: "Rice", calories: 240),
            FoodItem(name: "Broccoli", calories: 55)
        ]
        XCTAssertEqual(CalorieAggregator.total(of: items), 575)
    }

    func testTotalOfSingleItem() {
        XCTAssertEqual(CalorieAggregator.total(of: [FoodItem(name: "Apple", calories: 95)]), 95)
    }

    func testMakeSuccessCarriesComputedTotal() {
        let items = [FoodItem(name: "A", calories: 100), FoodItem(name: "B", calories: 50)]
        guard case .success(let analysis) = CalorieAggregator.make(from: items) else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(analysis.totalCalories, 150)
        XCTAssertEqual(analysis.items.count, 2)
    }

    func testMakeFromEmptyIsNoFood() {
        XCTAssertEqual(CalorieAggregator.make(from: []), .noFood)
    }
}
