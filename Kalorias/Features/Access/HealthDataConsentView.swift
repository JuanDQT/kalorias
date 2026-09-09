//
//  HealthDataConsentView.swift
//  Kalorias
//
//  Explicit permission to send and process the answers already given
//  (feature 010, FR-017).
//
//  SIGNING IN WITH APPLE DID NOT ASK THIS. Apple's sheet authorised an account;
//  it said nothing about a date of birth, a weight or a pregnancy. Those are
//  special-category data, they are the entire content of the payload waiting on
//  this device, and the decision to send them is a separate one taken here.
//
//  NOTHING IS PRESELECTED, NOTHING TIMES OUT, NOTHING IS INFERRED. There is no
//  pre-ticked box and no "continuing means you agree": the affirmative tap is
//  the only thing that creates a receipt.
//
//  "NOT NOW" IS A REAL OPTION AND COSTS NOTHING. The account stays, the answers
//  stay on the device, and no request is made (FR-018). A consent screen with
//  only one way out is not a consent screen.
//
//  THE RECEIPT IS WRITTEN BEFORE THE UPLOAD. If the write fails, the user sees a
//  storage error and *nothing is sent* — the permission has to be recorded
//  before the data it covers leaves the phone.
//

import SwiftUI

struct HealthDataConsentView: View {
    @Environment(AppJourneyStore.self) private var journey
    @State private var isShowingPrivacyNotice = false

    var body: some View {
        ZStack {
            AppColor.surfacePrimary.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    Text("consent.title")
                        .displayRole()
                        .foregroundStyle(AppColor.textPrimary)

                    Text("consent.summary")
                        .supportingTextRole()
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("consent.summary")

                    Button {
                        isShowingPrivacyNotice = true
                    } label: {
                        Text("privacy.title")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColor.brandPrimary)
                    .accessibilityIdentifier("consent.privacyButton")

                    Spacer(minLength: AppSpacing.xl)

                    if let failure = journey.consentError {
                        Text(failure == .storage ? "consent.storageError" : "consent.outdated")
                            .supportingTextRole()
                            .foregroundStyle(AppColor.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("consent.error")
                            .transition(AppMotion.subtleTransition)
                    }

                    Button {
                        Task { await journey.acceptHealthDataConsent() }
                    } label: {
                        Text("consent.accept").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColor.brandPrimaryFill)
                    .controlSize(.large)
                    .disabled(journey.isFinalizing)
                    .accessibilityIdentifier("consent.acceptButton")

                    Button {
                        journey.declineHealthDataConsent()
                    } label: {
                        Text("consent.notNow").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("consent.notNowButton")
                }
                .frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.xxl)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .animation(AppMotion.subtle, value: journey.consentError)
        .accessibilityIdentifier("consent.screen")
        .sheet(isPresented: $isShowingPrivacyNotice) {
            PrivacyNoticeView()
        }
    }
}

#Preview {
    HealthDataConsentView()
        .environment(AppJourneyStore())
}
