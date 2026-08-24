//
//  AppMotion.swift
//  Kalorias
//
//  The app's motion vocabulary. Every animation in the app comes from here.
//
//  WHY IT EXISTS AT ALL. Principle III defaults motion *on* — "every observable
//  state change MUST be animated rather than snapping into place" — and in the
//  same breath forbids the obvious way to do that: "Views MUST NOT construct
//  `.spring(...)` or `.easeInOut(...)` inline and MUST NOT invent per-screen
//  durations." Without a vocabulary those two rules have no legal move between
//  them. The constitution's own answer is that the design system is a
//  prerequisite, not a deliverable: the first feature that needs a piece builds
//  it, in that run. This is that piece, built by feature 009.
//
//  THREE NAMED ANIMATIONS, EACH PAIRED WITH ITS TRANSITION. Pairing is what
//  makes "a surface leaves along the path it arrived by" true by construction
//  rather than by remembering — a view that animates with `standard` uses
//  `standardTransition`, and the two cannot drift apart across call sites.
//
//  CRITICALLY DAMPED BY DEFAULT (`bounce: 0`). Overshoot is reserved for motion
//  a gesture actually threw, which is the only thing `gestural` is for. A plate
//  of calories that bounces into place is decoration, and the constitution calls
//  that out by name.
//
//  REDUCE MOTION IS HANDLED HERE, ONCE. `@Environment(\.accessibilityReduceMotion)`
//  checked per view is how one screen ends up missing it; the vocabulary reads
//  the setting itself, so every call site inherits the substitution and no view
//  can forget. Under Reduce Motion springs become a short cross-fade and every
//  flow stays fully completable.
//
//  The feel was ratified with the maintainer at the Clarification Gate for
//  feature 009: crisp, because this is a habitual, quick-use app and a slower
//  house spring would pad a flow that already waits on the network.
//

import SwiftUI

/// MainActor-isolated (the project's default) rather than `nonisolated`, because
/// it reads `UIAccessibility.isReduceMotionEnabled`, which is. That is the right
/// place for it: motion is consumed by the view layer and nowhere else.
enum AppMotion {

    /// Whether the system is asking for reduced motion.
    ///
    /// Read from UIKit rather than from SwiftUI's environment so the vocabulary
    /// can apply the substitution itself, inside these properties, instead of
    /// requiring every view to check it (see the file comment).
    private static var prefersReducedMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    /// Under Reduce Motion, every animation becomes the same short cross-fade.
    private static let reduced = Animation.easeOut(duration: 0.15)

    // MARK: The three animations

    /// The house spring, used for almost everything: a state change, content
    /// arriving after a load, an error or empty state appearing.
    static var standard: Animation {
        prefersReducedMotion ? reduced : .spring(duration: 0.30, bounce: 0)
    }

    /// Motion a drag or flick actually threw. **The only place overshoot is
    /// permitted**, and it is what makes a thrown surface feel thrown.
    static var gestural: Animation {
        prefersReducedMotion ? reduced : .spring(duration: 0.40, bounce: 0.20)
    }

    /// A small in-place update: a number, a badge, a selection. Short enough to
    /// read as the value changing rather than as the screen doing something.
    static var subtle: Animation {
        prefersReducedMotion ? reduced : .spring(duration: 0.20, bounce: 0)
    }

    // MARK: The transitions they travel with

    /// Pairs with `standard`. The slight scale gives the change a direction —
    /// arriving content grows into place instead of blinking on.
    static var standardTransition: AnyTransition {
        prefersReducedMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.98))
    }

    /// Pairs with `gestural`. A surface leaves by the edge it came from.
    static func gesturalTransition(from edge: Edge) -> AnyTransition {
        prefersReducedMotion
            ? .opacity
            : .move(edge: edge).combined(with: .opacity)
    }

    /// Pairs with `subtle`. Nothing moves; only the value changes.
    static var subtleTransition: AnyTransition { .opacity }
}
