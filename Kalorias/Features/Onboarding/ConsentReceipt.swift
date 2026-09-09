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
//  THE VERSIONS ARE COMPILED IN, NOT FETCHED. Server-delivered consent copy can
//  change silently under the same version string, which would make the receipt a
//  record of nothing. The app ships the text and the version together.
//
//  ONLY THE AFFIRMATIVE ACTION CREATES ONE. Opening the notice does not, "Not
//  now" does not, and a successful Apple sign-in does not.
//

import Foundation

nonisolated struct ConsentReceipt: Codable, Equatable, Sendable {

    /// The published privacy notice the user was shown.
    let privacyNoticeVersion: String
    /// The affirmative health-data consent text the user accepted.
    let healthDataConsentVersion: String
    /// Device time at the moment of acceptance. Client context only — the
    /// backend records its own receipt time and does not trust this one as the
    /// audit authority.
    let grantedAt: Date

    /// The versions this build ships. Changing the on-screen copy means changing
    /// these, which is precisely the point: an old receipt then stops matching
    /// and the user is asked again.
    ///
    /// Approved legal wording and its final version identifiers are a release
    /// input (see the plan's Delivery Boundaries). These constants and the
    /// `consent.*` / `privacy.*` catalog entries move together.
    enum Version {
        static let privacyNotice = "2026-09-08"
        static let healthDataConsent = "2026-09-08"
    }

    /// The receipt for the copy this build displays.
    init(grantedAt: Date) {
        self.privacyNoticeVersion = Version.privacyNotice
        self.healthDataConsentVersion = Version.healthDataConsent
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
    var matchesCurrentVersions: Bool {
        privacyNoticeVersion == Version.privacyNotice
            && healthDataConsentVersion == Version.healthDataConsent
    }
}
