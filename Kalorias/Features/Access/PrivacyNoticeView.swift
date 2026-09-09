//
//  PrivacyNoticeView.swift
//  Kalorias
//
//  The approved privacy and health-data notice, reachable from Access, Consent
//  and Account Settings (feature 010).
//
//  READING IS NOT ACCEPTING. Opening this changes nothing and creates no
//  receipt; returning leaves the consent gate exactly as it was. Consent is a
//  deliberate tap on a button that says so.
//
//  THE VERSION SHOWN IS THE VERSION RECORDED. The text ships with the app
//  alongside `ConsentReceipt.Version`, so a receipt can always be matched back
//  to the words that were on screen. Server-delivered consent copy would let the
//  same version string mean different things on different days, which makes the
//  receipt a record of nothing.
//
//  The prose below is the shipping copy for this build. Final legal wording is
//  an approval artifact; when it changes, the version constants change with it
//  and every stored receipt correctly stops matching.
//

import SwiftUI

struct PrivacyNoticeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// The published policy, from the one place the app decides addresses
    /// (constitution, Backend Environments). Absent in a build that has no
    /// policy configured, in which case the notice's own text stands alone.
    private var policyURL: URL? { BackendEnvironment.privacyPolicyURL }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    Text("consent.summary")
                        .supportingTextRole()
                        .foregroundStyle(AppColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let url = policyURL {
                        Button {
                            openURL(url)
                        } label: {
                            Text("privacy.openExternal")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppColor.brandPrimary)
                        .accessibilityIdentifier("privacy.externalPolicyLink")
                    }

                    Text(verbatim: ConsentReceipt.Version.privacyNotice)
                        .sectionLabelRole()
                        .foregroundStyle(AppColor.textSecondary)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(AppSpacing.lg)
                .accessibilityIdentifier("privacy.content")
            }
            .background(AppColor.surfacePrimary)
            .navigationTitle(Text("privacy.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("privacy.done")
                    }
                    .accessibilityIdentifier("privacy.doneButton")
                }
            }
        }
        .accessibilityIdentifier("privacy.screen")
    }
}

#Preview {
    PrivacyNoticeView()
}
