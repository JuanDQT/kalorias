//
//  CalorieColorScaleTests.swift
//  KaloriasTests
//

import XCTest
@testable import Kalorias

nonisolated final class CalorieColorScaleTests: XCTestCase {

    // MARK: Degenerate groups (FR-014)

    func testAllTotalsEqualYieldsLow() {
        XCTAssertEqual(CalorieColorScale.step(for: 700, lowest: 700, highest: 700), .low)
    }

    func testSingleItemGroupYieldsLow() {
        // A one-meal group has lowest == highest == the value itself.
        XCTAssertEqual(CalorieColorScale.step(for: 1_850, lowest: 1_850, highest: 1_850), .low)
    }

    func testInvertedBoundsYieldLowWithoutCrashing() {
        XCTAssertEqual(CalorieColorScale.step(for: 500, lowest: 900, highest: 100), .low)
    }

    // MARK: Endpoints (FR-011)

    func testLowestValueInASpreadGroupIsLow() {
        XCTAssertEqual(CalorieColorScale.step(for: 100, lowest: 100, highest: 2_000), .low)
    }

    /// The clamp test. `value == highest` produces a raw band index of 4 — one
    /// past the last band — so without clamping this would not be `.veryHigh`.
    func testHighestValueInASpreadGroupIsVeryHigh() {
        XCTAssertEqual(CalorieColorScale.step(for: 2_000, lowest: 100, highest: 2_000), .veryHigh)
    }

    // MARK: Banding & monotonicity

    func testQuarterBoundariesLandOnSuccessiveSteps() {
        let bounds = (lowest: 0, highest: 400)
        XCTAssertEqual(CalorieColorScale.step(for: 0, lowest: bounds.lowest, highest: bounds.highest), .low)
        XCTAssertEqual(CalorieColorScale.step(for: 99, lowest: bounds.lowest, highest: bounds.highest), .low)
        XCTAssertEqual(CalorieColorScale.step(for: 100, lowest: bounds.lowest, highest: bounds.highest), .moderate)
        XCTAssertEqual(CalorieColorScale.step(for: 200, lowest: bounds.lowest, highest: bounds.highest), .high)
        XCTAssertEqual(CalorieColorScale.step(for: 300, lowest: bounds.lowest, highest: bounds.highest), .veryHigh)
        XCTAssertEqual(CalorieColorScale.step(for: 400, lowest: bounds.lowest, highest: bounds.highest), .veryHigh)
    }

    /// FR-013: a higher total must never be assigned a cooler step than a lower
    /// one within the same group.
    func testStepsNeverDecreaseAsValueIncreases() {
        let lowest = 180
        let highest = 2_450
        var previous = CalorieColorStep.low

        for value in stride(from: lowest, through: highest, by: 10) {
            let step = CalorieColorScale.step(for: value, lowest: lowest, highest: highest)
            XCTAssertTrue(
                step >= previous,
                "step regressed from \(previous) to \(step) at \(value) kcal"
            )
            previous = step
        }

        XCTAssertEqual(previous, .veryHigh, "the sweep should finish on the top step")
    }

    func testAllFourStepsAreReachableAcrossARange() {
        let steps = stride(from: 0, through: 1_000, by: 25).map {
            CalorieColorScale.step(for: $0, lowest: 0, highest: 1_000)
        }
        XCTAssertEqual(Set(steps).count, CalorieColorStep.allCases.count)
    }

    // MARK: Enum ordering

    func testStepsAreOrderedLowestToHighest() {
        XCTAssertTrue(CalorieColorStep.low < CalorieColorStep.moderate)
        XCTAssertTrue(CalorieColorStep.moderate < CalorieColorStep.high)
        XCTAssertTrue(CalorieColorStep.high < CalorieColorStep.veryHigh)
    }
}
