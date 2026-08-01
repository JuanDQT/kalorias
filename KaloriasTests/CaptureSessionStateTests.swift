//
//  CaptureSessionStateTests.swift
//  KaloriasTests
//

import XCTest
import UIKit
@testable import Kalorias

nonisolated final class CaptureSessionStateTests: XCTestCase {

    @MainActor
    func testStartsInPreviewing() {
        let store = CaptureSessionStore()
        XCTAssertTrue(store.captureState.isPreviewing)
        XCTAssertNil(store.captureState.capturedImage)
    }

    @MainActor
    func testDidCaptureMovesToCaptured() {
        let store = CaptureSessionStore()
        let image = UIImage()
        store.didCapture(image)
        XCTAssertNotNil(store.captureState.capturedImage)
        XCTAssertFalse(store.captureState.isPreviewing)
    }

    @MainActor
    func testResetReturnsToPreviewing() {
        let store = CaptureSessionStore()
        store.didCapture(UIImage())
        store.reset()
        XCTAssertTrue(store.captureState.isPreviewing)
        XCTAssertNil(store.captureState.capturedImage)
    }

    @MainActor
    func testMarkUnavailableSetsMessageAndBlocksReset() {
        let store = CaptureSessionStore()
        store.markUnavailable()
        XCTAssertNotNil(store.captureState.unavailableMessage)

        // reset must not clear an unavailable state.
        store.reset()
        XCTAssertNotNil(store.captureState.unavailableMessage)
    }
}
