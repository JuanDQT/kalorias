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
//  THE VERSION SHOWN IS THE VERSION RECORDED. The text ships with the app and
//  its Product/Legal-owned identifier arrives through build configuration, so a
//  receipt can always be matched back to the words that were on screen.
//
//  The prose below is the shipping copy for this build. Final legal wording is
//  an approval artifact; when it changes, its configured identifier changes
//  with it and every stored receipt correctly stops matching.
//

import SwiftUI

struct PrivacyNoticeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// Passed from the journey on the consent gate so the displayed URL and
    /// version are exactly the values its receipt will record. Other entry
    /// points use this build's same validated configuration.
    private let configuration: ConsentConfiguration?

    init(configuration: ConsentConfiguration? = BackendEnvironment.consentConfiguration) {
        self.configuration = configuration
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    Text("consent.summary")
                        .supportingTextRole()
                        .foregroundStyle(AppColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let url = configuration?.privacyPolicyURL {
                        Button {
                            openURL(url)
                        } label: {
                            Text("privacy.openExternal")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppColor.brandPrimary)
                        .accessibilityIdentifier("privacy.externalPolicyLink")
                    }

                    if let version = configuration?.privacyNoticeVersion {
                        Text(verbatim: version)
                            .sectionLabelRole()
                            .foregroundStyle(AppColor.textSecondary)
                            .accessibilityHidden(true)
                    } else {
                        Text("consent.configurationError")
                            .supportingTextRole()
                            .foregroundStyle(AppColor.danger)
                    }
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
