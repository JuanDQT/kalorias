//
//  AppleCredentialStateService.swift
//  Kalorias
//
//  Asks Apple whether this installation's authorization still exists
//  (feature 010, FR-034).
//
//  ONLY A DEFINITIVE ANSWER MAY END A SESSION, and this type exists mainly to
//  make that distinction impossible to lose. `ASAuthorizationAppleIDProvider`
//  reports `.notFound` both when the user really did revoke the app in Settings
//  and, in the shape of an error, when the lookup simply could not be performed
//  — offline, mid-flight, a transient system failure. Flattening the second into
//  the first signs a user out on a bad connection, and on the deletion path it
//  is worse than that.
//
//  So a failed *lookup* is its own case, and it changes nothing.
//
//  `.transferred` IS NOT A DELETION. It means the app moved to a different
//  developer account and Apple has issued the user a new subject there. The
//  correct response is to say so and route to support; silently treating it as
//  "unknown user" would strand real accounts, and treating it as revocation
//  would delete their data.
//
//  IT IS CHECKED AT BOOTSTRAP AND ON FOREGROUND, and the revocation notification
//  is observed too, because a user can revoke while the app is running.
//

import AuthenticationServices
import Foundation

/// What Apple says about a stored user identifier.
nonisolated enum AppleCredentialState: Equatable, Sendable {
    case authorized
    /// The user revoked the app. Definitive.
    case revoked
    /// Apple has no such credential. Definitive.
    case notFound
    /// The app changed developer accounts; this account needs migrating, not
    /// deleting.
    case transferred
    /// The lookup itself failed. **Not** evidence of anything.
    case temporarilyUnavailable

    /// Whether this result may invalidate the local session. Only the two
    /// definitive outcomes qualify.
    var invalidatesSession: Bool {
        self == .revoked || self == .notFound
    }
}

protocol AppleCredentialStateChecking: Sendable {
    nonisolated func state(forAppleUserIdentifier identifier: String) async -> AppleCredentialState
}

nonisolated struct AppleCredentialStateService: AppleCredentialStateChecking {

    /// The notification Apple posts when the user revokes the app while it runs.
    static var revocationNotification: Notification.Name {
        ASAuthorizationAppleIDProvider.credentialRevokedNotification
    }

    private let provider: ASAuthorizationAppleIDProvider

    init(provider: ASAuthorizationAppleIDProvider = ASAuthorizationAppleIDProvider()) {
        self.provider = provider
    }

    func state(forAppleUserIdentifier identifier: String) async -> AppleCredentialState {
        guard !identifier.isEmpty else { return .temporarilyUnavailable }

        return await withCheckedContinuation { continuation in
            provider.getCredentialState(forUserID: identifier) { state, error in
                // An error means the question was not answered. It never means
                // "no", however tempting the `.notFound` next to it looks.
                if error != nil {
                    continuation.resume(returning: .temporarilyUnavailable)
                    return
                }
                switch state {
                case .authorized: continuation.resume(returning: .authorized)
                case .revoked: continuation.resume(returning: .revoked)
                case .notFound: continuation.resume(returning: .notFound)
                case .transferred: continuation.resume(returning: .transferred)
                @unknown default:
                    // A state this build has never heard of is not grounds to
                    // destroy anything.
                    continuation.resume(returning: .temporarilyUnavailable)
                }
            }
        }
    }
}
