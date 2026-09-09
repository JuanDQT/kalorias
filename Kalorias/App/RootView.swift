//
//  RootView.swift
//  Kalorias
//
//  The root: exactly one journey phase on screen, and inside `ready` the tab
//  shell with its Liquid Glass bottom bar and the camera full-screen cover.
//
//  IT SWITCHES; IT NO LONGER COVERS. Until feature 010 the onboarding was a
//  `fullScreenCover` over an already-built tab shell, flipped off by a single
//  `@AppStorage` flag. That was a reasonable trade when "done" meant one thing,
//  and it stopped being one the moment the app grew identity gates: an
//  authenticated view must not exist behind Access or Consent — not built, not
//  warm, not for the length of an animation — because the account it would be
//  showing may belong to somebody else, or to nobody.
//
//  THE PHASE COMES FROM DURABLE STATE, NOT FROM A FLAG. `AppJourneyStore`
//  resolves it from the Keychain and protected storage; see that file for why a
//  Boolean could not.
//
//  EVERY PHASE CHANGE ANIMATES THROUGH `AppMotion.standard`, which is also where
//  Reduce Motion is substituted — no view here checks the setting.
//

import SwiftUI

struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(CameraPermissionStore.self) private var permission
    @Environment(AppJourneyStore.self) private var journey
    @Environment(MealHistoryRepository.self) private var history
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            AppColor.surfacePrimary
                .ignoresSafeArea()

            phaseContent
                .transition(AppMotion.standardTransition)
        }
        .animation(AppMotion.standard, value: journey.phase)
        .task { await journey.bootstrap() }
        // The identity changed: point local history at the new account and tear
        // down whatever the previous one had open, *before* any of it can render
        // over a gate (UI contract, Root Phase Contract).
        .onChange(of: journey.activeUserID, initial: true) { _, userID in
            router.resetForIdentityChange()
            history.setActiveUser(userID)
        }
        // A revocation can happen in Settings while the app is backgrounded, so
        // the credential is re-checked on the way back in.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await journey.applicationDidBecomeActive() }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: AppleCredentialStateService.revocationNotification
            )
        ) { _ in
            Task { await journey.appleCredentialWasRevoked() }
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch journey.phase {
        case .restoring:
            RestoringView()

        case .onboarding:
            OnboardingChatView(store: makeOnboardingStore())

        case .access:
            AccessView()

        case .consent:
            HealthDataConsentView()

        case .finalizing:
            FinalizingOnboardingView()

        case .ready:
            authenticatedShell

        case .deletingAccount:
            AccountDeletionView()
        }
    }

    /// A chat that reports its sealed payload to the journey, and resumes the
    /// existing session identity when the user came back to review answers.
    private func makeOnboardingStore() -> OnboardingStore {
        let store = OnboardingStore(onSealed: { pending in
            journey.onboardingDidSeal(pending)
        })
        if let identity = journey.resumableOnboardingIdentity {
            store.resume(sessionId: identity.sessionId, startedAt: identity.startedAt)
        }
        return store
    }

    // MARK: The authenticated shell

    private var authenticatedShell: some View {
        @Bindable var router = router

        return ZStack {
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
            ProgressTabView(ownerUserID: journey.activeUserID)
        case .history:
            HistoryView(ownerUserID: journey.activeUserID)
        }
    }
}

// MARK: - Restoring

/// What the app shows while it reads its own durable state — including on a
/// locked device, where the protected files simply cannot be opened yet.
struct RestoringView: View {
    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            ProgressView()
                .controlSize(.large)
                .tint(AppColor.brandPrimary)
            Text("journey.restoring.title")
                .supportingTextRole()
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.surfacePrimary)
        .accessibilityIdentifier("journey.restoring")
    }
}

#Preview {
    RootView()
        .environment(Router())
        .environment(CameraPermissionStore())
        .environment(AppJourneyStore())
}
