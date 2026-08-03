//
//  CameraPermissionView.swift
//  Kalorias
//
//  Full-screen rationale shown before the native camera-permission prompt
//  (FR-007). "Continue" drives the native prompt when it can still appear,
//  otherwise it deep-links to Settings (FR-008 / FR-010). Surfaces use Apple's
//  native Liquid Glass and the `AppColor` tokens.
//

import SwiftUI

struct CameraPermissionView: View {
    @Environment(CameraPermissionStore.self) private var permission
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            AppColor.surfacePrimary
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(AppColor.brandPrimary)

                Text("permission.title")
                    .font(.title.bold())
                    .foregroundStyle(AppColor.textPrimary)

                Text("permission.body")
                    .font(.body)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)

                Button(action: primaryAction) {
                    Text(primaryButtonTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(AppColor.brandPrimaryFill)
                .controlSize(.large)
                .accessibilityIdentifier("permission.continueButton")
            }
            .padding(32)
            .frame(maxWidth: 420)
        }
        .overlay(alignment: .topTrailing) { closeButton }
        .accessibilityIdentifier("permission.screen")
        .onAppear(perform: proceedIfAuthorized)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { proceedIfAuthorized() }
        }
    }

    private var primaryButtonTitle: LocalizedStringKey {
        permission.status.isPermanentlyBlocked ? "permission.openSettings" : "permission.continue"
    }

    private func primaryAction() {
        if permission.status.canRequestNatively {
            Task {
                await permission.requestAccess()
                proceedIfAuthorized()
            }
        } else if permission.status.isPermanentlyBlocked {
            permission.openSettings()
        } else if permission.status.isAuthorized {
            router.presentCamera()
        }
    }

    /// Re-read status and, if access is now granted, move straight to the camera
    /// (handles the granted-in-Settings edge case).
    private func proceedIfAuthorized() {
        permission.refresh()
        if permission.status.isAuthorized {
            router.presentCamera()
        }
    }

    private var closeButton: some View {
        Button {
            router.dismissFlow()
        } label: {
            Image(systemName: "xmark")
                .font(.headline)
                .padding(12)
        }
        .buttonStyle(.glass)
        .tint(AppColor.textSecondary)
        .padding()
        .accessibilityLabel(Text("camera.cancel"))
    }
}
