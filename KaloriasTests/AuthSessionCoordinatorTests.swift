//
//  AuthSessionCoordinatorTests.swift
//  KaloriasTests
//
//  The race the coordinator exists to lose.
//
//  THE SINGLE-FLIGHT TEST IS THE ONE THAT MATTERS. Two authenticated requests
//  starting together with a token about to expire will both see it expired. If
//  they both refresh, the second presents a credential the first has already
//  rotated away, the server correctly reads that as refresh-token reuse, and it
//  invalidates the family — signing out a user who did nothing wrong. So the
//  assertion is on the *number of refresh calls*, not merely on the token that
//  comes back.
//
//  AND THE OTHER HALF: a `500` must not sign anybody out. Only a definitive
//  rejection ends a session, and conflating the two turns a server hiccup into a
//  trip back through Apple.
//

import XCTest
@testable import Kalorias

nonisolated final class AuthSessionCoordinatorTests: XCTestCase {

    private var credentials: InMemoryCredentialStore!
    private var service: StubAuthService!

    /// A clock the test moves, so expiry is a decision rather than a wait.
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var _now: Date
        init(_ now: Date) { _now = now }
        var now: Date {
            get { lock.withLock { _now } }
            set { lock.withLock { _now = newValue } }
        }
    }

    private var clock: Clock!

    override func setUp() {
        super.setUp()
        credentials = InMemoryCredentialStore()
        service = StubAuthService()
        clock = Clock(Date(timeIntervalSince1970: 0))
    }

    @MainActor
    private func makeCoordinator() -> AuthSessionCoordinator {
        let clock = clock!
        return AuthSessionCoordinator(
            credentials: credentials,
            service: service,
            now: { clock.now }
        )
    }

    // MARK: Reading

    @MainActor
    func testAValidTokenIsReturnedWithoutRefreshing() async throws {
        try credentials.saveSession(AuthFixtures.session(accessExpiry: Date(timeIntervalSince1970: 10_000)))
        let coordinator = makeCoordinator()

        let token = try await coordinator.validAccessToken()

        XCTAssertEqual(token, "access-1")
        XCTAssertTrue(service.refreshCalls.isEmpty)
    }

    @MainActor
    func testNoSessionIsARejection() async {
        let coordinator = makeCoordinator()

        do {
            _ = try await coordinator.validAccessToken()
            XCTFail("A token was produced with no session.")
        } catch {
            XCTAssertEqual(error as? AuthError, .refreshRejected)
        }
    }

    // MARK: Proactive refresh

    /// A token that expires in flight costs a guaranteed round trip; renewing
    /// inside the margin costs nothing.
    @MainActor
    func testATokenInsideTheExpiryMarginIsRenewedBeforeUse() async throws {
        try credentials.saveSession(AuthFixtures.session(accessExpiry: Date(timeIntervalSince1970: 100)))
        service.refreshResult = .success(AuthFixtures.credentials())
        clock.now = Date(timeIntervalSince1970: 60)   // 40s left, margin is 60
        let coordinator = makeCoordinator()

        let token = try await coordinator.validAccessToken()

        XCTAssertEqual(token, "access-2")
        XCTAssertEqual(service.refreshCalls, ["refresh-1"])
    }

    @MainActor
    func testRotationIsPersistedWholeBeforeTheTokenIsHandedOut() async throws {
        try credentials.saveSession(AuthFixtures.session(accessExpiry: Date(timeIntervalSince1970: 10)))
        service.refreshResult = .success(AuthFixtures.credentials())
        let coordinator = makeCoordinator()

        _ = try await coordinator.validAccessToken()

        let stored = try XCTUnwrap(credentials.storedSession)
        XCTAssertEqual(stored.accessToken, "access-2")
        XCTAssertEqual(stored.refreshToken, "refresh-2", "both halves rotate together")
        XCTAssertEqual(stored.userId, "user-1", "identity survives rotation")
        XCTAssertEqual(stored.onboardingStatus, .required)
    }

    @MainActor
    func testRefreshRateLimitSuppressesNetworkCallsUntilRetryAfterExpires() async throws {
        try credentials.saveSession(
            AuthFixtures.session(accessExpiry: Date(timeIntervalSince1970: 10))
        )
        service.refreshResult = .failure(AuthError.rateLimited(retryAfter: 30))
        let coordinator = makeCoordinator()

        do {
            _ = try await coordinator.validAccessToken()
            XCTFail("The rate-limited refresh succeeded.")
        } catch {
            XCTAssertEqual(error as? AuthError, .rateLimited(retryAfter: 30))
        }

        do {
            _ = try await coordinator.validAccessToken()
            XCTFail("The cooldown allowed an early refresh.")
        } catch {
            XCTAssertEqual(error as? AuthError, .rateLimited(retryAfter: 30))
        }
        XCTAssertEqual(service.refreshCalls, ["refresh-1"], "the second call is blocked locally")

        clock.now = Date(timeIntervalSince1970: 31)
        service.refreshResult = .success(AuthFixtures.credentials())
        let token = try await coordinator.validAccessToken()

        XCTAssertEqual(token, "access-2")
        XCTAssertEqual(service.refreshCalls, ["refresh-1", "refresh-1"])
    }

    @MainActor
    func testLogoutRefreshesAndReplaysOnceWhenBearerIsRejected() async throws {
        let live = AuthFixtures.session(
            accessExpiry: Date(timeIntervalSince1970: 10_000),
            refreshExpiry: Date(timeIntervalSince1970: 20_000)
        )
        try credentials.saveSession(live)
        service.refreshResult = .success(AuthFixtures.credentials())
        service.logoutResults = [
            .failure(AuthError.refreshRejected),
            .success(()),
        ]
        let coordinator = makeCoordinator()

        try await coordinator.logout()

        XCTAssertEqual(service.refreshCalls, [live.refreshToken])
        XCTAssertEqual(service.logoutCalls, 2)
        XCTAssertNil(credentials.storedSession)
    }

    // MARK: Single flight

    /// Ten concurrent callers, one refresh. This is the whole reason the
    /// coordinator is an actor.
    @MainActor
    func testConcurrentCallersShareExactlyOneRefresh() async throws {
        try credentials.saveSession(AuthFixtures.session(accessExpiry: Date(timeIntervalSince1970: 10)))
        service.refreshResult = .success(AuthFixtures.credentials())
        service.refreshDelay = .milliseconds(50)
        let coordinator = makeCoordinator()

        let tokens = await withTaskGroup(of: String?.self) { group in
            for _ in 0..<10 {
                group.addTask { try? await coordinator.validAccessToken() }
            }
            var collected: [String?] = []
            for await token in group { collected.append(token) }
            return collected
        }

        XCTAssertEqual(service.refreshCalls.count, 1, "one rotation, not ten")
        XCTAssertEqual(Set(tokens.compactMap { $0 }), ["access-2"])
    }

    /// After a `401`, a caller whose token has already been rotated by somebody
    /// else uses that result instead of refreshing again.
    @MainActor
    func testARequestWhoseTokenWasAlreadyRotatedDoesNotRefreshAgain() async throws {
        try credentials.saveSession(AuthFixtures.session(accessExpiry: Date(timeIntervalSince1970: 10)))
        service.refreshResult = .success(AuthFixtures.credentials())
        let coordinator = makeCoordinator()

        _ = try await coordinator.refreshedAccessToken(replacing: "access-1")
        let second = try await coordinator.refreshedAccessToken(replacing: "access-1")

        XCTAssertEqual(second, "access-2")
        XCTAssertEqual(service.refreshCalls.count, 1)
    }

    // MARK: Transient versus definitive

    /// A `500` leaves the session exactly where it was. Signing somebody out on
    /// a server hiccup sends them back through Apple for nothing.
    @MainActor
    func testATransientRefreshFailurePreservesTheSession() async throws {
        try credentials.saveSession(AuthFixtures.session(accessExpiry: Date(timeIntervalSince1970: 10)))
        service.refreshResult = .failure(AuthError.serviceUnavailable)
        let coordinator = makeCoordinator()

        do {
            _ = try await coordinator.validAccessToken()
            XCTFail("A failed refresh produced a token.")
        } catch {
            XCTAssertEqual(error as? AuthError, .serviceUnavailable)
        }

        XCTAssertNotNil(credentials.storedSession, "the session survives an outage")
    }

    @MainActor
    func testADefinitiveRejectionEndsTheSession() async throws {
        try credentials.saveSession(AuthFixtures.session(accessExpiry: Date(timeIntervalSince1970: 10)))
        try credentials.saveKnownAccount(KnownAccount(session: AuthFixtures.session()))
        service.refreshResult = .failure(AuthError.refreshRejected)
        let coordinator = makeCoordinator()

        _ = try? await coordinator.validAccessToken()

        XCTAssertNil(credentials.storedSession)
        XCTAssertNotNil(credentials.storedKnownAccount,
                        "the account marker survives, so the user lands on Apple not question one")
    }

    /// Reuse invalidates the family. The marker still stays.
    @MainActor
    func testReuseDetectionEndsTheSessionAndKeepsTheMarker() async throws {
        try credentials.saveSession(AuthFixtures.session(accessExpiry: Date(timeIntervalSince1970: 10)))
        try credentials.saveKnownAccount(KnownAccount(session: AuthFixtures.session()))
        service.refreshResult = .failure(AuthError.refreshReused)
        let coordinator = makeCoordinator()

        _ = try? await coordinator.validAccessToken()

        XCTAssertNil(credentials.storedSession)
        XCTAssertNotNil(credentials.storedKnownAccount)
    }

    /// An expired refresh credential cannot be presented at all — there is
    /// nothing to try.
    @MainActor
    func testAnExpiredRefreshTokenEndsTheSessionWithoutARequest() async throws {
        try credentials.saveSession(
            AuthFixtures.session(
                accessExpiry: Date(timeIntervalSince1970: 10),
                refreshExpiry: Date(timeIntervalSince1970: 20)
            )
        )
        clock.now = Date(timeIntervalSince1970: 100)
        let coordinator = makeCoordinator()

        _ = try? await coordinator.validAccessToken()

        XCTAssertTrue(service.refreshCalls.isEmpty)
        XCTAssertNil(credentials.storedSession)
    }

    // MARK: Committing

    /// Session, then marker — the order the data model fixes, because a lost
    /// second write is reconcilable and a lost first one is not.
    @MainActor
    func testCommitWritesBothRecords() async throws {
        let coordinator = makeCoordinator()
        let session = AuthFixtures.session()

        try await coordinator.commit(session)

        XCTAssertEqual(credentials.storedSession, session)
        XCTAssertEqual(credentials.storedKnownAccount?.userId, "user-1")
        XCTAssertEqual(credentials.storedKnownAccount?.onboardingStatus, .required)
    }

    @MainActor
    func testAnInvalidSessionIsNeverCommitted() async {
        let coordinator = makeCoordinator()

        do {
            try await coordinator.commit(AuthFixtures.session(userId: ""))
            XCTFail("An invalid session was committed.")
        } catch {
            XCTAssertEqual(error as? AuthError, .invalidResponse)
        }
        XCTAssertNil(credentials.storedSession)
    }

    @MainActor
    func testCommittingCompleteStatusUpdatesBothRecords() async throws {
        let coordinator = makeCoordinator()
        try await coordinator.commit(AuthFixtures.session())

        try await coordinator.commitOnboardingStatus(.complete)

        XCTAssertEqual(credentials.storedSession?.onboardingStatus, .complete)
        XCTAssertEqual(credentials.storedKnownAccount?.onboardingStatus, .complete)
        XCTAssertEqual(credentials.storedSession?.accessToken, "access-1",
                       "recording a status does not disturb the credentials")
    }

    // MARK: Ending

    @MainActor
    func testEndingASessionKeepsTheAccountMarker() async throws {
        let coordinator = makeCoordinator()
        try await coordinator.commit(AuthFixtures.session())

        await coordinator.endSession()

        XCTAssertNil(credentials.storedSession)
        XCTAssertNotNil(credentials.storedKnownAccount)
        let current = await coordinator.currentSession()
        XCTAssertNil(current)
    }

    @MainActor
    func testLogoutClearsLocallyOnlyAfterServerConfirmation() async throws {
        let coordinator = makeCoordinator()
        try await coordinator.commit(AuthFixtures.session())

        try await coordinator.logout()

        XCTAssertEqual(service.logoutCalls, 1)
        XCTAssertNil(credentials.storedSession)
    }

    @MainActor
    func testLogoutFailurePreservesTheCompleteSession() async throws {
        let coordinator = makeCoordinator()
        try await coordinator.commit(AuthFixtures.session())
        service.logoutResult = .failure(AuthError.serviceUnavailable)

        do {
            try await coordinator.logout()
            XCTFail("An unconfirmed logout succeeded.")
        } catch {
            XCTAssertEqual(error as? AuthError, .serviceUnavailable)
        }

        XCTAssertEqual(service.logoutCalls, 1)
        XCTAssertEqual(credentials.storedSession, AuthFixtures.session())
    }
}
