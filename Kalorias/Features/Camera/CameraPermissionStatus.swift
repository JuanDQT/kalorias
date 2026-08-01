//
//  CameraPermissionStatus.swift
//  Kalorias
//
//  A pure, testable mapping of the system camera authorization status. Kept
//  free of side effects so it can be unit-tested without a device.
//

import AVFoundation

nonisolated enum CameraPermissionStatus: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted

    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .authorized: self = .authorized
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .notDetermined: self = .notDetermined
        @unknown default: self = .denied
        }
    }

    /// Camera access is granted; the camera can open directly (FR-011).
    var isAuthorized: Bool { self == .authorized }

    /// The native OS prompt can still be shown (FR-008).
    var canRequestNatively: Bool { self == .notDetermined }

    /// The native prompt will not appear again; the user must use Settings
    /// (FR-010).
    var isPermanentlyBlocked: Bool { self == .denied || self == .restricted }
}
