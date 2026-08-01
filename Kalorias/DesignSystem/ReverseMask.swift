//
//  ReverseMask.swift
//  Kalorias
//
//  Masks a view by the INVERSE of another view — used to dim everything outside the
//  camera's send frame by punching the frame out of a full-bleed scrim.
//
//  SwiftUI has `mask(_:)` but no built-in inverse, and hand-drawing four rectangles
//  around a rounded frame would be fragile at the corners.
//

import SwiftUI

extension View {
    /// Keeps this view everywhere the supplied content is *absent*.
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            ZStack {
                Rectangle()
                mask()
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
        }
    }
}
