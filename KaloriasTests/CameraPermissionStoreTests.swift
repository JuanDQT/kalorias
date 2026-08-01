//
//  CameraPermissionStoreTests.swift
//  KaloriasTests
//

import XCTest
import AVFoundation
@testable import Kalorias

nonisolated final class CameraPermissionStoreTests: XCTestCase {

    func testMappingFromSystemStatus() {
        XCTAssertEqual(CameraPermissionStatus(.notDetermined), .notDetermined)
        XCTAssertEqual(CameraPermissionStatus(.authorized), .authorized)
        XCTAssertEqual(CameraPermissionStatus(.denied), .denied)
        XCTAssertEqual(CameraPermissionStatus(.restricted), .restricted)
    }

    func testAuthorizedFlag() {
        XCTAssertTrue(CameraPermissionStatus.authorized.isAuthorized)
        XCTAssertFalse(CameraPermissionStatus.notDetermined.isAuthorized)
        XCTAssertFalse(CameraPermissionStatus.denied.isAuthorized)
        XCTAssertFalse(CameraPermissionStatus.restricted.isAuthorized)
    }

    func testCanRequestNativelyOnlyWhenNotDetermined() {
        XCTAssertTrue(CameraPermissionStatus.notDetermined.canRequestNatively)
        XCTAssertFalse(CameraPermissionStatus.authorized.canRequestNatively)
        XCTAssertFalse(CameraPermissionStatus.denied.canRequestNatively)
        XCTAssertFalse(CameraPermissionStatus.restricted.canRequestNatively)
    }

    func testPermanentlyBlockedForDeniedAndRestricted() {
        XCTAssertTrue(CameraPermissionStatus.denied.isPermanentlyBlocked)
        XCTAssertTrue(CameraPermissionStatus.restricted.isPermanentlyBlocked)
        XCTAssertFalse(CameraPermissionStatus.notDetermined.isPermanentlyBlocked)
        XCTAssertFalse(CameraPermissionStatus.authorized.isPermanentlyBlocked)
    }
}
