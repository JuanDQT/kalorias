//
//  ImageCropperTests.swift
//  KaloriasTests
//
//  Source images are built synthetically, as `ImageStoreTests` does — no fixtures
//  on disk.
//

import UIKit
import XCTest
@testable import Kalorias

nonisolated final class ImageCropperTests: XCTestCase {

    /// A `size`-point image split into coloured quadrants, so a crop can be checked
    /// against the colour it is supposed to contain.
    private func quadrantImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let half = CGSize(width: size.width / 2, height: size.height / 2)
            let quadrants: [(UIColor, CGRect)] = [
                (.red, CGRect(origin: .zero, size: half)),
                (.green, CGRect(x: half.width, y: 0, width: half.width, height: half.height)),
                (.blue, CGRect(x: 0, y: half.height, width: half.width, height: half.height)),
                (.yellow, CGRect(origin: CGPoint(x: half.width, y: half.height), size: half))
            ]
            for (colour, rect) in quadrants {
                colour.setFill()
                context.fill(rect)
            }
        }
    }

    private func region(x: Double, y: Double, w: Double, h: Double) -> FoodRegion {
        guard let region = FoodRegion(clampingX: x, y: y, width: w, height: h) else {
            fatalError("test region must be valid")
        }
        return region
    }

    /// The dominant colour at the centre of an image, for asserting *which* part of
    /// the source a crop came from.
    private func centreColour(of image: UIImage) -> (r: Int, g: Int, b: Int)? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(
            cgImage,
            in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
        )
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }

    private func isReddish(_ colour: (r: Int, g: Int, b: Int)?) -> Bool {
        guard let colour else { return false }
        return colour.r > 150 && colour.g < 100 && colour.b < 100
    }

    // MARK: Geometry

    func testCropPreservesTheRegionAspectRatio() {
        let source = quadrantImage(size: CGSize(width: 400, height: 200))
        // Left half of a 2:1 image is 200x200 — square.
        guard let cropped = ImageCropper.crop(
            source, to: region(x: 0, y: 0, w: 0.5, h: 1), maxDimension: 400
        ) else { return XCTFail("expected a crop") }

        XCTAssertEqual(cropped.size.width / cropped.size.height, 1, accuracy: 0.02)
    }

    func testCropIsCappedAtMaxDimension() {
        let source = quadrantImage(size: CGSize(width: 1000, height: 800))
        guard let cropped = ImageCropper.crop(
            source, to: region(x: 0, y: 0, w: 1, h: 1), maxDimension: 120
        ) else { return XCTFail("expected a crop") }

        XCTAssertLessThanOrEqual(max(cropped.size.width, cropped.size.height), 120.5)
    }

    func testSmallCropIsNotUpscaled() {
        let source = quadrantImage(size: CGSize(width: 100, height: 100))
        guard let cropped = ImageCropper.crop(
            source, to: region(x: 0, y: 0, w: 0.2, h: 0.2), maxDimension: 500
        ) else { return XCTFail("expected a crop") }

        XCTAssertEqual(max(cropped.size.width, cropped.size.height), 20, accuracy: 1)
    }

    func testWholeImageRegionReturnsTheWholeImage() {
        let source = quadrantImage(size: CGSize(width: 240, height: 240))
        guard let cropped = ImageCropper.crop(
            source, to: region(x: 0, y: 0, w: 1, h: 1), maxDimension: 240
        ) else { return XCTFail("expected a crop") }

        XCTAssertEqual(cropped.size.width, 240, accuracy: 1)
        XCTAssertEqual(cropped.size.height, 240, accuracy: 1)
    }

    func testCropTakesTheRegionItWasAskedFor() {
        // Top-left quadrant is red.
        let source = quadrantImage(size: CGSize(width: 200, height: 200))
        guard let cropped = ImageCropper.crop(
            source, to: region(x: 0, y: 0, w: 0.5, h: 0.5), maxDimension: 100
        ) else { return XCTFail("expected a crop") }

        XCTAssertTrue(
            isReddish(centreColour(of: cropped)),
            "the top-left region must yield the red quadrant"
        )
    }

    /// The test that catches `cgImage.cropping(to:)`. A non-`.up` image must crop
    /// the same VISIBLE region as an `.up` one; `CGImage` cropping ignores
    /// orientation and would return a different quadrant.
    func testCropRespectsImageOrientation() {
        let upright = quadrantImage(size: CGSize(width: 200, height: 200))
        guard let cgImage = upright.cgImage else { return XCTFail("expected a CGImage") }

        // Same pixels, tagged as rotated. Visually the top-left is no longer red.
        let rotated = UIImage(cgImage: cgImage, scale: 1, orientation: .left)

        guard let croppedUpright = ImageCropper.crop(
            upright, to: region(x: 0, y: 0, w: 0.5, h: 0.5), maxDimension: 100
        ), let croppedRotated = ImageCropper.crop(
            rotated, to: region(x: 0, y: 0, w: 0.5, h: 0.5), maxDimension: 100
        ) else { return XCTFail("expected both crops") }

        XCTAssertTrue(isReddish(centreColour(of: croppedUpright)))
        XCTAssertFalse(
            isReddish(centreColour(of: croppedRotated)),
            "a rotated source must not yield the same quadrant — orientation was ignored"
        )
    }

    // MARK: Degenerate input

    func testZeroSizedSourceReturnsNil() {
        let empty = UIImage()
        XCTAssertNil(
            ImageCropper.crop(
                empty, to: region(x: 0, y: 0, w: 1, h: 1), maxDimension: 100
            )
        )
    }

    func testZeroMaxDimensionReturnsNil() {
        let source = quadrantImage(size: CGSize(width: 100, height: 100))
        XCTAssertNil(
            ImageCropper.crop(
                source, to: region(x: 0, y: 0, w: 1, h: 1), maxDimension: 0
            )
        )
    }

    // MARK: Batch

    func testCropsOnlyIncludesFoodsThatHaveARegion() {
        let source = quadrantImage(size: CGSize(width: 200, height: 200))
        let withRegion = StoredFood(
            name: "Pollo", calories: 320, region: region(x: 0, y: 0, w: 0.5, h: 0.5)
        )
        let without = StoredFood(name: "Arroz", calories: 210)

        let crops = ImageCropper.crops(
            for: [withRegion, without], from: source, maxDimension: 100
        )

        XCTAssertEqual(crops.count, 1)
        XCTAssertNotNil(crops[withRegion.id])
        XCTAssertNil(crops[without.id])
    }

    func testCropsIsEmptyWhenNoFoodHasARegion() {
        let source = quadrantImage(size: CGSize(width: 200, height: 200))
        let foods = [
            StoredFood(name: "Pollo", calories: 320),
            StoredFood(name: "Arroz", calories: 210)
        ]

        XCTAssertTrue(
            ImageCropper.crops(for: foods, from: source, maxDimension: 100).isEmpty
        )
    }

    func testCropsIsKeyedByFoodID() {
        let source = quadrantImage(size: CGSize(width: 200, height: 200))
        let foods = [
            StoredFood(name: "A", calories: 100, region: region(x: 0, y: 0, w: 0.5, h: 0.5)),
            StoredFood(name: "B", calories: 200, region: region(x: 0.5, y: 0.5, w: 0.5, h: 0.5))
        ]

        let crops = ImageCropper.crops(for: foods, from: source, maxDimension: 100)

        XCTAssertEqual(Set(crops.keys), Set(foods.map(\.id)))
    }
}
