//
//  AuthSession.swift
//  Kalorias
//
//  The two Keychain records that say who this installation is (feature 010).
//
//  `AuthSession` IS ONE RECORD, REPLACED WHOLE. Tokens and their expiries are
//  written as a unit because a refresh rotates all four together; storing them
//  as separate items invites the state where a new access token sits next to the
//  old refresh token, and no reader can tell.
//
//  `KnownAccount` HOLDS NO CREDENTIAL, and that is its entire job. When a
//  session expires or is revoked, the tokens go and this stays — so a user who
//  already has a plan is sent back to Sign in with Apple rather than through the
//  whole questionnaire again (FR-027). It is removed only by a confirmed account
//  deletion.
//
//  VALIDATION AT THE BOUNDARY, NOT AT USE. An empty user id or a refresh token
//  that expires before its access token means the response is wrong, and the
//  moment to refuse it is before it reaches the Keychain — after that, every
//  later reader has to re-litigate whether it can be trusted.
//
//  `nonisolated`: these are `Sendable` value types crossing into an actor and a
//  URL session, and the project defaults to MainActor isolation.
//

import Foundation

// MARK: - Session

nonisolated struct AuthSession: Codable, Equatable, Sendable {

    /// Migration version for the encoded Keychain payload.
    let schemaVersion: Int
    /// The authoritative, opaque Kalorias user id. This — never the Apple
    /// subject — is what local meals are scoped by and what the server knows.
    let userId: String
    /// Apple's stable identifier for this user, kept **only** so
    /// `ASAuthorizationAppleIDProvider` can be asked whether the credential is
    /// still valid (FR-026a). It is not a server-facing id and never logged.
    let appleUserIdentifier: String
    let accessToken: String
    let accessTokenExpiresAt: Date
    let refreshToken: String
    let refreshTokenExpiresAt: Date
    /// The last status the backend committed for this account.
    let onboardingStatus: OnboardingServerStatus

    static let currentSchemaVersion = 1

    init(
        schemaVersion: Int = AuthSession.currentSchemaVersion,
        userId: String,
        appleUserIdentifier: String,
        accessToken: String,
        accessTokenExpiresAt: Date,
        refreshToken: String,
        refreshTokenExpiresAt: Date,
        onboardingStatus: OnboardingServerStatus
    ) {
        self.schemaVersion = schemaVersion
        self.userId = userId
        self.appleUserIdentifier = appleUserIdentifier
        self.accessToken = accessToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.refreshToken = refreshToken
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
        self.onboardingStatus = onboardingStatus
    }

    /// Whether every field is usable. Checked before the record is persisted, so
    /// a malformed server response is refused once instead of everywhere.
    var isValid: Bool {
        guard !userId.isEmpty,
              !appleUserIdentifier.isEmpty,
              !accessToken.isEmpty,
              !refreshToken.isEmpty
        else { return false }
        // A refresh credential that dies before the access token it renews is a
        // contradiction; the response describes a session that cannot work.
        return refreshTokenExpiresAt >= accessTokenExpiresAt
    }

    /// How long before the stated expiry the access token is treated as spent.
    ///
    /// Sending a token that expires in-flight costs a guaranteed round trip;
    /// refreshing a little early costs nothing.
    static let expiryMargin: TimeInterval = 60

    func isAccessTokenUsable(at now: Date) -> Bool {
        now.addingTimeInterval(Self.expiryMargin) < accessTokenExpiresAt
    }

    func isRefreshTokenUsable(at now: Date) -> Bool {
        now < refreshTokenExpiresAt
    }

    /// The same session with rotated credentials, as a refresh returns them.
    func rotating(
        accessToken: String,
        accessTokenExpiresAt: Date,
        refreshToken: String,
        refreshTokenExpiresAt: Date
    ) -> AuthSession {
        AuthSession(
            userId: userId,
            appleUserIdentifier: appleUserIdentifier,
            accessToken: accessToken,
            accessTokenExpiresAt: accessTokenExpiresAt,
            refreshToken: refreshToken,
            refreshTokenExpiresAt: refreshTokenExpiresAt,
            onboardingStatus: onboardingStatus
        )
    }

    /// The same session carrying a newly committed server status.
    func with(onboardingStatus newStatus: OnboardingServerStatus) -> AuthSession {
        AuthSession(
            userId: userId,
            appleUserIdentifier: appleUserIdentifier,
            accessToken: accessToken,
            accessTokenExpiresAt: accessTokenExpiresAt,
            refreshToken: refreshToken,
            refreshTokenExpiresAt: refreshTokenExpiresAt,
            onboardingStatus: newStatus
        )
    }
}

// MARK: - Known account

/// What survives an expired or revoked session: that this installation belongs
/// to a real account, and how far that account got.
nonisolated struct KnownAccount: Codable, Equatable, Sendable {

    let schemaVersion: Int
    let userId: String
    /// Populated after Apple authorization. Optional only so a record written by
    /// an earlier build can still be read.
    let appleUserIdentifier: String?
    let onboardingStatus: OnboardingServerStatus

    static let currentSchemaVersion = 1

    init(
        schemaVersion: Int = KnownAccount.currentSchemaVersion,
        userId: String,
        appleUserIdentifier: String?,
        onboardingStatus: OnboardingServerStatus
    ) {
        self.schemaVersion = schemaVersion
        self.userId = userId
        self.appleUserIdentifier = appleUserIdentifier
        self.onboardingStatus = onboardingStatus
    }

    /// The marker implied by a live session. Used both when committing a fresh
    /// authentication and to rebuild the record if its paired write was lost.
    init(session: AuthSession) {
        self.init(
            userId: session.userId,
            appleUserIdentifier: session.appleUserIdentifier,
            onboardingStatus: session.onboardingStatus
        )
    }

    var isValid: Bool { !userId.isEmpty }
}
