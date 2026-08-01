//
//  PeriodChangeTests.swift
//  KaloriasTests
//
//  The zero-baseline guard is the point of this suite: a percentage change needs
//  something to divide by, and without the guard `(current - 0) / 0` reaches the
//  screen as "+∞" or "nan%".
//

import XCTest
@testable import Kalorias

nonisolated final class PeriodChangeTests: XCTestCase {

    // MARK: No basis for comparison

    func testZeroBaselineReturnsNil() {
        XCTAssertNil(ProgressStatistics.change(current: 1_500, baseline: 0))
    }

    func testBothZeroReturnsNil() {
        XCTAssertNil(ProgressStatistics.change(current: 0, baseline: 0))
    }

    func testNegativeBaselineReturnsNilWithoutCrashing() {
        XCTAssertNil(ProgressStatistics.change(current: 500, baseline: -100))
    }

    // MARK: Direction

    func testEqualValuesAreUnchangedRatherThanAZeroPercentIncrease() {
        let change = ProgressStatistics.change(current: 1_000, baseline: 1_000)
        XCTAssertEqual(change?.direction, .unchanged)
        XCTAssertEqual(change?.percent, 0)
    }

    func testIncreaseReportsUpWithItsMagnitude() {
        let change = ProgressStatistics.change(current: 1_120, baseline: 1_000)
        XCTAssertEqual(change?.direction, .up)
        XCTAssertEqual(change?.percent, 12)
    }

    func testDecreaseReportsDownWithAPositiveMagnitude() {
        let change = ProgressStatistics.change(current: 880, baseline: 1_000)
        XCTAssertEqual(change?.direction, .down)
        XCTAssertEqual(change?.percent, 12, "the sign lives in `direction`, not in `percent`")
    }

    /// A difference too small to show at integer precision must not render as
    /// "↑0%", which reads as a contradiction.
    func testChangeTooSmallToRoundIsReportedAsUnchanged() {
        let change = ProgressStatistics.change(current: 1_001, baseline: 1_000)
        XCTAssertEqual(change?.direction, .unchanged)
        XCTAssertEqual(change?.percent, 0)
    }

    // MARK: Magnitude

    func testLargeRatioIsReportedWithoutOverflow() {
        let change = ProgressStatistics.change(current: 2_000, baseline: 10)
        XCTAssertEqual(change?.direction, .up)
        XCTAssertEqual(change?.percent, 19_900)
    }

    func testDroppingToZeroIsAFullDecrease() {
        let change = ProgressStatistics.change(current: 0, baseline: 1_200)
        XCTAssertEqual(change?.direction, .down)
        XCTAssertEqual(change?.percent, 100)
    }

    func testPercentIsNeverNegativeAcrossASweep() {
        for current in stride(from: 0, through: 4_000, by: 137) {
            guard let change = ProgressStatistics.change(current: current, baseline: 1_000) else {
                return XCTFail("a positive baseline must always yield a change")
            }
            XCTAssertGreaterThanOrEqual(change.percent, 0, "failed at \(current)")
        }
    }

    func testRoundingUsesNearestRatherThanTruncation() {
        // 1126 vs 1000 is 12.6% → 13, not 12.
        XCTAssertEqual(ProgressStatistics.change(current: 1_126, baseline: 1_000)?.percent, 13)
    }
}
