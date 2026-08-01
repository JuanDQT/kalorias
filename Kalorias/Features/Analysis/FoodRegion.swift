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
//  Invalid regions cannot exist: both initializers are failable and are the only
//  way to make one, so anything that holds a `FoodRegion` holds a croppable one
//  (FR-015). No UIKit/CoreGraphics import, so the geometry rules — the part most
//  likely to be wrong — are unit-testable without an image.
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

    /// A bounding box as the analysis reports it: integer edges on a 0–1000
    /// normalized scale, `ymin`/`ymax` from the **top** and `xmin`/`xmax` from the
    /// **left**.
    ///
    /// The parameter labels spell the axes out on purpose. The model's native
    /// array form is `[ymin, xmin, ymax, xmax]` — **y first** — which is the
    /// opposite of the `(x, y, …)` order most code assumes, and swapping the pair
    /// yields a perfectly valid-looking crop of the wrong part of the photo with
    /// no error raised anywhere.
    init?(geminiTop ymin: Int, left xmin: Int, bottom ymax: Int, right xmax: Int) {
        let scale = 1000.0
        self.init(
            clampingX: Double(xmin) / scale,
            y: Double(ymin) / scale,
            width: Double(xmax - xmin) / scale,
            height: Double(ymax - ymin) / scale
        )
    }
}
