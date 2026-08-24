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

    func testTotalOfNothingIsZero() {
        XCTAssertEqual(CalorieAggregator.total(of: []), 0)
    }

    func testMakeSuccessCarriesTheReportedTotal() {
        let items = [FoodItem(name: "A", calories: 100), FoodItem(name: "B", calories: 50)]
        guard case .success(let analysis) = CalorieAggregator.make(from: items, reportedTotal: 150) else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(analysis.totalCalories, 150)
        XCTAssertEqual(analysis.items.count, 2)
    }

    /// FR-012. The displayed figure is the server's, even when it disagrees with
    /// the breakdown beneath it: the app logs the mismatch in DEBUG and shows
    /// what it was told, rather than substituting arithmetic the server did not
    /// do.
    func testReportedTotalWinsOverTheItemSum() {
        let items = [FoodItem(name: "A", calories: 100), FoodItem(name: "B", calories: 50)]
        guard case .success(let analysis) = CalorieAggregator.make(from: items, reportedTotal: 999) else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(analysis.totalCalories, 999, "the reported total is taken, not computed")
        XCTAssertNotEqual(analysis.totalCalories, CalorieAggregator.total(of: items))
    }

    /// A mismatch is logged, never fatal: the meal still reaches the user.
    func testAMismatchStillProducesASuccess() {
        guard case .success = CalorieAggregator.make(
            from: [FoodItem(name: "A", calories: 10)], reportedTotal: 4000
        ) else {
            return XCTFail("a disagreeing total must not fail the analysis")
        }
    }

    func testMakeFromEmptyIsNoFoodWhateverTheReportedTotal() {
        XCTAssertEqual(CalorieAggregator.make(from: [], reportedTotal: 0), .noFood)
        XCTAssertEqual(CalorieAggregator.make(from: [], reportedTotal: 500), .noFood)
    }

    func testZeroCalorieMealIsStillASuccess() {
        guard case .success(let analysis) = CalorieAggregator.make(
            from: [FoodItem(name: "Water", calories: 0)], reportedTotal: 0
        ) else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(analysis.totalCalories, 0)
    }
}
