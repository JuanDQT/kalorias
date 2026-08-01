//
//  CameraPreviewLayerView.swift
//  Kalorias
//
//  Bridges `AVCaptureVideoPreviewLayer` into SwiftUI for the live rear preview.
//
//  This view deliberately does NOT convert the send frame into image coordinates.
//  An earlier attempt used `metadataOutputRectConverted(fromLayerRect:)`, whose
//  result lives in the metadata output space — the sensor's landscape buffer — while
//  the captured `UIImage` reports an orientation-corrected size. Mixing the two
//  transposed the axes and produced a 3563x6334 crop where a square was required.
//
//  The mapping now lives in `SendFrame.imageRegion(previewSize:imageSize:)`, computed
//  in the image's own coordinate space, with no rotation to reason about and no
//  hardware needed to test it.
//

import AVFoundation
import SwiftUI
import UIKit

struct CameraPreviewLayerView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        // The send-frame geometry assumes this gravity; changing it requires
        // revisiting `SendFrame.imageRegion(previewSize:imageSize:)`.
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            // Safe: `layerClass` guarantees the backing layer's type.
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
