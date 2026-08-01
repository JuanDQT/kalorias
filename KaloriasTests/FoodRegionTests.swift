//
//  FoodRegionTests.swift
//  KaloriasTests
//
//  Pure geometry — no image, no bundle, no clock.
//

import XCTest
@testable import Kalorias

nonisolated final class FoodRegionTests: XCTestCase {

    private let tolerance = 0.000_001

    // MARK: Unit-space construction

    func testValidUnitRectIsPreserved() {
        guard let region = FoodRegion(clampingX: 0.25, y: 0.5, width: 0.25, height: 0.4) else {
            return XCTFail("expected a valid region")
        }
        XCTAssertEqual(region.x, 0.25, accuracy: tolerance)
        XCTAssertEqual(region.y, 0.5, accuracy: tolerance)
        XCTAssertEqual(region.width, 0.25, accuracy: tolerance)
        XCTAssertEqual(region.height, 0.4, accuracy: tolerance)
    }

    func testWholeImageIsValid() {
        guard let region = FoodRegion(clampingX: 0, y: 0, width: 1, height: 1) else {
            return XCTFail("the whole image must be a valid region")
        }
        XCTAssertEqual(region.width, 1, accuracy: tolerance)
        XCTAssertEqual(region.height, 1, accuracy: tolerance)
    }

    func testEdgeSlightlyOutOfRangeIsClampedNotRejected() {
        // Bottom edge at 1.02 — a box a hair past the image, still useful.
        guard let region = FoodRegion(clampingX: 0.1, y: 0.9, width: 0.2, height: 0.12) else {
            return XCTFail("a slightly overhanging box must be clamped, not rejected")
        }
        XCTAssertEqual(region.y, 0.9, accuracy: tolerance)
        XCTAssertEqual(region.height, 0.1, accuracy: tolerance, "clamped to the image edge")
    }

    func testZeroWidthIsRejected() {
        XCTAssertNil(FoodRegion(clampingX: 0.3, y: 0.3, width: 0, height: 0.4))
    }

    func testZeroHeightIsRejected() {
        XCTAssertNil(FoodRegion(clampingX: 0.3, y: 0.3, width: 0.4, height: 0))
    }

    func testNegativeWidthIsRejected() {
        XCTAssertNil(FoodRegion(clampingX: 0.5, y: 0.3, width: -0.2, height: 0.4))
    }

    func testRegionWhollyOutOfBoundsIsRejected() {
        // Starts past the right edge; clamping leaves no area.
        XCTAssertNil(FoodRegion(clampingX: 2.0, y: 0.2, width: 0.3, height: 0.3))
    }

    func testNonFiniteValuesAreRejected() {
        XCTAssertNil(FoodRegion(clampingX: .nan, y: 0.2, width: 0.3, height: 0.3))
        XCTAssertNil(FoodRegion(clampingX: 0.2, y: 0.2, width: .infinity, height: 0.3))
    }

    // MARK: Gemini 0–1000 edges

    /// The axis-order test. Gemini's native array form is `[ymin, xmin, ymax, xmax]`
    /// — y first — so a swapped pair produces a valid-looking crop of the wrong
    /// part of the photo with no error anywhere. This is the only thing that
    /// catches it.
    func testGeminiEdgesMapTopToYAndLeftToX() {
        guard let region = FoodRegion(geminiTop: 100, left: 500, bottom: 300, right: 900) else {
            return XCTFail("expected a valid region")
        }
        XCTAssertEqual(region.y, 0.1, accuracy: tolerance, "ymin 100 must become y, not x")
        XCTAssertEqual(region.x, 0.5, accuracy: tolerance, "xmin 500 must become x, not y")
        XCTAssertEqual(region.height, 0.2, accuracy: tolerance, "ymax-ymin must become height")
        XCTAssertEqual(region.width, 0.4, accuracy: tolerance, "xmax-xmin must become width")
    }

    func testGeminiEdgesAreDividedByOneThousand() {
        guard let region = FoodRegion(geminiTop: 0, left: 0, bottom: 500, right: 250) else {
            return XCTFail("expected a valid region")
        }
        XCTAssertEqual(region.height, 0.5, accuracy: tolerance)
        XCTAssertEqual(region.width, 0.25, accuracy: tolerance)
    }

    func testGeminiFullFrameIsTheWholeImage() {
        guard let region = FoodRegion(geminiTop: 0, left: 0, bottom: 1000, right: 1000) else {
            return XCTFail("a full-frame box must be valid")
        }
        XCTAssertEqual(region.x, 0, accuracy: tolerance)
        XCTAssertEqual(region.y, 0, accuracy: tolerance)
        XCTAssertEqual(region.width, 1, accuracy: tolerance)
        XCTAssertEqual(region.height, 1, accuracy: tolerance)
    }

    func testGeminiInvertedEdgesAreRejected() {
        XCTAssertNil(FoodRegion(geminiTop: 800, left: 100, bottom: 200, right: 400))
        XCTAssertNil(FoodRegion(geminiTop: 100, left: 900, bottom: 400, right: 300))
    }

    func testGeminiDegenerateBoxIsRejected() {
        XCTAssertNil(FoodRegion(geminiTop: 300, left: 300, bottom: 300, right: 700))
    }

    func testGeminiEdgesPastOneThousandAreClamped() {
        guard let region = FoodRegion(geminiTop: 900, left: 100, bottom: 1005, right: 400) else {
            return XCTFail("an overhanging box must be clamped, not rejected")
        }
        XCTAssertEqual(region.y, 0.9, accuracy: tolerance)
        XCTAssertEqual(region.height, 0.1, accuracy: tolerance)
    }

    // MARK: Codable

    func testCodableRoundTripIsLossless() throws {
        guard let region = FoodRegion(clampingX: 0.125, y: 0.25, width: 0.5, height: 0.125) else {
            return XCTFail("expected a valid region")
        }
        let data = try JSONEncoder().encode(region)
        let decoded = try JSONDecoder().decode(FoodRegion.self, from: data)
        XCTAssertEqual(region, decoded)
    }
}
