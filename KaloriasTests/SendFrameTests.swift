//
//  SendFrameTests.swift
//  KaloriasTests
//
//  Pure geometry — no camera, no layer, no clock.
//

import CoreGraphics
import XCTest
@testable import Kalorias

nonisolated final class SendFrameTests: XCTestCase {

    private let tolerance: CGFloat = 0.001

    func testFrameIsSquareOnATallContainer() {
        let rect = SendFrame(inset: 32).rect(in: CGSize(width: 440, height: 956))
        XCTAssertEqual(rect.width, rect.height, accuracy: tolerance)
    }

    func testFrameIsSquareOnAWideContainer() {
        let rect = SendFrame(inset: 32).rect(in: CGSize(width: 956, height: 440))
        XCTAssertEqual(rect.width, rect.height, accuracy: tolerance)
    }

    func testFrameIsSquareOnAnExactlySquareContainer() {
        let rect = SendFrame(inset: 24).rect(in: CGSize(width: 500, height: 500))
        XCTAssertEqual(rect.width, rect.height, accuracy: tolerance)
    }

    func testFrameIsCentred() {
        let size = CGSize(width: 440, height: 956)
        let rect = SendFrame(inset: 32).rect(in: size)

        XCTAssertEqual(rect.midX, size.width / 2, accuracy: tolerance)
        XCTAssertEqual(rect.midY, size.height / 2, accuracy: tolerance)
    }

    /// Sized from the SHORTER edge, so the square always fits.
    func testSideIsShorterEdgeMinusTwiceTheInset() {
        let inset: CGFloat = 32
        let rect = SendFrame(inset: inset).rect(in: CGSize(width: 440, height: 956))
        XCTAssertEqual(rect.width, 440 - 2 * inset, accuracy: tolerance)

        let wide = SendFrame(inset: inset).rect(in: CGSize(width: 956, height: 440))
        XCTAssertEqual(wide.width, 440 - 2 * inset, accuracy: tolerance)
    }

    /// A container too small for the inset must still give a usable square, not a
    /// negative one.
    func testTinyContainerStillYieldsAPositiveSquare() {
        let rect = SendFrame(inset: 100).rect(in: CGSize(width: 120, height: 200))

        XCTAssertGreaterThan(rect.width, 0)
        XCTAssertEqual(rect.width, rect.height, accuracy: tolerance)
        XCTAssertTrue(rect.width.isFinite)
    }

    func testZeroSizedContainerDoesNotProduceANegativeRect() {
        let rect = SendFrame(inset: 32).rect(in: .zero)
        XCTAssertGreaterThanOrEqual(rect.width, 0)
        XCTAssertEqual(rect.width, rect.height, accuracy: tolerance)
    }

    func testIsDeterministic() {
        let frame = SendFrame(inset: 32)
        let size = CGSize(width: 393, height: 852)
        XCTAssertEqual(frame.rect(in: size), frame.rect(in: size))
    }

    // MARK: Mapping the frame into the captured image
    //
    // These are the tests that would have caught the transposition shipped in the
    // first attempt. That version fed the frame through
    // `metadataOutputRectConverted(fromLayerRect:)`, whose result is in the sensor's
    // landscape buffer space, and applied it to the orientation-corrected image size.
    // On device it produced a 3563x6334 crop (16:9) where a square was required. The
    // mapping is now pure, so it can be asserted here instead of only at runtime.

    private let pixelTolerance: CGFloat = 1.5

    private func cropPixels(
        preview: CGSize, image: CGSize, inset: CGFloat = 32
    ) -> CGSize? {
        guard let region = SendFrame(inset: inset)
            .imageRegion(previewSize: preview, imageSize: image)
        else { return nil }
        return CGSize(
            width: region.width * image.width,
            height: region.height * image.height
        )
    }

    /// The core invariant: a centred square frame yields an EQUAL-SIDED pixel crop,
    /// whatever the preview and image aspect ratios.
    func testCropIsSquareInPixelsAcrossDevicesAndImageAspects() {
        let combinations: [(String, CGSize, CGSize)] = [
            ("15 Pro Max / 48MP portrait", CGSize(width: 430, height: 932), CGSize(width: 6048, height: 8064)),
            ("15 Pro Max / 12MP portrait", CGSize(width: 430, height: 932), CGSize(width: 3024, height: 4032)),
            ("17 Pro Max / 4:3 portrait", CGSize(width: 440, height: 956), CGSize(width: 3024, height: 4032)),
            ("landscape image", CGSize(width: 430, height: 932), CGSize(width: 4032, height: 3024)),
            ("16:9 image", CGSize(width: 430, height: 932), CGSize(width: 2160, height: 3840)),
            ("square image", CGSize(width: 430, height: 932), CGSize(width: 3000, height: 3000))
        ]

        for (name, preview, image) in combinations {
            guard let px = cropPixels(preview: preview, image: image) else {
                return XCTFail("\(name): expected a region")
            }
            XCTAssertEqual(
                px.width, px.height, accuracy: pixelTolerance,
                "\(name): crop must be square, got \(Int(px.width))x\(Int(px.height))"
            )
        }
    }

    /// The exact regression: the shipped bug produced a 16:9 crop on this device.
    func testCropIsNotSixteenByNineOnTheDeviceThatFailed() {
        guard let px = cropPixels(
            preview: CGSize(width: 430, height: 932),
            image: CGSize(width: 6048, height: 8064)
        ) else { return XCTFail("expected a region") }

        let ratio = max(px.width, px.height) / min(px.width, px.height)
        XCTAssertEqual(ratio, 1.0, accuracy: 0.01, "a 16:9 ratio here is the transposition bug")
    }

    /// The normalized rect is deliberately NOT square — only the pixel rect is. Getting
    /// this backwards is what makes the bug look plausible.
    func testNormalizedRectIsNotSquareForANonSquareImage() {
        guard let region = SendFrame(inset: 32).imageRegion(
            previewSize: CGSize(width: 430, height: 932),
            imageSize: CGSize(width: 3024, height: 4032)
        ) else { return XCTFail("expected a region") }

        XCTAssertGreaterThan(
            region.width, region.height,
            "for a portrait 4:3 image the normalized width must exceed the height"
        )
        XCTAssertEqual(region.width / region.height, 4.0 / 3.0, accuracy: 0.01)
    }

    func testRegionIsCentredInTheImage() {
        guard let region = SendFrame(inset: 32).imageRegion(
            previewSize: CGSize(width: 430, height: 932),
            imageSize: CGSize(width: 3024, height: 4032)
        ) else { return XCTFail("expected a region") }

        XCTAssertEqual(region.x + region.width / 2, 0.5, accuracy: 0.001)
        XCTAssertEqual(region.y + region.height / 2, 0.5, accuracy: 0.001)
    }

    func testRegionNeverExceedsTheImage() {
        // A tiny preview against a huge frame inset would otherwise overflow.
        guard let region = SendFrame(inset: 0).imageRegion(
            previewSize: CGSize(width: 1000, height: 100),
            imageSize: CGSize(width: 200, height: 4000)
        ) else { return XCTFail("expected a region") }

        XCTAssertLessThanOrEqual(region.x + region.width, 1.0 + 0.001)
        XCTAssertLessThanOrEqual(region.y + region.height, 1.0 + 0.001)
    }

    func testDegenerateSizesYieldNoRegion() {
        let frame = SendFrame(inset: 32)
        XCTAssertNil(frame.imageRegion(previewSize: .zero, imageSize: CGSize(width: 100, height: 100)))
        XCTAssertNil(frame.imageRegion(previewSize: CGSize(width: 100, height: 100), imageSize: .zero))
    }
}
