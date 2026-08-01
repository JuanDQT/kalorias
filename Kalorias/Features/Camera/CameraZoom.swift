//
//  CameraZoom.swift
//  Kalorias
//
//  Zoom bounds for the camera, as arithmetic.
//
//  No AVFoundation import: clamping is the part most likely to be got wrong at a
//  limit, and it must be testable without hardware (constitution Principle I/II).
//  The device supplies its own maximum; everything else is decided here.
//

import CoreGraphics

nonisolated enum CameraZoom {
    /// The configured rear camera is the wide-angle lens, whose factor starts at 1×.
    /// There is no ultra-wide to zoom out into, so this is the wide limit.
    static let minimumFactor: CGFloat = 1.0

    /// A QUALITY ceiling, not the device's capability. `maxAvailableVideoZoomFactor`
    /// can be very large and is mostly digital upscaling; past roughly 5× the picture
    /// stops being worth analyzing, which is what FR-018's "still produces an
    /// acceptable picture" asks for.
    static let maximumUsableFactor: CGFloat = 5.0

    /// The requested factor, constrained to what is both supported and usable.
    ///
    /// A device that cannot reach the ceiling clamps to its own maximum, and a device
    /// with no zoom at all (`deviceMaximum == 1`) stays at 1× for any request.
    static func clamp(_ requested: CGFloat, deviceMaximum: CGFloat) -> CGFloat {
        guard requested.isFinite, requested > 0 else { return minimumFactor }

        let ceiling = max(minimumFactor, min(deviceMaximum, maximumUsableFactor))
        return min(max(requested, minimumFactor), ceiling)
    }

    /// Whether a factor is the un-zoomed default — drives whether the indicator shows.
    static func isDefault(_ factor: CGFloat) -> Bool {
        abs(factor - minimumFactor) < 0.01
    }
}
