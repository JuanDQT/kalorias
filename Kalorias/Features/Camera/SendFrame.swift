//
//  SendFrame.swift
//  Kalorias
//
//  Where the send frame sits on the camera screen: a centred square, inset from the
//  shorter edge.
//
//  Pure geometry — no AVFoundation, no view code — so the placement is unit-testable
//  across screen aspect ratios without a camera (constitution Principle I/II).
//
//  A square is deliberate. It sidesteps any aspect negotiation between the screen
//  (tall), the sensor (4:3) and the crop; it matches how the image is displayed
//  afterwards (the history and ingredient thumbnails are square-ish); and it is what
//  makes the crop's self-check available — a centred square in the preview must map
//  to an EQUAL-SIDED pixel rect, whatever the screen and image aspects. That
//  invariant is the substitute for a unit test on the layer conversion, which needs
//  live hardware.
//

import CoreGraphics

nonisolated struct SendFrame {
    /// Distance from the shorter container edge.
    let inset: CGFloat

    init(inset: CGFloat = 32) {
        self.inset = inset
    }

    /// The centred square frame within a container of `size`.
    ///
    /// Sized from the **shorter** edge so the square always fits, and clamped to a
    /// positive side length so a container smaller than twice the inset still yields
    /// a usable rect rather than a negative one (no force-unwrap, no crash).
    func rect(in size: CGSize) -> CGRect {
        let shortest = min(size.width, size.height)
        let side = max(shortest - 2 * inset, minimumSide(for: shortest))

        return CGRect(
            x: (size.width - side) / 2,
            y: (size.height - side) / 2,
            width: side,
            height: side
        )
    }

    /// Floor for a container too small for the inset: never zero or negative.
    private func minimumSide(for shortest: CGFloat) -> CGFloat {
        max(shortest / 2, 0)
    }

    /// The framed region expressed in the captured image's own normalized
    /// coordinates, ready to crop.
    ///
    /// Derived directly rather than via `AVCaptureVideoPreviewLayer`'s
    /// `metadataOutputRectConverted(fromLayerRect:)`. That API returns coordinates in
    /// the **metadata output** space — the sensor's landscape buffer — while the
    /// captured `UIImage` reports an orientation-corrected size. Applying one to the
    /// other transposes the axes: on device it produced a 3563×6334 crop (16:9) where
    /// a square was required. The mismatch is real and easy to reintroduce, so the
    /// geometry lives here, in the image's own space, where it is unit-testable.
    ///
    /// This works because two facts hold together: the preview is **centred
    /// aspect-fill**, and the frame is a **centred square**. A centred square of side
    /// `s` in the preview therefore corresponds to a centred square of side
    /// `s / fillScale` in the image — no rotation to reason about, and square by
    /// construction, which is what the runtime invariant checks.
    ///
    /// Assumes the still capture covers the same field of view as the preview, which
    /// holds for the `.photo` preset on one device.
    func imageRegion(previewSize: CGSize, imageSize: CGSize) -> FoodRegion? {
        guard
            previewSize.width > 0, previewSize.height > 0,
            imageSize.width > 0, imageSize.height > 0
        else { return nil }

        // `resizeAspectFill`: the image is scaled to cover the preview, so the
        // limiting axis is whichever needs the larger scale.
        let fillScale = max(
            previewSize.width / imageSize.width,
            previewSize.height / imageSize.height
        )
        guard fillScale > 0 else { return nil }

        let sideInPreview = rect(in: previewSize).width
        // Never exceed the image: a frame wider than the shorter image edge would
        // otherwise clamp asymmetrically and stop being square.
        let side = min(sideInPreview / fillScale, min(imageSize.width, imageSize.height))

        return FoodRegion(
            clampingX: (imageSize.width - side) / 2 / imageSize.width,
            y: (imageSize.height - side) / 2 / imageSize.height,
            width: side / imageSize.width,
            height: side / imageSize.height
        )
    }
}
