//
//  CaptureSessionStore.swift
//  Kalorias
//
//  Owns the camera capture state machine (constitution Principle V). The
//  AVFoundation session lives in `CameraSessionController` (off the main
//  thread); this store only holds observable UI state on the main actor.
//  The state-transition methods are pure and unit-testable without hardware.
//

import AVFoundation
import Observation
import UIKit

@MainActor
@Observable
final class CaptureSessionStore {
    private(set) var captureState: CaptureState = .previewing

    /// True while a picked library photo is being loaded and resized. Drives the
    /// loading state so the screen never appears frozen (FR-027).
    private(set) var isPreparingPickedPhoto = false

    /// Set when a picked item could not be decoded; cleared when the preview
    /// resumes. A failure must be visible, never silent (FR-006).
    private(set) var pickFailureMessage: String?

    /// Size of the live preview, reported by the view. Combined with the captured
    /// image's own size this yields the framed region — see
    /// `SendFrame.imageRegion(previewSize:imageSize:)`.
    var previewSize: CGSize = .zero

    /// Frame geometry. Must match what the view draws, so both read this one value.
    let sendFrame = SendFrame()

    /// Current magnification. Always a clamped value — the raw gesture never reaches
    /// the device (FR-018).
    private(set) var zoomFactor: CGFloat = CameraZoom.minimumFactor

    /// Whether the zoom indicator should show (FR-019).
    var isZoomed: Bool { !CameraZoom.isDefault(zoomFactor) }

    /// The device's ceiling, for the gesture to clamp against.
    var maximumZoomFactor: CGFloat { controller.maximumZoomFactor }

    private let controller = CameraSessionController()

    /// The session to hand to the preview layer.
    var session: AVCaptureSession { controller.session }

    // MARK: Hardware lifecycle

    func start() {
        captureState = .previewing
        resetZoom()
        controller.configureAndStart { [weak self] in
            Task { @MainActor in self?.markUnavailable() }
        }
    }

    func stop() {
        controller.stop()
    }

    /// Return to a live preview after an analysis was dismissed for a retake.
    func resumePreview() {
        pickFailureMessage = nil
        captureState = .previewing
        resetZoom()
        controller.resume()
    }

    // MARK: Zoom (feature 008)

    /// Set the zoom, clamping first. Ignored once a photo exists: the gesture must
    /// not appear to alter an image that has already been taken (FR-020).
    func setZoom(_ requested: CGFloat) {
        guard captureState.isPreviewing else { return }

        let clamped = CameraZoom.clamp(requested, deviceMaximum: controller.maximumZoomFactor)
        zoomFactor = clamped
        controller.setZoom(clamped)
    }

    /// Back to 1× whenever the live preview (re)starts, so a zoom left from a previous
    /// meal cannot silently frame the next one.
    private func resetZoom() {
        zoomFactor = CameraZoom.minimumFactor
        controller.setZoom(CameraZoom.minimumFactor)
    }

    // MARK: Library photo (feature 008)

    /// Run `load` to obtain a picked photo and hand it to the existing confirmation
    /// state, owning the loading and failure transitions around it.
    ///
    /// Takes a closure rather than a `PhotosPickerItem` on purpose: the picker's type
    /// belongs to the view layer, and this store holds camera UI state, not UI
    /// framework types (Principle V). The view supplies the loading; the store owns
    /// what the screen shows while it happens and afterwards.
    ///
    /// The picked image enters `CaptureState.captured` — the SAME state a capture
    /// uses — so Send, back-out, analysis and storage all work through one path and
    /// a library photo cannot diverge from a captured one (FR-002 / FR-003).
    ///
    /// A picked photo is **downsized but never cropped**: the send frame is a
    /// camera-framing tool, not a library editor.
    func preparePickedPhoto(_ load: () async -> UIImage?) async {
        pickFailureMessage = nil
        isPreparingPickedPhoto = true
        defer { isPreparingPickedPhoto = false }

        guard let image = await load() else {
            pickFailureMessage = String(localized: "camera.library.failed")
            // Stay on / return to the live preview so the user can try again.
            if captureState.capturedImage != nil { captureState = .previewing }
            return
        }

        // Stop the live camera: an image is ready to send, exactly as after a shot.
        controller.stop()
        captureState = .captured(image)
    }

    /// Dismiss a pick failure without changing anything else.
    func clearPickFailure() {
        pickFailureMessage = nil
    }

    func capturePhoto() {
        let frame = sendFrame
        let preview = previewSize
        controller.capturePhoto { [weak self] image in
            Task { @MainActor in
                guard let self else { return }
                if let image {
                    // The region depends on the captured image's own size, so it can
                    // only be computed now, not when the preview laid out.
                    let region = frame.imageRegion(
                        previewSize: preview, imageSize: image.size
                    )
                    self.didCapture(Self.cropped(image, to: region))
                } else {
                    self.markUnavailable()
                }
            }
        }
    }

    /// Crop a capture to the send frame.
    ///
    /// `maxDimension` is deliberately large: `ImageCropper` scales DOWN only, so a
    /// generous ceiling yields the crop at native resolution. FR-013 forbids
    /// upscaling to reach a fixed size, which is why no floor is applied.
    ///
    /// **When there is no usable region the FULL image is returned**, and because it
    /// is the returned image that enters `.captured`, the confirmation step shows
    /// exactly that. The user always confirms what will be sent — a missing region
    /// must never mean "quietly send something different from what was shown"
    /// (FR-010 / FR-012).
    private static func cropped(_ image: UIImage, to region: FoodRegion?) -> UIImage {
        guard let region else { return image }
        guard let crop = ImageCropper.crop(image, to: region, maxDimension: 4096) else {
            return image
        }

        assertSquarePixels(crop)
        return crop
    }

    /// The runtime guard standing in for a unit test the layer conversion cannot have.
    ///
    /// A centred square frame must map to an EQUAL-SIDED pixel rect — verified
    /// numerically across layer and image aspect ratios (1653², 1575², 1977², 1883²).
    /// Note the *normalized* rect is deliberately not square; only the pixel rect is.
    /// Transposed axes, a forgotten gravity crop, or a wrong orientation each break
    /// this. It does not catch a uniform offset, which is why the physical check
    /// (food outside the frame must not appear) is also required.
    private static func assertSquarePixels(_ crop: UIImage) {
        let width = crop.size.width * crop.scale
        let height = crop.size.height * crop.scale
        let longest = max(width, height)
        guard longest > 0 else { return }

        let skew = abs(width - height) / longest
        assert(
            skew < 0.02,
            """
            Send-frame crop is not square (\(Int(width))x\(Int(height))). A centred \
            square frame must map to equal pixel sides; this means the layer-rect \
            conversion is transposing axes, ignoring the aspect-fill crop, or \
            applying the wrong orientation.
            """
        )
    }

    // MARK: Pure state transitions (testable)

    /// previewing → captured (FR-014).
    func didCapture(_ image: UIImage) {
        captureState = .captured(image)
    }

    /// captured → previewing; no-op once unavailable (single-photo rule).
    func reset() {
        guard captureState.unavailableMessage == nil else { return }
        captureState = .previewing
    }

    /// Enter the unavailable state with a localized message (FR-017).
    func markUnavailable() {
        captureState = .unavailable(String(localized: "camera.unavailable"))
    }
}
