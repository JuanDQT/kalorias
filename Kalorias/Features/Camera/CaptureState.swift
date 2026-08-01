//
//  CaptureState.swift
//  Kalorias
//
//  The capture-flow state that drives the Capture ↔ Send button swap. A pure,
//  nonisolated value type so it is usable and testable from any context.
//

import UIKit

nonisolated enum CaptureState {
    /// Live rear preview, no photo taken — shows the Capture button (FR-013).
    case previewing
    /// A photo was taken — shows the Send button (FR-014).
    case captured(UIImage)
    /// No usable camera / configuration failed — shows an error (FR-017).
    case unavailable(String)

    var isPreviewing: Bool {
        if case .previewing = self { return true }
        return false
    }

    var capturedImage: UIImage? {
        if case .captured(let image) = self { return image }
        return nil
    }

    var unavailableMessage: String? {
        if case .unavailable(let message) = self { return message }
        return nil
    }
}
