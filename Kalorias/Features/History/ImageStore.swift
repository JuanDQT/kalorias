//
//  ImageStore.swift
//  Kalorias
//
//  Stores meal photos as downsized JPEG files on disk (not DB blobs), so the
//  history list stays fast (FR-012 / SC-002). `save` runs its encode/write off
//  the main thread because the type is nonisolated and the method is async.
//

import UIKit

protocol ImageStoring: Sendable {
    /// Downsize, encode, and write the image; returns the stored file name.
    nonisolated func save(_ image: UIImage, id: UUID) async throws -> String
    /// Load a stored image, or nil if it is missing/unreadable.
    nonisolated func loadImage(named name: String) -> UIImage?
    /// Delete a stored image file.
    nonisolated func delete(named name: String)
}

enum ImageStoreError: Error {
    case encodingFailed
}

nonisolated struct DiskImageStore: ImageStoring {
    private let directory: URL
    private let maxDimension: CGFloat

    init(directory: URL? = nil, maxDimension: CGFloat = 1024) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = base.appendingPathComponent("MealImages", isDirectory: true)
        }
        self.maxDimension = maxDimension
    }

    func save(_ image: UIImage, id: UUID) async throws -> String {
        let resized = ImageCropper.downsized(image, maxDimension: maxDimension)
        guard let data = resized.jpegData(compressionQuality: 0.8) else {
            throw ImageStoreError.encodingFailed
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "\(id.uuidString).jpg"
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        return name
    }

    nonisolated func loadImage(named name: String) -> UIImage? {
        UIImage(contentsOfFile: directory.appendingPathComponent(name).path)
    }

    nonisolated func delete(named name: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }
}
