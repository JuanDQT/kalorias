//
//  Router.swift
//  Kalorias
//
//  Owns all navigation state for the app (constitution Principle V — navigation
//  is driven by a dedicated Router, never constructed ad hoc in views). Views
//  observe this and call its intents; they do not mutate navigation directly.
//

import Observation

/// The full-screen flow launched from the center camera action. Exactly one is
/// presented at a time, so the permission gate and the camera never overlap.
enum CameraFlow: Identifiable, Hashable {
    case permission
    case camera

    var id: Self { self }
}

@MainActor
@Observable
final class Router {
    /// The currently shown content tab. Defaults to Progress (FR-003) and is
    /// preserved while a camera flow is presented, so dismissing returns to
    /// exactly this tab (FR-015 / FR-016).
    var selectedTab: AppTab = .progress

    /// The presented full-screen camera flow, if any. Settable so it can back a
    /// `fullScreenCover(item:)` binding; a `nil` write dismisses the flow.
    var cameraFlow: CameraFlow?

    /// Navigation path for the History tab (drill into meal details, feature 003).
    var historyPath: [MealEntry] = []

    /// True while the live camera (not the permission gate) is presented.
    var isCameraPresented: Bool { cameraFlow == .camera }

    func select(_ tab: AppTab) {
        selectedTab = tab
    }

    /// Present the full-screen permission rationale (FR-007).
    func presentPermission() {
        cameraFlow = .permission
    }

    /// Present the live camera (FR-011).
    func presentCamera() {
        cameraFlow = .camera
    }

    /// Dismiss whatever camera flow is showing, returning to `selectedTab`.
    func dismissFlow() {
        cameraFlow = nil
    }

    /// Convenience alias used by the camera capture flow (FR-015 / FR-016).
    func dismissCamera() {
        cameraFlow = nil
    }

    /// Push a meal's details onto the History navigation stack (feature 003).
    func openMeal(_ entry: MealEntry) {
        historyPath.append(entry)
    }
}
