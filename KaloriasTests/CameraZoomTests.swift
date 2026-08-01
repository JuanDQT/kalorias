//
//  CameraZoomTests.swift
//  KaloriasTests
//
//  Pure arithmetic — no camera hardware involved.
//

import CoreGraphics
import XCTest
@testable import Kalorias

nonisolated final class CameraZoomTests: XCTestCase {

    private let tolerance: CGFloat = 0.001
    /// A typical modern device: capable of far more than is worth analyzing.
    private let capableDevice: CGFloat = 16.0

    // MARK: Limits

    func testRequestBelowMinimumClampsToOne() {
        XCTAssertEqual(
            CameraZoom.clamp(0.5, deviceMaximum: capableDevice), 1.0, accuracy: tolerance
        )
    }

    func testRequestAboveTheUsableCeilingClampsToIt() {
        XCTAssertEqual(
            CameraZoom.clamp(50, deviceMaximum: capableDevice),
            CameraZoom.maximumUsableFactor, accuracy: tolerance,
            "the ceiling is a quality limit, not the device's capability"
        )
    }

    func testMidRangeRequestPassesThroughUnchanged() {
        XCTAssertEqual(
            CameraZoom.clamp(2.5, deviceMaximum: capableDevice), 2.5, accuracy: tolerance
        )
    }

    // MARK: Device-constrained edges

    /// A device that cannot reach the ceiling must clamp to its own maximum.
    func testDeviceMaximumBelowTheCeilingWins() {
        XCTAssertEqual(
            CameraZoom.clamp(10, deviceMaximum: 3.0), 3.0, accuracy: tolerance
        )
    }

    /// A device with a single focal length and no digital zoom must stay at 1×.
    func testDeviceWithNoZoomStaysAtOne() {
        for request: CGFloat in [1.0, 2.0, 5.0, 100.0] {
            XCTAssertEqual(
                CameraZoom.clamp(request, deviceMaximum: 1.0), 1.0, accuracy: tolerance,
                "no zoom available, so \(request) must clamp to 1"
            )
        }
    }

    /// Defensive: a device reporting a nonsensical maximum must not push us below 1×.
    func testDeviceMaximumBelowOneStillYieldsOne() {
        XCTAssertEqual(
            CameraZoom.clamp(3.0, deviceMaximum: 0.5), 1.0, accuracy: tolerance
        )
    }

    // MARK: Degenerate requests

    func testNonFiniteAndNonPositiveRequestsYieldOne() {
        for request: CGFloat in [0, -3, .nan, .infinity] {
            XCTAssertEqual(
                CameraZoom.clamp(request, deviceMaximum: capableDevice), 1.0,
                accuracy: tolerance, "unusable request must fall back to 1×"
            )
        }
    }

    func testResultIsNeverOutsideTheAllowedRangeAcrossASweep() {
        for step in 0...80 {
            let request = CGFloat(step) * 0.25 - 5   // spans negative through 15
            let result = CameraZoom.clamp(request, deviceMaximum: capableDevice)

            XCTAssertGreaterThanOrEqual(result, CameraZoom.minimumFactor)
            XCTAssertLessThanOrEqual(result, CameraZoom.maximumUsableFactor)
        }
    }

    // MARK: Default detection

    func testIsDefaultOnlyAtOne() {
        XCTAssertTrue(CameraZoom.isDefault(1.0))
        XCTAssertFalse(CameraZoom.isDefault(1.5))
        XCTAssertFalse(CameraZoom.isDefault(5.0))
    }
}
