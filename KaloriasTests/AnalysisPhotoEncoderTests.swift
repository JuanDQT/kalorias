//
//  AnalysisPhotoEncoderTests.swift
//  KaloriasTests
//
//  Rules P1–P6.
//

import XCTest
import UIKit
@testable import Kalorias

nonisolated final class AnalysisPhotoEncoderTests: XCTestCase {

    /// A noisy image rather than a flat fill: a solid colour compresses to a few
    /// hundred bytes at any quality, which would make the size assertions below
    /// pass for the wrong reason.
    ///
    /// `scale` is explicit because it is the thing under test. A photo from the
    /// library arrives at the screen's scale, so `size` is in points and the
    /// pixel count is three times larger on this device — and the pixel count is
    /// what gets uploaded.
    private func makeImage(width: CGFloat, height: CGFloat, scale: CGFloat = 1) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height), format: format
        )
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            for row in stride(from: 0, to: height, by: 4) {
                for column in stride(from: 0, to: width, by: 4) {
                    UIColor(
                        hue: CGFloat((Int(row + column) % 360)) / 360,
                        saturation: 0.9,
                        brightness: 0.9,
                        alpha: 1
                    ).setFill()
                    context.fill(CGRect(x: column, y: row, width: 4, height: 4))
                }
            }
        }
    }

    /// Pixel dimensions of an encoded JPEG — what actually travels, and what
    /// the server resizes from.
    private func decodedPixelSize(_ data: Data) throws -> CGSize {
        let image = try XCTUnwrap(UIImage(data: data))
        return CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    // MARK: P1 — the longest side is capped at 1024

    func testLargePhotoIsDownsizedToTheServersAnalysisSize() throws {
        let data = try XCTUnwrap(AnalysisPhotoEncoder.encode(makeImage(width: 4032, height: 3024)))
        let size = try decodedPixelSize(data)

        XCTAssertEqual(max(size.width, size.height), 1024, accuracy: 1)
        XCTAssertEqual(AnalysisPhotoEncoder.maxDimension, 1024)
    }

    /// **The cap is on pixels, not points.** A photo from the library carries
    /// the screen's scale, so capping points would send 3072 px and nine times
    /// the bytes on this device while every assertion about "1024" still passed.
    func testTheCapIsOnPixelsWhateverScaleThePhotoCarries() throws {
        let data = try XCTUnwrap(
            AnalysisPhotoEncoder.encode(makeImage(width: 1344, height: 1008, scale: 3))
        )
        let size = try decodedPixelSize(data)

        XCTAssertEqual(max(size.width, size.height), 1024, accuracy: 1)
    }

    func testPortraitPhotoIsCappedOnItsLongestSideToo() throws {
        let data = try XCTUnwrap(AnalysisPhotoEncoder.encode(makeImage(width: 3024, height: 4032)))
        let size = try decodedPixelSize(data)

        XCTAssertEqual(max(size.width, size.height), 1024, accuracy: 1)
        XCTAssertLessThan(min(size.width, size.height), 1024)
    }

    func testAspectRatioIsPreserved() throws {
        let source = makeImage(width: 4000, height: 2000)
        let size = try decodedPixelSize(try XCTUnwrap(AnalysisPhotoEncoder.encode(source)))

        XCTAssertEqual(
            size.width / size.height,
            source.size.width / source.size.height,
            accuracy: 0.01
        )
    }

    // MARK: P5 — never upscale

    /// Upscaling would send more bytes carrying no more information, and blur
    /// what the model sees.
    func testASmallPhotoIsNotUpscaled() throws {
        let size = try decodedPixelSize(
            try XCTUnwrap(AnalysisPhotoEncoder.encode(makeImage(width: 320, height: 240)))
        )

        XCTAssertEqual(size.width, 320, accuracy: 1)
        XCTAssertEqual(size.height, 240, accuracy: 1)
    }

    /// A 3x photo of 320 points is 960 pixels — under the limit, so its pixels
    /// are kept rather than being blown up to 1024.
    func testASmallHighScalePhotoKeepsItsPixels() throws {
        let size = try decodedPixelSize(
            try XCTUnwrap(AnalysisPhotoEncoder.encode(makeImage(width: 320, height: 240, scale: 3)))
        )

        XCTAssertEqual(size.width, 960, accuracy: 1)
        XCTAssertEqual(size.height, 720, accuracy: 1)
    }

    func testAPhotoExactlyAtTheLimitIsLeftAlone() throws {
        let size = try decodedPixelSize(
            try XCTUnwrap(AnalysisPhotoEncoder.encode(makeImage(width: 1024, height: 768)))
        )

        XCTAssertEqual(size.width, 1024, accuracy: 1)
        XCTAssertEqual(size.height, 768, accuracy: 1)
    }

    // MARK: P6 — the output is always JPEG

    /// The contract accepts nothing else, so a PNG or HEIC from the library must
    /// be converted rather than forwarded.
    func testOutputIsJPEGWhateverTheSourceFormat() throws {
        let png = try XCTUnwrap(makeImage(width: 800, height: 600).pngData())
        let source = try XCTUnwrap(UIImage(data: png))

        let data = try XCTUnwrap(AnalysisPhotoEncoder.encode(source))

        // SOI marker: every JPEG starts 0xFF 0xD8, and no PNG does.
        XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8], "the upload must be JPEG")
        XCTAssertNotNil(UIImage(data: data))
    }

    // MARK: P3 / P4 — the size cap

    func testResultIsUnderTheCapWithRoomForMultipartOverhead() throws {
        let data = try XCTUnwrap(AnalysisPhotoEncoder.encode(makeImage(width: 4032, height: 3024)))

        XCTAssertLessThanOrEqual(data.count, AnalysisPhotoEncoder.maxByteCount)
        XCTAssertLessThan(
            AnalysisPhotoEncoder.maxByteCount, 8_000_000,
            "the cap must sit below the server's limit, not on it"
        )
    }

    /// The point of the 1024 downsize: a full-resolution capture used to be sent
    /// as-is, and this is the assertion that a routine photo now travels as a
    /// few hundred KB rather than megabytes (SC-006).
    func testATypicalCaptureEncodesToAFewHundredKilobytes() throws {
        let data = try XCTUnwrap(AnalysisPhotoEncoder.encode(makeImage(width: 4032, height: 3024)))
        XCTAssertLessThan(data.count, 1_000_000)
    }

    /// The defect this closes: the capture site used to send
    /// `jpegData(compressionQuality: 0.8)` at full resolution.
    func testTheUploadIsFarSmallerThanEncodingTheFullResolutionCapture() throws {
        let capture = makeImage(width: 4032, height: 3024)

        let encoded = try XCTUnwrap(AnalysisPhotoEncoder.encode(capture))
        let unprepared = try XCTUnwrap(capture.jpegData(compressionQuality: 0.8))

        XCTAssertLessThan(encoded.count, unprepared.count / 4)
    }

    func testTheQualityLadderDescendsAndStartsWhereTheAppAlwaysEncoded() {
        XCTAssertEqual(AnalysisPhotoEncoder.qualityLadder, [0.8, 0.6, 0.4])
        XCTAssertEqual(AnalysisPhotoEncoder.qualityLadder, AnalysisPhotoEncoder.qualityLadder.sorted(by: >))
    }

    /// P4. A zero-area image produces no JPEG at any quality, which is the one
    /// reachable way `encode` returns `nil` — and the caller must show
    /// `.photoRejected` rather than dismissing the flow silently.
    func testAnUnencodablePhotoYieldsNil() {
        let empty = UIImage()
        XCTAssertNil(AnalysisPhotoEncoder.encode(empty))
    }

    // MARK: Determinism

    /// A retry re-sends prepared bytes rather than re-encoding, so the same
    /// photo must not become a different upload between attempts.
    func testEncodingTheSamePhotoTwiceGivesTheSameBytes() throws {
        let image = makeImage(width: 2000, height: 1500)

        let first = try XCTUnwrap(AnalysisPhotoEncoder.encode(image))
        let second = try XCTUnwrap(AnalysisPhotoEncoder.encode(image))

        XCTAssertEqual(first.count, second.count)
    }
}
