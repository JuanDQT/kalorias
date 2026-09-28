//
//  AuthLog.swift
//  Kalorias
//
//  What an authentication or account problem leaves behind (feature 010,
//  FR-037). One `os.Logger`, category `auth`, alongside `analysis`.
//
//  THE LIST OF THINGS THAT MAY BE LOGGED IS SHORT AND CLOSED: a stage name, a
//  stable outcome category, and the server's own `X-Request-Id`. That is enough
//  to match a user's "it wouldn't let me in" to the line in the backend log that
//  says why, and it is the most that can be said without saying something about
//  the person.
//
//  THE LIST OF THINGS THAT MAY NOT IS LONGER, AND IT IS ENFORCED BY THE
//  SIGNATURES BELOW. There is no parameter for an Apple identity token, an
//  authorization code, a Kalorias access or refresh token, a nonce, an Apple
//  subject, an email address, a user id, an answer, a free-text note or a health
//  value — so no call site can pass one, even by accident. `os.Logger`'s default
//  redaction would hide most of them in a release build; "would hide" is not the
//  same guarantee as "was never passed".
//
//  ONLY NON-IDENTIFYING VALUES ARE MARKED `privacy: .public`. A stage and an
//  outcome describe the app, not the user; the request id is server-generated
//  and identifies a request. A log entry that reads `<private>` when the device
//  is finally in your hand cost effort and answers nothing, which is why those
//  three are readable — and why nothing else is passed at all.
//
//  NOTHING HERE REACHES THE UI. No crash reporter, no analytics, no on-screen
//  id, no persisted log file: the system log is the whole mechanism.
//

import Foundation
import os

nonisolated enum AuthLog {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.quispe.kalorias.Kalorias",
        category: "auth"
    )

    /// Where in the journey something happened. A closed set, so a call site
    /// cannot invent a stage name that carries content.
    enum Stage: String {
        case appleAuthorization
        case authenticatedRequest
        case registration
        case sessionRefresh
        case logout
        case onboardingSubmission
        case credentialState
        case accountDeletion
    }

    /// A stage completed. No identifier of any kind travels with it.
    static func success(_ stage: Stage, requestId: String? = nil) {
        logger.info(
            """
            auth ok stage=\(stage.rawValue, privacy: .public) \
            requestId=\(requestId ?? "none", privacy: .public)
            """
        )
    }

    /// A stage failed.
    ///
    /// `outcome` must be a stable category — the `AuthError`/`OnboardingError`
    /// case name — and never the server's prose, which can quote back whatever
    /// was sent to it.
    static func failure(_ stage: Stage, outcome: String, requestId: String? = nil) {
        logger.error(
            """
            auth failed stage=\(stage.rawValue, privacy: .public) \
            outcome=\(outcome, privacy: .public) \
            requestId=\(requestId ?? "none", privacy: .public)
            """
        )
    }

    /// A definitive Apple credential outcome that gated the app. Recorded
    /// because "why was I signed out?" is otherwise unanswerable.
    static func credentialInvalidated(_ state: AppleCredentialState) {
        logger.notice("auth gated reason=\(String(describing: state), privacy: .public)")
    }
}
