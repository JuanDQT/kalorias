//
//  FoodRegion.swift
//  Kalorias
//
//  Where in a meal's photo a detected food sits, so the details screen can crop a
//  thumbnail of that ingredient out of the photo the user actually took.
//
//  PROPORTIONAL, NOT PIXELS. `DiskImageStore` saves a downsized JPEG (max
//  dimension 1024), so the stored photo's pixel size differs from what the model
//  analyzed. A pixel region would mis-crop by the downscale ratio — silently, and
//  differently for every photo. Unit coordinates survive any rescaling.
//
//  Invalid regions cannot exist: the initializer is failable and is the only way
//  to make one, so anything that holds a `FoodRegion` holds a croppable one
//  (FR-015). No UIKit/CoreGraphics import, so the geometry rules — the part most
//  likely to be wrong — are unit-testable without an image.
//
//  THE 0-1000 CONVERSION IS GONE (feature 009). The Kalorias backend sends
//  proportions in `0...1` from the top-left already, which is exactly what this
//  type stores, so the scaling and the y-first axis order are the server's
//  problem now. The old initializer was deleted rather than kept "just in case":
//  left in place it was dead code that still compiled, and its tests would have
//  kept passing while covering a path no request can reach.
//

import Foundation

nonisolated struct FoodRegion: Codable, Hashable, Sendable {
    /// Left edge, as a proportion of image width. `0...1`, measured from the left.
    let x: Double
    /// Top edge, as a proportion of image height. `0...1`, measured from the top.
    let y: Double
    /// Width as a proportion of image width. Always positive.
    let width: Double
    /// Height as a proportion of image height. Always positive.
    let height: Double

    /// A unit-space rect, clamped into `0...1`.
    ///
    /// Edges slightly outside the image are clamped rather than rejected — a box
    /// reported a few units past the edge is still a useful thumbnail. Returns
    /// `nil` only when the clamped result has no area left to crop.
    init?(clampingX x: Double, y: Double, width: Double, height: Double) {
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite else { return nil }

        let left = min(max(x, 0), 1)
        let top = min(max(y, 0), 1)
        let right = min(max(x + width, 0), 1)
        let bottom = min(max(y + height, 0), 1)

        let clampedWidth = right - left
        let clampedHeight = bottom - top
        guard clampedWidth > 0, clampedHeight > 0 else { return nil }

        self.x = left
        self.y = top
        self.width = clampedWidth
        self.height = clampedHeight
    }

}
