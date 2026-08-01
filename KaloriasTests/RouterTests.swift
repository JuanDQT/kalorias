//
//  RouterTests.swift
//  KaloriasTests
//

import XCTest
@testable import Kalorias

nonisolated final class RouterTests: XCTestCase {

    @MainActor
    func testDefaultSelectedTabIsProgress() {
        let router = Router()
        XCTAssertEqual(router.selectedTab, .progress)
        XCTAssertFalse(router.isCameraPresented)
    }

    @MainActor
    func testSelectSwitchesTab() {
        let router = Router()
        router.select(.history)
        XCTAssertEqual(router.selectedTab, .history)
    }

    @MainActor
    func testPresentAndDismissCameraLeaveSelectedTabUnchanged() {
        let router = Router()
        router.select(.history)

        router.presentCamera()
        XCTAssertTrue(router.isCameraPresented)
        XCTAssertEqual(router.selectedTab, .history, "Selected tab must be preserved while the camera is presented")

        router.dismissCamera()
        XCTAssertFalse(router.isCameraPresented)
        XCTAssertEqual(router.selectedTab, .history, "Dismissing the camera returns to the previously shown tab")
    }
}
