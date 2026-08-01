//
//  CameraSessionController.swift
//  Kalorias
//
//  Encapsulates the AVFoundation capture session. This type is marked
//  `@unchecked Sendable` because `AVCaptureSession` and `AVCapturePhotoOutput`
//  are not Sendable, yet every mutation of them here is serialized onto the
//  private `sessionQueue` (AVFoundation's supported model). The lone exception
//  is `session`, which is read on the main thread to attach to the preview
//  layer — AVFoundation permits that. This escape is justified per constitution
//  Principle V (documented safety invariant).
//
//  `device` (feature 008, for zoom) obeys the same rule: it is assigned once during
//  configuration and afterwards only read/mutated inside `sessionQueue.async`, so it
//  never crosses a boundary unserialized. `maximumZoomFactor` is the one exception —
//  a plain `Double` snapshot published for the UI to clamp against, which is safe to
//  read because it is written once before it is ever observed.
//

import AVFoundation
import UIKit

nonisolated final class CameraSessionController: @unchecked Sendable {
    /// Read on the main thread only to bind to the preview layer.
    let session = AVCaptureSession()

    private let photoOutput = AVCapturePhotoOutput()
    /// Retained for zoom. Mutated only on `sessionQueue`.
    private var device: AVCaptureDevice?
    /// The device's own ceiling, snapshotted at configuration for `CameraZoom.clamp`.
    /// Defaults to 1 so a not-yet-configured session reports "no zoom available".
    private(set) var maximumZoomFactor: CGFloat = 1.0
    private let sessionQueue = DispatchQueue(label: "com.quispe.kalorias.camera.session")
    private var activeDelegate: PhotoCaptureDelegate?
    private var isConfigured = false

    /// Configure the rear camera + photo output and start running, all on the
    /// session queue. Idempotent: if already configured, it just resumes.
    /// `onFailure` is invoked (off the main thread) when no usable rear camera
    /// can be configured (FR-012 / FR-017).
    func configureAndStart(onFailure: @escaping @Sendable () -> Void) {
        sessionQueue.async { [self] in
            if isConfigured {
                if !session.isRunning { session.startRunning() }
                return
            }

            session.beginConfiguration()
            session.sessionPreset = .photo

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(input),
                session.canAddOutput(photoOutput)
            else {
                session.commitConfiguration()
                onFailure()
                return
            }

            session.addInput(input)
            session.addOutput(photoOutput)
            session.commitConfiguration()
            self.device = device
            self.maximumZoomFactor = device.maxAvailableVideoZoomFactor
            isConfigured = true
            session.startRunning()
        }
    }

    /// Resume a previously-configured session (used when retaking after analysis).
    func resume() {
        sessionQueue.async { [self] in
            if isConfigured, !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    /// Apply a zoom factor to the capture device (feature 008).
    ///
    /// The caller is expected to have clamped it through `CameraZoom` — this only
    /// guards against a device that cannot accept the value at all. Because zoom is
    /// a property of the device, it affects the preview AND the still capture, so the
    /// photo that gets sent always reflects what the user framed (FR-017 / FR-021).
    func setZoom(_ factor: CGFloat) {
        sessionQueue.async { [self] in
            guard let device else { return }
            let supported = min(max(factor, 1.0), device.maxAvailableVideoZoomFactor)
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = supported
                device.unlockForConfiguration()
            } catch {
                // A device that will not lock simply keeps its current zoom; zoom is
                // an enhancement and must never break capture (FR-022).
            }
        }
    }

    /// Capture a still photo; `completion` delivers the image (or nil on
    /// failure) off the main thread.
    func capturePhoto(completion: @escaping @Sendable (UIImage?) -> Void) {
        sessionQueue.async { [self] in
            let settings = AVCapturePhotoSettings()
            let delegate = PhotoCaptureDelegate(completion: completion)
            activeDelegate = delegate
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }
}

/// Bridges the AVFoundation delegate callback (invoked on a background queue)
/// to a Sendable completion. `@unchecked Sendable` because it only forwards an
/// immutable, Sendable closure.
private nonisolated final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let completion: @Sendable (UIImage?) -> Void

    init(completion: @escaping @Sendable (UIImage?) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            completion(nil)
            return
        }
        completion(image)
    }
}
