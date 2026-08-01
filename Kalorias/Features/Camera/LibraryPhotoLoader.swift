//
//  LibraryPhotoLoader.swift
//  Kalorias
//
//  Turns a photo the user picked from their library into an image ready to send.
//
//  Uses `PhotosPickerItem`, which comes from the out-of-process system picker: the
//  app only ever receives the items the user explicitly chose and never gains
//  access to the library, so there is **no authorisation prompt and no usage
//  description** (FR-007). That is the reason for choosing this API over the older
//  in-process picker, which would require both.
//
//  A picked photo can be far larger than a capture, so it is downsized through the
//  shared `ImageCropper.downsized` to a comparable dimension — analysis cost and
//  latency must not depend on where the image came from (FR-008). Loading and
//  resizing happen off the main thread.
//

import PhotosUI
import SwiftUI
import UIKit

nonisolated enum LibraryPhotoLoader {
    /// Matches the meal-photo store's limit, so a picked photo and a capture reach
    /// the analysis at a comparable size.
    static let maxDimension: CGFloat = 1024

    /// Load, decode and downsize a picked item.
    ///
    /// Returns `nil` rather than throwing for anything the system cannot give us as
    /// an image — an unsupported format, or an iCloud asset whose download failed.
    /// The caller turns that into a visible message and resumes the preview
    /// (FR-006); it is never a silent failure.
    static func loadImage(from item: PhotosPickerItem) async -> UIImage? {
        guard
            let data = try? await item.loadTransferable(type: Data.self),
            let image = UIImage(data: data)
        else {
            return nil
        }
        return downsize(image)
    }

    /// Exposed separately so the resizing step is reachable without a picker item.
    static func downsize(_ image: UIImage) -> UIImage {
        ImageCropper.downsized(image, maxDimension: maxDimension)
    }
}
