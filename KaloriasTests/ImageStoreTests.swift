//
//  ImageStoreTests.swift
//  KaloriasTests
//

import XCTest
import UIKit
@testable import Kalorias

nonisolated final class ImageStoreTests: XCTestCase {

    private func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageStoreTests-\(UUID().uuidString)", isDirectory: true)
        return url
    }

    private func solidImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40))
        return renderer.image { ctx in
            UIColor.green.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
    }

    func testSaveThenLoadRoundTrip() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DiskImageStore(directory: dir)
        let id = UUID()

        let name = try await store.save(solidImage(), id: id)
        XCTAssertEqual(name, "\(id.uuidString).jpg")
        XCTAssertNotNil(store.loadImage(named: name))
    }

    func testLoadMissingReturnsNil() {
        let store = DiskImageStore(directory: makeTempDir())
        XCTAssertNil(store.loadImage(named: "does-not-exist.jpg"))
    }

    func testDeleteRemovesFile() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DiskImageStore(directory: dir)
        let id = UUID()
        let name = try await store.save(solidImage(), id: id)
        XCTAssertNotNil(store.loadImage(named: name))
        store.delete(named: name)
        XCTAssertNil(store.loadImage(named: name))
    }
}
