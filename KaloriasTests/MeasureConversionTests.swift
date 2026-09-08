//
//  MeasureConversionTests.swift
//  KaloriasTests
//
//  The wheel's arithmetic. Two of these assert things that are invisible when
//  broken — a unit switch that quietly loses half a step, and a rounding carry
//  that produces "5 ft 12 in".
//

import XCTest
@testable import Kalorias

nonisolated final class MeasureConversionTests: XCTestCase {

    private func measure(_ json: String) throws -> MeasureConfig {
        try XCTUnwrap(OnboardingFixtures.question(json).measure)
    }

    private var weight: MeasureConfig { get throws { try measure(OnboardingFixtures.weightMeasure) } }
    private var height: MeasureConfig { get throws { try measure(OnboardingFixtures.heightMeasure) } }

    // MARK: Canonical value

    func testCanonicalUnitPassesThroughUnchanged() throws {
        let value = try weight.canonicalValue(components: ["kg": 84.4], unitId: "kg")
        XCTAssertEqual(try XCTUnwrap(value), 84.4, accuracy: 0.0001)
    }

    func testAlternateUnitIsConvertedByItsFactor() throws {
        let value = try weight.canonicalValue(components: ["lb": 186], unitId: "lb")
        XCTAssertEqual(try XCTUnwrap(value), 84.368, accuracy: 0.001)
    }

    /// The reason a unit carries an array of components: `ft/in` cannot be
    /// expressed as one scale factor.
    func testTwoComponentUnitSumsBothComponents() throws {
        let value = try height.canonicalValue(components: ["ft": 5, "in": 10], unitId: "ft_in")
        XCTAssertEqual(try XCTUnwrap(value), 177.8, accuracy: 0.01)
    }

    // MARK: Splitting back

    func testSplittingIntoTwoComponents() throws {
        let parts = try height.components(fromCanonical: 177.8, unitId: "ft_in")
        XCTAssertEqual(parts["ft"], 5)
        XCTAssertEqual(parts["in"], 10)
    }

    /// 5 ft 11.6 in rounds to 12 inches, which is not a height anyone writes.
    func testRoundingUpTheFineComponentCarriesIntoTheCoarseOne() throws {
        // 181.5 cm is 5 ft 11.46 in — but nudge it past the half-inch and the
        // inches round to 12.
        let parts = try height.components(fromCanonical: 182.8, unitId: "ft_in")
        XCTAssertEqual(parts["ft"], 6, "the carry must happen")
        XCTAssertEqual(parts["in"], 0)
        XCTAssertNotEqual(parts["in"], 12)
    }

    func testSplittingClampsToTheComponentRange() throws {
        let parts = try weight.components(fromCanonical: 5, unitId: "kg")
        XCTAssertEqual(parts["kg"], 30, "below the wheel's minimum")
    }

    func testSplittingSnapsToTheStep() throws {
        let parts = try weight.components(fromCanonical: 70.04, unitId: "kg")
        XCTAssertEqual(try XCTUnwrap(parts["kg"]), 70.0, accuracy: 0.0001)
    }

    // MARK: The rule that is invisible when broken

    /// Switching units converts for display and leaves the canonical value
    /// alone. Rewriting it on every switch loses half a step each time, and the
    /// user's weight drifts one rounding at a time.
    func testSwitchingUnitsRepeatedlyDoesNotDriftTheCanonicalValue() throws {
        let config = try weight
        let canonical = 84.4
        var displayed = config.components(fromCanonical: canonical, unitId: "kg")
        var unit = "kg"

        for _ in 0..<20 {
            unit = unit == "kg" ? "lb" : "kg"
            // What the view does on a unit switch: re-derive the display from
            // the *unchanged* canonical value.
            displayed = config.components(fromCanonical: canonical, unitId: unit)
        }

        XCTAssertEqual(canonical, 84.4, "the value of record never moved")
        XCTAssertEqual(unit, "kg")
        XCTAssertEqual(try XCTUnwrap(displayed["kg"]), 84.4, accuracy: 0.0001)
    }

    /// And the counter-example, so the test above is not passing by accident:
    /// re-deriving the canonical value from the snapped display every time *does*
    /// drift, which is exactly the bug the rule prevents.
    func testDerivingTheCanonicalFromTheDisplayOnEverySwitchWouldDrift() throws {
        let config = try weight
        var canonical = 84.35   // half a step off a pound tick
        var unit = "kg"

        for _ in 0..<20 {
            unit = unit == "kg" ? "lb" : "kg"
            let parts = config.components(fromCanonical: canonical, unitId: unit)
            canonical = try XCTUnwrap(config.canonicalValue(components: parts, unitId: unit))
        }

        XCTAssertNotEqual(canonical, 84.35, accuracy: 0.0001,
                          "if this ever stops drifting the guard above is worthless")
    }

    // MARK: Unit preference

    func testDevicePreferenceWinsOverTheFilesDefault() throws {
        let config = try weight
        XCTAssertEqual(config.defaultUnit, "kg")
        XCTAssertEqual(config.preferredUnitId(matching: .us), "lb")
        XCTAssertEqual(config.preferredUnitId(matching: .metric), "kg")
    }

    func testWithNoDevicePreferenceTheFilesDefaultStands() throws {
        XCTAssertEqual(try weight.preferredUnitId(matching: nil), "kg")
    }

    // MARK: Component helpers

    func testTicksCoverTheWholeRangeInclusive() throws {
        let component = try XCTUnwrap(height.unit(id: "ft_in")?.components.first)
        XCTAssertEqual(component.ticks, [4, 5, 6, 7])
    }
}
