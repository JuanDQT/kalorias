//
//  AccountSettingsView.swift
//  Kalorias
//
//  Where an account can be read about and deleted (feature 010, FR-038).
//
//  IT IS A PUSHED DESTINATION, NOT A ROOT PHASE. Managing an account happens
//  *inside* an authenticated session, so it belongs on `Router.progressPath`.
//  The identity gates are the opposite — they replace the app precisely because
//  no authenticated content may exist behind them.
//
//  IT SHOWS NO IDENTIFIER. Not the Apple subject, not the backend user id, not
//  a request id. They mean nothing to the person reading and everything to
//  anyone who talks them into reading one out (FR-037).
//
//  DELETION CONFIRMS, AND IT IS THE ONLY THING HERE THAT DOES. The alert exists
//  because this action is genuinely irreversible and takes data off two
//  machines. Retrying an upload, cancelling Apple, declining consent and
//  reviewing answers all deliberately do *not* confirm — a confirmation on
//  everything is a confirmation on nothing.
//
//  CONFIRMING WRITES THE ATTEMPT AND LEAVES. The journey persists the operation
//  and swaps the root before the request goes out, so this screen is gone by the
//  time the server hears about it. That is what makes a termination mid-request
//  recoverable instead of a shell full of a deleted account's data.
//
//  LOGOUT INVALIDATES ONLY THIS SESSION. It is deliberately separate from the
//  destructive account action and clears local authority only after `204`.
//

import SwiftUI

struct AccountSettingsView: View {
    @Environment(AppJourneyStore.self) private var journey
    @Environment(Router.self) private var router

    @State private var isConfirmingDeletion = false
    @State private var isShowingPrivacyNotice = false

    var body: some View {
        List {
            Section {
                Text("account.status.signedIn")
                    .supportingTextRole()
                    .foregroundStyle(AppColor.textSecondary)
            } header: {
                Text("account.title")
            }

            if journey.needsAccountTransferHelp {
                Section {
                    Text("account.transfer.body")
                        .supportingTextRole()
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("account.transfer.title")
                }
            }

            Section {
                Button {
                    isShowingPrivacyNotice = true
                } label: {
                    Text("account.privacy")
                }
                .accessibilityIdentifier("account.privacyButton")
            }

            Section {
                Button {
                    Task { await journey.logout() }
                } label: {
                    if journey.isLoggingOut {
                        HStack(spacing: AppSpacing.sm) {
                            ProgressView().controlSize(.small)
                            Text("account.logout.progress")
                        }
                    } else {
                        Text("account.logout")
                    }
                }
                .disabled(journey.isLoggingOut)
                .accessibilityIdentifier("account.logoutButton")

                if journey.logoutError != nil {
                    Text("account.logout.error")
                        .supportingTextRole()
                        .foregroundStyle(AppColor.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("account.logoutError")
                }
            }

            Section {
                Button(role: .destructive) {
                    isConfirmingDeletion = true
                } label: {
                    Text("account.delete")
                }
                .accessibilityIdentifier("account.deleteButton")
            }
        }
        .navigationTitle("account.title")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("account.screen")
        .sheet(isPresented: $isShowingPrivacyNotice) {
            PrivacyNoticeView()
        }
        .confirmationDialog(
            Text("account.delete.confirm.title"),
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                // Clear what the outgoing identity was looking at first: the
                // journey is about to replace the root, and a pushed detail or
                // an open camera must not animate out over the deletion gate.
                router.resetForIdentityChange()
                Task { await journey.confirmAccountDeletion() }
            } label: {
                Text("account.delete.confirm.action")
            }
            .accessibilityIdentifier("account.deleteConfirmButton")

            Button(role: .cancel) {
                isConfirmingDeletion = false
            } label: {
                Text("account.delete.confirm.cancel")
            }
            .accessibilityIdentifier("account.deleteCancelButton")
        } message: {
            Text("account.delete.confirm.body")
        }
    }
}

#Preview {
    NavigationStack {
        AccountSettingsView()
            .environment(AppJourneyStore())
            .environment(Router())
    }
}
