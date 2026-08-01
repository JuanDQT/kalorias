//
//  ImageCropper.swift
//  Kalorias
//
//  The app's single image-geometry utility: cropping a `UIImage` to a unit rect,
//  and downsizing one to a maximum dimension.
//
//  Two callers rely on the crop — the ingredient thumbnails on the details screen,
//  and the camera's send frame, which crops a capture to what the user framed. It
//  is deliberately ONE implementation: orientation handling here is subtle enough
//  that a second copy is how the orientation bug comes back.
//
//  ORIENTATION MATTERS HERE. `CGImage` has no notion of `UIImage.imageOrientation`,
//  so `cgImage?.cropping(to:)` would silently crop a rotated interpretation of the
//  coordinates — a wrong-region bug that looks exactly like a bad model box. And
//  the case is reachable: `DiskImageStore.downsized` returns the ORIGINAL image
//  untouched when it is already small enough, and `UIImage.jpegData` preserves
//  orientation metadata, so a loaded photo is not guaranteed to be `.up`.
//
//  Drawing through `UIGraphicsImageRenderer` applies the orientation as part of
//  `draw(in:)`, so a unit rect maps to what the user actually sees. Geometry is
//  therefore computed against `image.size` — the orientation-corrected logical
//  size — never against `cgImage.width/height`.
//

import UIKit

nonisolated enum ImageCropper {

    /// Crop `image` to `region`, rendered at up to `maxDimension` points on its
    /// longest side. `nil` when the source has no usable area.
    static func crop(_ image: UIImage, to region: FoodRegion, maxDimension: CGFloat) -> UIImage? {
        let source = image.size
        guard source.width > 0, source.height > 0, maxDimension > 0 else { return nil }

        let cropRect = CGRect(
            x: region.x * source.width,
            y: region.y * source.height,
            width: region.width * source.width,
            height: region.height * source.height
        )
        guard cropRect.width > 0, cropRect.height > 0 else { return nil }

        // Scale down only; never upscale a small crop into a blurry larger one.
        let longest = max(cropRect.width, cropRect.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let outputSize = CGSize(
            width: cropRect.width * scale,
            height: cropRect.height * scale
        )
        guard outputSize.width >= 1, outputSize.height >= 1 else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)

        return renderer.image { _ in
            // Draw the whole image scaled and offset so the wanted region lands in
            // the renderer's bounds. `draw(in:)` honours `imageOrientation`.
            image.draw(
                in: CGRect(
                    x: -cropRect.origin.x * scale,
                    y: -cropRect.origin.y * scale,
                    width: source.width * scale,
                    height: source.height * scale
                )
            )
        }
    }

    /// Every crop for the foods that have a region, keyed by food id.
    ///
    /// One pass over an already-loaded image: a 15-ingredient meal would otherwise
    /// cost 15 extra decodes on top of the load the details screen already does.
    /// Foods without a region are simply absent from the result, and the view shows
    /// its placeholder for them.
    static func crops(
        for foods: [StoredFood],
        from image: UIImage,
        maxDimension: CGFloat
    ) -> [UUID: UIImage] {
        var result: [UUID: UIImage] = [:]
        for food in foods {
            guard
                let region = food.region,
                let thumbnail = crop(image, to: region, maxDimension: maxDimension)
            else { continue }
            result[food.id] = thumbnail
        }
        return result
    }

    /// Scale an image down so its longest side is at most `maxDimension`.
    ///
    /// Scales DOWN only — an image already within the limit is returned untouched,
    /// so nothing is ever upscaled into blur. Shared by the meal-photo store and by
    /// the camera's library picker, which must prepare a picked photo to a size
    /// comparable to a capture. One implementation, because two would drift.
    static func downsized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

}
