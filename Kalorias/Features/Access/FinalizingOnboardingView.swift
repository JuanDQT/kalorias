//
//  FinalizingOnboardingView.swift
//  Kalorias
//
//  The upload boundary: registered, consented, and sending the sealed answers
//  once (feature 010, FR-024).
//
//  IT NEVER SENDS ANYTHING BY ITSELF ON A RELAUNCH. Exactly one attempt is
//  automatic — the one that follows the consent tap in the same process. After
//  that, and after any restore, the screen shows Continue and waits (FR-033). A
//  screen that retries on every launch takes the decision away from the only
//  person who can see what went wrong, and quietly hammers a struggling server.
//
//  IT NEVER SENDS THE USER BACK THROUGH APPLE while the session can still be
//  renewed. Registration and submission are two commits; a failure in the second
//  has nothing to do with the first (FR-030).
//
//  SUCCESS IS A TRANSITION, NOT A CELEBRATION. There is no confetti and no
//  blocking "well done" step; the app opens the moment the complete status is
//  durable.
//
//  THE PRIMARY ACTION DISABLES ITSELF WHILE A REQUEST IS IN FLIGHT, because two
//  taps must not become two requests — even though the idempotency key would
//  make them harmless on the server.
//

import SwiftUI

struct FinalizingOnboardingView: View {
    @Environment(AppJourneyStore.self) private var journey
    @State private var isShowingPrivacyNotice = false

    var body: some View {
        ZStack {
            AppColor.surfacePrimary.ignoresSafeArea()

            VStack(spacing: AppSpacing.lg) {
                Text("finalization.title")
                    .displayRole()
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)

                Text(body(for: journey))
                    .supportingTextRole()
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if journey.isFinalizing {
                    ProgressView()
                        .controlSize(.large)
                        .tint(AppColor.brandPrimary)
                        .accessibilityIdentifier("finalization.progress")
                        .transition(AppMotion.subtleTransition)
                }

                if let error = journey.finalizationError {
                    Text(String(localized: error.finalizationMessageKey))
                        .supportingTextRole()
                        .foregroundStyle(AppColor.danger)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("finalization.error")
                        .transition(AppMotion.subtleTransition)
                }

                if showsPrimaryAction {
                    Button {
                        Task { await journey.retryFinalization() }
                    } label: {
                        Text(journey.finalizationError == nil ? "common.continue" : "finalization.retry")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColor.brandPrimaryFill)
                    .controlSize(.large)
                    .disabled(journey.isFinalizing)
                    .accessibilityIdentifier("finalization.retryButton")
                }

                Button {
                    isShowingPrivacyNotice = true
                } label: {
                    Text("privacy.title")
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColor.brandPrimary)
                .accessibilityIdentifier("finalization.privacyButton")
            }
            .frame(maxWidth: 520)
            .padding(AppSpacing.xxl)
        }
        .animation(AppMotion.subtle, value: journey.isFinalizing)
        .animation(AppMotion.subtle, value: journey.finalizationError)
        .accessibilityIdentifier("finalization.screen")
        .sheet(isPresented: $isShowingPrivacyNotice) {
            PrivacyNoticeView()
        }
    }

    /// Offered whenever nothing is in flight and the user has to ask: after a
    /// failure, and after a relaunch restored a consented payload.
    private var showsPrimaryAction: Bool {
        !journey.isFinalizing && (journey.finalizationError != nil || journey.finalizationAwaitsUser)
    }

    private func body(for journey: AppJourneyStore) -> LocalizedStringKey {
        journey.isFinalizing ? "finalization.body.uploading" : "finalization.body.resume"
    }
}

#Preview {
    FinalizingOnboardingView()
        .environment(AppJourneyStore())
}
