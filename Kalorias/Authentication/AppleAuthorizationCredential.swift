//
//  AppleAuthorizationCredential.swift
//  Kalorias
//
//  What one successful Apple authorization hands to the Kalorias backend, and
//  nothing more (feature 010, FR-013, FR-014).
//
//  IT CARRIES NO ONBOARDING DATA, and the type is the enforcement. There is no
//  field for an answer, a profile value or a free-text note, so the request that
//  creates an account cannot smuggle one — a property the spec asks to be
//  provable by inspecting the encoded body, not by reading the call site.
//
//  IT IS NEVER PERSISTED AND NEVER LOGGED. The identity token and authorization
//  code are single-use credentials with real value for the seconds they live;
//  both string descriptions are overridden so an interpolation cannot leak one
//  into a console (FR-037).
//
//  NOTHING HERE IS TRUSTED CLIENT-SIDE. The app does not decode the identity
//  token, does not read its subject, and does not decide who the user is. The
//  backend verifies Apple's signature and derives the subject itself; the app's
//  job is to carry the evidence intact (FR-015).
//

import Foundation

nonisolated struct AppleAuthorizationCredential: Equatable, Sendable {
    /// The compact JWS Apple signed. Verified by the backend, never by the app.
    let identityToken: String
    /// Apple's single-use code, exchanged server-side.
    let authorizationCode: String
    /// Apple's stable identifier for this user on this app. Kept *only* so
    /// `ASAuthorizationAppleIDProvider` can later be asked whether the
    /// credential still exists; it is not sent as an identity claim, because a
    /// client-declared subject is not evidence of anything (FR-026a).
    let appleUserIdentifier: String
    /// The preimage of the nonce inside `identityToken`. This is what makes the
    /// token unreplayable, so it goes to Kalorias and only to Kalorias.
    let rawNonce: String
}

nonisolated extension AppleAuthorizationCredential: CustomStringConvertible, CustomDebugStringConvertible {
    var description: String { "AppleAuthorizationCredential(redacted)" }
    var debugDescription: String { description }
}

/// Why a native authorization could not be turned into something the backend
/// can verify. Every case is a refusal to send, never a partial attempt.
nonisolated enum AppleAuthorizationError: Error, Equatable, Sendable {
    /// A callback arrived with no attempt outstanding.
    case noAttemptInFlight
    /// The callback's `state` is not this attempt's. Discarded locally; nothing
    /// is sent.
    case stateMismatch
    case missingIdentityToken
    case missingAuthorizationCode
    case missingUserIdentifier
    /// The authorization succeeded but is not an Apple ID credential.
    case unexpectedCredentialType
    /// The user dismissed Apple's sheet. Not an error to the user: no data
    /// changed and the button is simply enabled again.
    case cancelled
    /// Apple itself failed. Recoverable; the pending answers are untouched.
    case failed

    /// The copy shown beneath the Apple button. Cancellation is deliberately
    /// quiet rather than styled as a failure.
    var messageKey: String.LocalizationValue {
        switch self {
        case .cancelled: "access.cancelled"
        case .noAttemptInFlight, .stateMismatch: "access.error.replayed"
        case .missingIdentityToken, .missingAuthorizationCode,
             .missingUserIdentifier, .unexpectedCredentialType:
            "access.error.invalidCredential"
        case .failed: "access.error.generic"
        }
    }

    /// Cancellation is a decision, not a fault, and is not presented as one.
    var isUserCancellation: Bool { self == .cancelled }
}
