//
//  RootView.swift
//  Kalorias
//
//  The app shell: shows the content for the currently selected tab above the
//  shared Liquid Glass bottom bar, and presents the camera flow (permission
//  gate or live camera) as a single full-screen cover.
//

import SwiftUI

struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(CameraPermissionStore.self) private var permission

    var body: some View {
        @Bindable var router = router

        ZStack {
            AppColor.surfacePrimary
                .ignoresSafeArea()

            content

            // A floating overlay, deliberately NOT a safe-area inset. Feature 006
            // tried the inset here and it does nothing: `NavigationStack` consumes
            // it and hands its destination a full-screen environment with a bottom
            // inset of 0 (measured: 148 at this level, 0 inside a pushed detail
            // view). Every tab wraps itself in a NavigationStack, so the inset can
            // never reach the scrolling content.
            //
            // Clearance is therefore reserved INSIDE each scroll container, via
            // `BottomBar.scrollClearance`. Keeping only one mechanism means no
            // screen can end up inset twice.
            BottomBar(
                selectedTab: router.selectedTab,
                onSelect: { router.select($0) },
                onCamera: cameraTapped
            )
            .padding(.bottom, 8)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .fullScreenCover(item: $router.cameraFlow) { flow in
            switch flow {
            case .permission:
                CameraPermissionView()
            case .camera:
                CameraCaptureView()
            }
        }
    }

    /// Consult the permission state, then either open the camera directly
    /// (authorized) or present the rationale (FR-007 / FR-009 / FR-011).
    private func cameraTapped() {
        permission.refresh()
        if permission.status.isAuthorized {
            router.presentCamera()
        } else {
            router.presentPermission()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch router.selectedTab {
        case .progress:
            ProgressTabView()
        case .history:
            HistoryView()
        }
    }
}

#Preview {
    RootView()
        .environment(Router())
        .environment(CameraPermissionStore())
}
