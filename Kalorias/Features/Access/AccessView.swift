//
//  AccessView.swift
//  Kalorias
//
//  Sign in with Apple, shown *after* the questionnaire (feature 010, FR-001).
//
//  IT ASKS FOR NOTHING BUT THE ACCOUNT. No answers, no name, no email, no
//  password — and the app never sees an Apple Account password at all, because
//  the control below is Apple's own and the credential exchange happens inside
//  the system sheet (FR-010).
//
//  THE APPLE BUTTON IS NOT RESTYLED, and it is not put inside a card. Apple's
//  control has required sizing, spacing and an appearance that must track the
//  colour scheme; wrapping it in the app's own surface is both a HIG violation
//  and a recognisability problem — people look for *that* button.
//
//  CANCELLATION IS NOT AN ERROR. Someone who backed out of the sheet made a
//  choice; showing them a red failure for it is both wrong and slightly
//  accusatory. It gets calm, secondary copy and the button stays enabled.
//
//  "REVIEW ANSWERS" DISAPPEARS ONCE AN ACCOUNT IS COMMITTED. From that moment
//  the sealed payload is the body of an idempotent request that may already be
//  in flight, and editing it under the same key turns a harmless retry into an
//  `idempotency_payload_mismatch`.
//
//  AN OPAQUE SURFACE, NOT GLASS. This is a focused privacy decision on a screen
//  with one action; material and translucency belong over content, and there is
//  no content behind this — by design, nothing authenticated is rendered here.
//

import AuthenticationServices
import SwiftUI

struct AccessView: View {
    @Environment(AppJourneyStore.self) private var journey
    @Environment(\.colorScheme) private var colorScheme

    @State private var requests = AppleSignInRequestFactory()
    @State private var isShowingPrivacyNotice = false

    var body: some View {
        ZStack {
            AppColor.surfacePrimary.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    Text("access.title")
                        .displayRole()
                        .foregroundStyle(AppColor.textPrimary)

                    Text(journey.pending == nil ? "access.body.returning" : "access.body.pending")
                        .supportingTextRole()
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: AppSpacing.xxl)

                    appleButton

                    if journey.canReviewAnswers {
                        Button {
                            journey.reviewAnswers()
                        } label: {
                            Text("access.reviewAnswers").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .accessibilityIdentifier("access.reviewAnswersButton")
                    }

                    status

                    Button {
                        isShowingPrivacyNotice = true
                    } label: {
                        Text("privacy.title")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColor.brandPrimary)
                    .accessibilityIdentifier("access.privacyButton")
                }
                .frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.xxl)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .animation(AppMotion.subtle, value: journey.isAuthenticating)
        .accessibilityIdentifier("access.screen")
        .sheet(isPresented: $isShowingPrivacyNotice) {
            PrivacyNoticeView()
        }
    }

    // MARK: The Apple control

    private var appleButton: some View {
        SignInWithAppleButton(.continue) { request in
            requests.configure(request)
        } onCompletion: { result in
            handle(result)
        }
        // Apple's own control, sized as Apple requires and following the scheme.
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 50)
        .frame(maxWidth: .infinity)
        .disabled(journey.isAuthenticating || journey.accessSecondsUntilRetry != nil)
        .opacity(
            journey.isAuthenticating || journey.accessSecondsUntilRetry != nil
                ? 0.5
                : 1
        )
        .accessibilityIdentifier("access.appleButton")
    }

    private func handle(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential
            else {
                requests.clear()
                journey.appleAuthorizationDidFail(.unexpectedCredentialType)
                return
            }
            switch requests.consume(credential) {
            case let .success(mapped):
                Task { await journey.signIn(with: mapped) }
            case let .failure(error):
                journey.appleAuthorizationDidFail(error)
            }

        case let .failure(error):
            requests.clear()
            let cancelled = (error as? ASAuthorizationError)?.code == .canceled
            journey.appleAuthorizationDidFail(cancelled ? .cancelled : .failed)
        }
    }

    // MARK: Status

    @ViewBuilder
    private var status: some View {
        if journey.isAuthenticating {
            HStack(spacing: AppSpacing.sm) {
                ProgressView().controlSize(.small)
                Text("finalization.body.uploading")
                    .supportingTextRole()
                    .foregroundStyle(AppColor.textSecondary)
            }
            .accessibilityIdentifier("access.progress")
            .transition(AppMotion.subtleTransition)
        } else if let error = journey.accessError {
            Text(String(localized: error.messageKey))
                .supportingTextRole()
                .foregroundStyle(AppColor.danger)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("access.error")
                .transition(AppMotion.subtleTransition)
        } else if let notice = journey.accessNotice {
            // Cancellation reads as information, not as a fault.
            Text(String(localized: notice.messageKey))
                .supportingTextRole()
                .foregroundStyle(
                    notice.isUserCancellation ? AppColor.textSecondary : AppColor.danger
                )
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("access.error")
                .transition(AppMotion.subtleTransition)
        }
    }
}

#Preview {
    AccessView()
        .environment(AppJourneyStore())
}
