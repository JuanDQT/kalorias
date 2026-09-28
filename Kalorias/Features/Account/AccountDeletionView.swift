//
//  AccountDeletionView.swift
//  Kalorias
//
//  The root gate that stands in front of a confirmed account deletion
//  (feature 010, FR-040a).
//
//  IT REPLACES THE APP, IT DOES NOT SIT OVER IT. Once the user confirms, the
//  server may delete the account at any moment; continuing to render meals and
//  totals behind a spinner would be showing someone data that no longer exists
//  anywhere else. So this is a root phase, and bootstrap restores it ahead of
//  everything — including a session that still looks valid.
//
//  A FAILURE DELETES NOTHING. Any result that is not `204` leaves every local
//  record, file and credential exactly where it was and offers a retry
//  (FR-040). "Probably deleted" is not a state this app acts on.
//
//  CONTINUE REPLAYS THE SAME OPERATION, presenting the exact bearer and key the
//  confirmation recorded. After a successful server deletion there is nothing
//  left to refresh against, and only those exact values match the backend's
//  deletion tombstone — which is what turns a lost `204` into a recoverable
//  situation instead of an account that is gone on the server and present here.
//

import AuthenticationServices
import SwiftUI

struct AccountDeletionView: View {
    @Environment(AppJourneyStore.self) private var journey
    @Environment(\.colorScheme) private var colorScheme
    @State private var requests = AppleSignInRequestFactory()

    var body: some View {
        ZStack {
            AppColor.surfacePrimary.ignoresSafeArea()

            VStack(spacing: AppSpacing.lg) {
                Text("account.delete.progress")
                    .rowTitleRole()
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)

                if journey.isDeleting {
                    ProgressView()
                        .controlSize(.large)
                        .tint(AppColor.brandPrimary)
                        .accessibilityIdentifier("account.deleteProgress")
                        .transition(AppMotion.subtleTransition)
                }

                if let deletionError = journey.deletionError {
                    Text(
                        deletionError == .reauthenticationRequired
                            ? "account.delete.reauthenticate.body"
                            : "account.delete.error"
                    )
                        .supportingTextRole()
                        .foregroundStyle(AppColor.danger)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("account.deleteError")
                        .transition(AppMotion.subtleTransition)
                }

                if journey.deletionError == .reauthenticationRequired {
                    appleButton

                    if let notice = journey.deletionAuthorizationNotice {
                        Text(String(localized: notice.messageKey))
                            .supportingTextRole()
                            .foregroundStyle(
                                notice.isUserCancellation
                                    ? AppColor.textSecondary
                                    : AppColor.danger
                            )
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("account.deleteReauthenticationError")
                    }
                } else if !journey.isDeleting {
                    Button {
                        Task { await journey.retryAccountDeletion() }
                    } label: {
                        Text(journey.deletionError == nil ? "common.continue" : "common.tryAgain")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColor.brandPrimaryFill)
                    .controlSize(.large)
                    .disabled(journey.deletionSecondsUntilRetry != nil)
                    .accessibilityIdentifier("account.deleteContinueButton")

                    if journey.deletionSecondsUntilRetry != nil {
                        Text("account.delete.rateLimited")
                            .supportingTextRole()
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
            .frame(maxWidth: 520)
            .padding(AppSpacing.xxl)
        }
        .animation(AppMotion.subtle, value: journey.isDeleting)
        .animation(AppMotion.subtle, value: journey.deletionError)
        .accessibilityIdentifier("account.deleteScreen")
    }

    private var appleButton: some View {
        SignInWithAppleButton(.continue) { request in
            requests.configure(request)
        } onCompletion: { result in
            handle(result)
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 50)
        .frame(maxWidth: .infinity)
        .disabled(journey.isAuthenticating)
        .opacity(journey.isAuthenticating ? 0.5 : 1)
        .accessibilityIdentifier("account.deleteAppleButton")
    }

    private func handle(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential
            else {
                requests.clear()
                journey.accountDeletionAuthorizationDidFail(.unexpectedCredentialType)
                return
            }
            switch requests.consume(credential) {
            case let .success(mapped):
                Task { await journey.reauthenticateAccountDeletion(with: mapped) }
            case let .failure(error):
                journey.accountDeletionAuthorizationDidFail(error)
            }

        case let .failure(error):
            requests.clear()
            let cancelled = (error as? ASAuthorizationError)?.code == .canceled
            journey.accountDeletionAuthorizationDidFail(cancelled ? .cancelled : .failed)
        }
    }
}

#Preview {
    AccountDeletionView()
        .environment(AppJourneyStore())
}
