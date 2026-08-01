//
//  CameraPermissionStore.swift
//  Kalorias
//
//  Owns the camera authorization state machine (constitution Principle V —
//  logic lives in a Store, not in view bodies). Views observe `status` and
//  call the intents.
//

import AVFoundation
import Observation
import UIKit

@MainActor
@Observable
final class CameraPermissionStore {
    private(set) var status: CameraPermissionStatus

    init() {
        status = CameraPermissionStatus(AVCaptureDevice.authorizationStatus(for: .video))
    }

    /// Re-read the current system status (call on appear/foreground). Covers
    /// the "granted in Settings while the rationale is open" edge case.
    func refresh() {
        status = CameraPermissionStatus(AVCaptureDevice.authorizationStatus(for: .video))
    }

    /// Show the native OS prompt when it can still appear (FR-008).
    func requestAccess() async {
        guard status.canRequestNatively else { return }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        status = granted ? .authorized : .denied
    }

    /// Deep-link to the system Settings for this app (FR-010).
    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
