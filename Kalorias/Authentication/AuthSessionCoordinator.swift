//
//  AuthSessionCoordinator.swift
//  Kalorias
//
//  The single owner of the Kalorias session: who holds it, when it is renewed,
//  and what happens when it cannot be (feature 010, FR-032).
//
//  AN `actor`, BECAUSE THE BUG IT PREVENTS IS A RACE. Two authenticated requests
//  starting together with a token about to expire will both see it expired and
//  both refresh. The second refresh presents a token the first has already
//  rotated away, the server correctly reads that as refresh-token reuse, and it
//  invalidates the whole family — logging out a user who did nothing wrong. Only
//  serialised ownership fixes this; a lock around a shared struct does not,
//  because the await inside the refresh is where the interleaving happens.
//
//  SINGLE FLIGHT: concurrent callers join the *same* refresh rather than
//  queueing their own behind it. That is the difference between one network call
//  and N sequential ones, and between one rotation and N.
//
//  IT REFRESHES SLIGHTLY EARLY. A token that expires in flight costs a
//  guaranteed round trip and a retry; renewing inside `AuthSession.expiryMargin`
//  costs nothing.
//
//  TRANSIENT FAILURE IS NOT LOGOUT. A `500` or a dropped connection leaves the
//  session exactly where it was, to be retried. Only a definitive rejection —
//  the refresh credential is invalid, or was reused — ends it. Conflating the
//  two means a server hiccup signs people out and, for a user mid-finalization,
//  sends them back through Apple for no reason.
//
//  KEYCHAIN WRITES HAPPEN BEFORE WAITERS ARE RELEASED. A caller must never
//  receive a token that a later crash would leave unrecorded.
//

import Foundation

/// What a consumer of the session can ask for, so the authenticated client is
/// testable without a Keychain or a network.
protocol AuthSessionProviding: Sendable, AnyObject {
    /// A usable access token, refreshing first if it is near expiry.
    func validAccessToken() async throws -> String
    /// Force one refresh, joining any that is already running, and return the
    /// new token. Used after a `401`.
    func refreshedAccessToken(replacing spentToken: String) async throws -> String
    /// The current session, without refreshing.
    func currentSession() async -> AuthSession?
    /// Commit a freshly authenticated session and its known-account marker.
    func commit(_ session: AuthSession) async throws
    /// Record a new server onboarding status against the live session.
    func commitOnboardingStatus(_ status: OnboardingServerStatus) async throws
    /// Drop the active session, keeping the known-account marker.
    func endSession() async
}

actor AuthSessionCoordinator: AuthSessionProviding {

    private let credentials: any CredentialStoring
    private let service: any AuthenticationServicing
    private let now: @Sendable () -> Date

    /// Cached so ordinary requests do not hit the Keychain every time. The
    /// Keychain remains the source of truth: every mutation writes there first.
    private var session: AuthSession?
    private var hasLoadedSession = false

    /// The refresh currently in flight, if any. This one value is what makes the
    /// coordinator single-flight.
    private var refreshTask: Task<AuthSession, any Error>?

    init(
        credentials: any CredentialStoring = KeychainCredentialStore(),
        service: any AuthenticationServicing = RemoteAuthService(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.credentials = credentials
        self.service = service
        self.now = now
    }

    // MARK: Reading

    func currentSession() async -> AuthSession? {
        loadIfNeeded()
        return session
    }

    private func loadIfNeeded() {
        guard !hasLoadedSession else { return }
        hasLoadedSession = true
        session = try? credentials.loadSession()
    }

    // MARK: Tokens

    func validAccessToken() async throws -> String {
        loadIfNeeded()
        guard let current = session, current.isValid else { throw AuthError.refreshRejected }

        if current.isAccessTokenUsable(at: now()) {
            return current.accessToken
        }
        return try await refresh(from: current).accessToken
    }

    /// After a `401`. `spentToken` is what the failed request presented: if the
    /// stored session has already moved past it, another caller's refresh
    /// succeeded in the meantime and this one simply uses the result.
    func refreshedAccessToken(replacing spentToken: String) async throws -> String {
        loadIfNeeded()
        guard let current = session, current.isValid else { throw AuthError.refreshRejected }

        if current.accessToken != spentToken {
            return current.accessToken
        }
        return try await refresh(from: current).accessToken
    }

    // MARK: Refresh

    /// Join the in-flight refresh, or start the only one.
    private func refresh(from current: AuthSession) async throws -> AuthSession {
        if let refreshTask {
            return try await refreshTask.value
        }

        guard current.isRefreshTokenUsable(at: now()) else {
            await endSession()
            throw AuthError.refreshRejected
        }

        let task = Task<AuthSession, any Error> { [service, credentials] in
            let rotated = try await service.refresh(refreshToken: current.refreshToken)
            let updated = current.rotating(
                accessToken: rotated.accessToken,
                accessTokenExpiresAt: rotated.accessTokenExpiresAt,
                refreshToken: rotated.refreshToken,
                refreshTokenExpiresAt: rotated.refreshTokenExpiresAt
            )
            // Durable before any waiter is released.
            try credentials.saveSession(updated)
            return updated
        }
        refreshTask = task

        defer { refreshTask = nil }

        do {
            let updated = try await task.value
            session = updated
            return updated
        } catch {
            let authError = AuthError.from(error)
            // Only a definitive rejection ends the session. A 500 or a dropped
            // connection leaves it alone to be retried.
            if authError.isDefinitiveRefreshFailure {
                await endSession()
            }
            throw authError
        }
    }

    // MARK: Committing

    func commit(_ session: AuthSession) async throws {
        guard session.isValid else { throw AuthError.invalidResponse }
        // The order is fixed by the data model: session, then marker, then the
        // caller may publish a phase. A failure between them is reconciled at
        // the next bootstrap from the session that did land.
        try credentials.saveSession(session)
        try credentials.saveKnownAccount(KnownAccount(session: session))
        self.session = session
        hasLoadedSession = true
    }

    func commitOnboardingStatus(_ status: OnboardingServerStatus) async throws {
        loadIfNeeded()
        guard let current = session else { throw AuthError.refreshRejected }
        let updated = current.with(onboardingStatus: status)
        try credentials.saveSession(updated)
        try credentials.saveKnownAccount(KnownAccount(session: updated))
        session = updated
    }

    // MARK: Ending

    /// Drop the credential, keep the marker. A user whose token expired is still
    /// a user with an account, and must land on Apple rather than on question
    /// one (FR-027).
    func endSession() async {
        try? credentials.deleteSession()
        session = nil
        hasLoadedSession = true
        refreshTask = nil
    }

    /// Best-effort server-side invalidation, then the local drop. The local part
    /// happens whatever the network did — a device that cannot reach the server
    /// must still be able to stop using a credential.
    func logout() async {
        loadIfNeeded()
        if let current = session {
            try? await service.logout(
                accessToken: current.accessToken,
                refreshToken: current.refreshToken
            )
        }
        await endSession()
    }
}
