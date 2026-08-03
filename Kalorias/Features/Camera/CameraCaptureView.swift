//
//  CameraCaptureView.swift
//  Kalorias
//
//  Full-screen rear camera. Shows a live preview with a centered capture
//  button that becomes a Send button after a shot (FR-012–FR-016). Send and
//  Cancel close the camera and return to the prior tab (Router). If no camera
//  is usable, a clear message is shown instead (FR-017).
//

import PhotosUI
import SwiftUI

struct CameraCaptureView: View {
    @Environment(Router.self) private var router
    @Environment(MealHistoryRepository.self) private var history
    @State private var store = CaptureSessionStore()
    @State private var analysisStore: CalorieAnalysisStore?
    @State private var pickedItem: PhotosPickerItem?

    /// Geometry of the region that will actually be sent (FR-009).
    /// Zoom at the moment the pinch began, so the gesture is relative not absolute.
    @State private var zoomAtGestureStart: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch store.captureState {
            case .previewing, .captured:
                cameraContent
            case .unavailable(let message):
                unavailableView(message)
            }
        }
        .accessibilityIdentifier("camera.screen")
        .onAppear { store.start() }
        .onDisappear { store.stop() }
        .task(id: pickedItem) {
            guard let pickedItem else { return }
            await store.preparePickedPhoto {
                await LibraryPhotoLoader.loadImage(from: pickedItem)
            }
            // Clear the selection so re-picking the same photo works.
            self.pickedItem = nil
        }
        .alert(
            Text("camera.library.failed"),
            isPresented: Binding(
                get: { store.pickFailureMessage != nil },
                set: { if !$0 { store.clearPickFailure() } }
            )
        ) {
            Button("camera.cancel") { store.clearPickFailure() }
        }
        .fullScreenCover(item: $analysisStore) { analysis in
            AnalysisResultView(
                store: analysis,
                onFinish: {
                    analysisStore = nil
                    router.dismissCamera()
                },
                onRetake: {
                    analysisStore = nil
                    store.resumePreview()
                }
            )
        }
    }

    /// Send the captured photo for calorie analysis (feature 002).
    private func startAnalysis(_ image: UIImage) {
        store.stop()
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            dismiss()
            return
        }
        analysisStore = CalorieAnalysisStore(
            imageData: data,
            image: image,
            analyzer: GeminiCalorieService(),
            recorder: history
        )
    }

    // MARK: Live camera / captured photo

    private var cameraContent: some View {
        ZStack {
            GeometryReader { proxy in
                let frame = store.sendFrame.rect(in: proxy.size)

                CameraPreviewLayerView(session: store.session)
                    .accessibilityIdentifier("camera.preview")
                    .onAppear { store.previewSize = proxy.size }
                    .onChange(of: proxy.size) { store.previewSize = $1 }
                    .overlay {
                        // Only drawn while framing — once a photo exists it is already
                        // cropped, so a frame over it would be meaningless.
                        if store.captureState.capturedImage == nil {
                            sendFrameOverlay(frame, in: proxy.size)
                        }
                    }
                    .gesture(zoomGesture)
            }
            .ignoresSafeArea()

            // Freeze the captured still over the live preview.
            if let image = store.captureState.capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            }

            VStack {
                HStack {
                    cancelButton
                    Spacer()
                }
                Spacer()
                if store.captureState.capturedImage == nil {
                    zoomControl
                }
                ZStack {
                    centerControl
                    HStack {
                        libraryButton
                        Spacer()
                    }
                }
            }
            .padding(24)
        }
    }

    /// Relative pinch: the factor multiplies whatever the zoom was when the gesture
    /// started, so a pinch feels continuous rather than jumping.
    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                store.setZoom(zoomAtGestureStart * value.magnification)
            }
            .onEnded { _ in
                zoomAtGestureStart = store.zoomFactor
            }
    }

    /// The zoom indicator, shown only when zoomed (FR-019), and doubling as the
    /// **accessible alternative to pinching**: it is an adjustable element, so
    /// VoiceOver users can change zoom with swipe up/down instead of a two-finger
    /// gesture they may be unable to perform (FR-025). A pinch-only implementation
    /// would make zoom unavailable to them.
    /// The zoom factor as shown, e.g. "2.5" or "3".
    private var formattedZoom: String {
        let value = Double(store.zoomFactor)
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }

    @ViewBuilder
    private var zoomControl: some View {
        let step: CGFloat = 0.5

        // Built with String(format:) over the localized pattern, NOT by interpolating
        // inside Text(...): interpolation would derive the key
        // "camera.zoom.indicator %@", which is not the key in the catalog, and the
        // label would silently render that raw key instead.
        Text(verbatim: String(format: String(localized: "camera.zoom.indicator"), formattedZoom))
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
            .opacity(store.isZoomed ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: store.isZoomed)
            .accessibilityElement()
            .accessibilityLabel(Text("camera.zoom.label"))
            .accessibilityValue(Text(verbatim: formattedZoom))
            .accessibilityIdentifier("camera.zoomIndicator")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: store.setZoom(store.zoomFactor + step)
                case .decrement: store.setZoom(store.zoomFactor - step)
                @unknown default: break
                }
            }
    }

    /// The frame plus a scrim over everything that will be discarded, so the
    /// distinction is obvious rather than implied (FR-009).
    ///
    /// The frame is NOT decorative: its label states that content outside it is not
    /// analyzed, which is the fact a user who cannot see it needs (FR-015).
    private func sendFrameOverlay(_ frame: CGRect, in size: CGSize) -> some View {
        ZStack {
            // Dim outside the frame by punching the frame out of a full-bleed scrim.
            Rectangle()
                .fill(.black.opacity(0.45))
                .reverseMask {
                    RoundedRectangle(cornerRadius: 20)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                }

            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
        }
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(Text("camera.sendFrame.label"))
        .accessibilityIdentifier("camera.sendFrame")
    }

    @ViewBuilder
    private var centerControl: some View {
        if let capturedImage = store.captureState.capturedImage {
            Button {
                startAnalysis(capturedImage)
            } label: {
                Text("camera.send")
                    .font(.headline)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.glassProminent)
            .tint(AppColor.brandPrimaryFill)
            .accessibilityIdentifier("camera.sendButton")
        } else {
            Button {
                store.capturePhoto()
            } label: {
                Circle()
                    .strokeBorder(.white, lineWidth: 5)
                    .frame(width: 76, height: 76)
                    .overlay(Circle().fill(.white).padding(6))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("camera.captureButton")
            .accessibilityLabel(Text("camera.capture"))
        }
    }

    /// Opens the system photo picker. Uses `PhotosPicker`, which runs out of
    /// process and therefore needs **no photo-library permission** (FR-007).
    ///
    /// Icon-only, so it carries an explicit label. Placed bottom-left to balance the
    /// centre capture button without displacing it.
    @ViewBuilder
    private var libraryButton: some View {
        if store.isPreparingPickedPhoto {
            HStack(spacing: 8) {
                ProgressView().tint(.white)
                Text("camera.preparing")
                    .font(.footnote)
                    .foregroundStyle(.white)
            }
            .padding(12)
            .glassEffect(.regular, in: .capsule)
            .accessibilityIdentifier("camera.preparingIndicator")
        } else {
            PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.headline)
                    .padding(12)
            }
            .buttonStyle(.glass)
            .tint(.white)
            .accessibilityIdentifier("camera.libraryButton")
            .accessibilityLabel(Text("camera.library"))
        }
    }

    private var cancelButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.headline)
                .padding(12)
        }
        .buttonStyle(.glass)
        .tint(.white)
        .accessibilityIdentifier("camera.cancelButton")
        .accessibilityLabel(Text("camera.cancel"))
    }

    // MARK: Unavailable

    private func unavailableView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 56))
                .foregroundStyle(.white)
            Text(message)
                .font(.body)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("camera.unavailableMessage")
            // An unusable camera must NOT block picking a photo (FR-005) — this is
            // the whole point of having a second image source.
            libraryButton

            Button {
                dismiss()
            } label: {
                Text("camera.cancel")
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.glassProminent)
            .tint(AppColor.brandPrimaryFill)
            .accessibilityIdentifier("camera.cancelButton")
        }
        .padding(32)
    }

    private func dismiss() {
        store.stop()
        router.dismissCamera()
    }
}
