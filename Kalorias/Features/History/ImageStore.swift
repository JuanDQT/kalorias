//
//  ImageStore.swift
//  Kalorias
//
//  Stores meal photos as downsized JPEG files on disk (not DB blobs), so the
//  history list stays fast (FR-012 / SC-002). `save` runs its encode/write off
//  the main thread because the type is nonisolated and the method is async.
//
//  PHOTOS OF FOOD ARE PERSONAL DATA (feature 010). They are written with
//  complete file protection, like the onboarding answers, because a plate is
//  also a place, a time and often a face in the background.
//
//  BATCH DELETION EXISTS FOR ACCOUNT DELETION. Removing one account's meals
//  means removing a set of files, and doing that one `await` at a time across
//  hundreds of rows is both slow and — because it can be interrupted halfway —
//  no more correct. The batch runs off the main actor and is idempotent, so a
//  cleanup that is killed resumes safely on the next attempt.
//

import UIKit

protocol ImageStoring: Sendable {
    /// Downsize, encode, and write the image; returns the stored file name.
    nonisolated func save(_ image: UIImage, id: UUID) async throws -> String
    /// Load a stored image, or nil if it is missing/unreadable.
    nonisolated func loadImage(named name: String) -> UIImage?
    /// Delete a stored image file.
    nonisolated func delete(named name: String)
    /// Delete a set of stored image files. Idempotent: names that are already
    /// gone are success, which is what makes an interrupted cleanup resumable.
    nonisolated func delete(named names: [String]) async
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
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        let name = "\(id.uuidString).jpg"
        let destination = directory.appendingPathComponent(name)
        try data.write(to: destination, options: [.atomic, .completeFileProtection])
        // Set again after the atomic replace, which swaps the item rather than
        // rewriting it and does not necessarily carry the attribute across.
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: destination.path
        )
        return name
    }

    nonisolated func loadImage(named name: String) -> UIImage? {
        UIImage(contentsOfFile: directory.appendingPathComponent(name).path)
    }

    nonisolated func delete(named name: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }

    /// `async` so the whole batch runs off the main actor: account deletion can
    /// be hundreds of files, and the caller is a `@MainActor` store.
    nonisolated func delete(named names: [String]) async {
        for name in names where !name.isEmpty {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
