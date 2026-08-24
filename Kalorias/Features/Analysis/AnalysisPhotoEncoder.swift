//
//  AnalysisPhotoEncoder.swift
//  Kalorias
//
//  Turns a captured or picked photo into the JPEG that gets uploaded.
//
//  THIS FIXES A LATENT BUG, not just a size preference. The capture site used to
//  send `jpegData(compressionQuality: 0.8)` at full capture resolution, which on
//  a 48 MP device can exceed the server's 8 MB limit outright — a `422` on the
//  one photo the user cared about (SC-006).
//
//  1024 IS NOT ARBITRARY: it is the size the server analyses at. Sending more
//  resolution buys no accuracy and costs upload time on a phone connection.
//
//  THE CAP IS 7.5 MB, NOT 8. The server's limit applies to the multipart body —
//  the JPEG plus its boundary and headers — and its check may be on the raw byte
//  count, so sizing the photo to exactly the limit is how you get a `422` on the
//  one photo that matters.
//
//  THE QUALITY LADDER SHOULD NEVER FIRE. At 1024 a JPEG measures 100–300 KB, so
//  0.6 and 0.4 are a guard against something unforeseen, not a routine path.
//
//  IT LIVES AT THE CAPTURE SITE, not inside the network service: that keeps
//  `CalorieAnalyzing` shaped around `analyze(imageData:)`, keeps the service free
//  of UIKit, and means a retry re-sends bytes that are already prepared instead
//  of re-encoding the image on every attempt.
//

import UIKit

nonisolated enum AnalysisPhotoEncoder {

    /// The longest side, **in pixels**, that the server analyses at.
    ///
    /// Pixels rather than points is the whole point: the upload is measured in
    /// bytes, and on a 3x device a 1024-*point* image carries 3072 pixels and
    /// nine times the data — which is the bloat this encoder exists to remove.
    static let maxDimension: CGFloat = 1024

    /// Below the server's 8 MB, leaving room for multipart overhead.
    static let maxByteCount = 7_500_000

    /// Tried in order, and only while the result is still over the cap.
    static let qualityLadder: [CGFloat] = [0.8, 0.6, 0.4]

    /// JPEG data ready to upload, or `nil` when even the lowest quality will not
    /// fit — in which case the caller shows `.photoRejected` rather than
    /// dismissing silently (FR-023).
    static func encode(_ image: UIImage) -> Data? {
        // Scales down only, and in pixels: an image already within the limit
        // keeps its dimensions, so nothing is upscaled into blur (rule P5).
        let sized = ImageCropper.downsizedToPixels(image, maxPixels: maxDimension)

        for quality in qualityLadder {
            // Always JPEG, whatever the source — a HEIC or PNG from the library
            // is converted here, because the contract accepts nothing else.
            guard let data = sized.jpegData(compressionQuality: quality) else { continue }
            if data.count <= maxByteCount { return data }
        }

        return nil
    }
}
