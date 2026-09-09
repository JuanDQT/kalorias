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

import SwiftUI

struct AccountDeletionView: View {
    @Environment(AppJourneyStore.self) private var journey

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

                if journey.deletionError != nil {
                    Text("account.delete.error")
                        .supportingTextRole()
                        .foregroundStyle(AppColor.danger)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("account.deleteError")
                        .transition(AppMotion.subtleTransition)
                }

                if !journey.isDeleting {
                    Button {
                        Task { await journey.retryAccountDeletion() }
                    } label: {
                        Text(journey.deletionError == nil ? "common.continue" : "common.tryAgain")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColor.brandPrimaryFill)
                    .controlSize(.large)
                    .accessibilityIdentifier("account.deleteContinueButton")
                }
            }
            .frame(maxWidth: 520)
            .padding(AppSpacing.xxl)
        }
        .animation(AppMotion.subtle, value: journey.isDeleting)
        .animation(AppMotion.subtle, value: journey.deletionError)
        .accessibilityIdentifier("account.deleteScreen")
    }
}

#Preview {
    AccountDeletionView()
        .environment(AppJourneyStore())
}
