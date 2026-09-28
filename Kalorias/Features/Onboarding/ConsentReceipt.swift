//
//  ConsentReceipt.swift
//  Kalorias
//
//  Proof that the user said yes to sending and processing their health answers
//  (feature 010, FR-017).
//
//  SIGNING IN WITH APPLE IS NOT THIS. Apple's sheet authorizes an account; it
//  says nothing about a date of birth, a weight or a pregnancy. The spec treats
//  them as two decisions because they are two decisions, and only this receipt
//  permits an upload.
//
//  A RECEIPT NAMES A VERSION, NOT JUST A MOMENT. "They consented" is worthless
//  in a year when nobody can say to what; the receipt pins the exact notice and
//  consent text that was on screen, so a later change to that text cannot
//  retroactively claim to have been agreed to.
//
//  THE VERSIONS ARE BUILD CONFIGURATION, NOT SOURCE FALLBACKS. Product/Legal
//  supplies them with the localized copy and policy URL; an incomplete build is
//  unable to mint a receipt or upload health data.
//
//  ONLY THE AFFIRMATIVE ACTION CREATES ONE. Opening the notice does not, "Not
//  now" does not, and a successful Apple sign-in does not.
//

import Foundation

/// Product/Legal-owned values that identify the exact notice shipped by this
/// build. They arrive through build configuration; source code supplies no
/// fallback and therefore cannot accidentally mint a provisional receipt.
nonisolated struct ConsentConfiguration: Equatable, Sendable {
    static let maximumVersionLength = 32

    let privacyPolicyURL: URL
    let privacyNoticeVersion: String
    let healthDataConsentVersion: String
}

nonisolated struct ConsentReceipt: Codable, Equatable, Sendable {

    /// The published privacy notice the user was shown.
    let privacyNoticeVersion: String
    /// The affirmative health-data consent text the user accepted.
    let healthDataConsentVersion: String
    /// Device time at the moment of acceptance. Client context only — the
    /// backend records its own receipt time and does not trust this one as the
    /// audit authority.
    let grantedAt: Date

    /// The receipt for the copy this build displays.
    init(configuration: ConsentConfiguration, grantedAt: Date) {
        self.privacyNoticeVersion = configuration.privacyNoticeVersion
        self.healthDataConsentVersion = configuration.healthDataConsentVersion
        self.grantedAt = grantedAt
    }

    /// A receipt read back from disk, which may name older approved versions.
    init(privacyNoticeVersion: String, healthDataConsentVersion: String, grantedAt: Date) {
        self.privacyNoticeVersion = privacyNoticeVersion
        self.healthDataConsentVersion = healthDataConsentVersion
        self.grantedAt = grantedAt
    }

    /// Whether this receipt still refers to the copy this build shows. A stored
    /// receipt for retired wording cannot be reused (UI contract, `consent.outdated`).
    func matches(_ configuration: ConsentConfiguration) -> Bool {
        privacyNoticeVersion == configuration.privacyNoticeVersion
            && healthDataConsentVersion == configuration.healthDataConsentVersion
    }
}
