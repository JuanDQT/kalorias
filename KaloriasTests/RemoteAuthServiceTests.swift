//
//  RemoteAuthServiceTests.swift
//  KaloriasTests
//
//  The exact bytes of every authentication route, against a `URLProtocol` stub.
//
//  THE BODY ASSERTION IS THE SPEC'S OWN ACCEPTANCE TEST. FR-014 says the
//  Apple-auth request must not contain onboarding answers, a name, an email, or
//  a client-declared Apple subject, and "the code doesn't do that" is a claim
//  about a call site. Decoding what actually went on the wire and asserting the
//  key set is the claim about the request.
//

import XCTest
@testable import Kalorias

nonisolated final class RemoteAuthServiceTests: XCTestCase {

    private var service: RemoteAuthService!

    override func setUp() {
        super.setUp()
        service = RemoteAuthService(
            baseURL: AuthFixtures.baseURL,
            session: AuthStubURLProtocol.makeSession()
        )
    }

    override func tearDown() {
        AuthStubURLProtocol.reset()
        service = nil
        super.tearDown()
    }

    private func json(_ body: String, status: Int = 200, headers: [String: String] = [:]) {
        AuthStubURLProtocol.stub { request in
            (AuthFixtures.response(request.url!, status, headers: headers), Data(body.utf8))
        }
    }

    private static let successBody = """
    {
      "data": {
        "user": { "id": "9d92525d" },
        "session": {
          "tokenType": "Bearer",
          "accessToken": "access-1",
          "accessTokenExpiresAt": "2026-09-08T17:30:00Z",
          "refreshToken": "refresh-1",
          "refreshTokenExpiresAt": "2026-12-07T17:15:00Z"
        },
        "onboarding": { "status": "required" }
      }
    }
    """

    // MARK: /auth/apple

    func testAppleAuthenticationPostsToTheContractPath() async throws {
        json(Self.successBody, status: 201)

        _ = try await service.authenticate(with: AuthFixtures.appleCredential())

        let request = try XCTUnwrap(AuthStubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/auth/apple")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "X-Request-Id"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"),
                     "registration has no bearer to present yet")
    }

    /// FR-014, asserted on the wire: exactly three keys, and none of them is an
    /// answer, a name, an email or a client-asserted Apple subject.
    func testAppleAuthBodyCarriesExactlyTheThreeContractFields() async throws {
        json(Self.successBody)

        _ = try await service.authenticate(with: AuthFixtures.appleCredential())

        let body = try XCTUnwrap(AuthStubURLProtocol.bodies.first)
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )

        XCTAssertEqual(Set(object.keys), ["identityToken", "authorizationCode", "nonce"])
        XCTAssertEqual(object["nonce"] as? String, "raw-nonce",
                       "the backend gets the preimage, not the hash")

        for forbidden in ["answers", "onboarding", "email", "name", "user", "appleUserIdentifier",
                          "consent", "sessionId"] {
            XCTAssertNil(object[forbidden], "\(forbidden) must not appear in an auth request")
        }
    }

    func testBothTwoHundredAndTwoOhOneAreSuccess() async throws {
        for status in [200, 201] {
            AuthStubURLProtocol.reset()
            json(Self.successBody, status: status)

            let response = try await service.authenticate(with: AuthFixtures.appleCredential())

            XCTAssertEqual(response.userId, "9d92525d")
            XCTAssertEqual(response.onboardingStatus, .required)
        }
    }

    // MARK: Response validation

    /// A scheme this build cannot present is not a session it can use.
    func testANonBearerTokenTypeIsRejected() async {
        json(Self.successBody.replacingOccurrences(of: "\"Bearer\"", with: "\"MAC\""))

        await assertThrows(.invalidResponse) {
            _ = try await self.service.authenticate(with: AuthFixtures.appleCredential())
        }
    }

    func testAnEmptyUserIdIsRejected() async {
        json(Self.successBody.replacingOccurrences(of: "\"9d92525d\"", with: "\"\""))

        await assertThrows(.invalidResponse) {
            _ = try await self.service.authenticate(with: AuthFixtures.appleCredential())
        }
    }

    func testAnEmptyAccessTokenIsRejected() async {
        json(Self.successBody.replacingOccurrences(of: "\"access-1\"", with: "\"\""))

        await assertThrows(.invalidResponse) {
            _ = try await self.service.authenticate(with: AuthFixtures.appleCredential())
        }
    }

    /// An unknown status must fail the whole response rather than default to
    /// anything — least of all to `complete`, which opens the app.
    func testAnUnknownOnboardingStatusIsRejected() async {
        json(Self.successBody.replacingOccurrences(of: "\"required\"", with: "\"pending\""))

        await assertThrows(.invalidResponse) {
            _ = try await self.service.authenticate(with: AuthFixtures.appleCredential())
        }
    }

    func testAnUnparseableDateIsRejected() async {
        json(Self.successBody.replacingOccurrences(
            of: "\"2026-09-08T17:30:00Z\"", with: "\"whenever\""
        ))

        await assertThrows(.invalidResponse) {
            _ = try await self.service.authenticate(with: AuthFixtures.appleCredential())
        }
    }

    /// A refresh credential that dies before the access token it renews.
    func testInconsistentExpiryOrderingIsRejected() async {
        json(Self.successBody.replacingOccurrences(
            of: "\"2026-12-07T17:15:00Z\"", with: "\"2026-01-01T00:00:00Z\""
        ))

        await assertThrows(.invalidResponse) {
            _ = try await self.service.authenticate(with: AuthFixtures.appleCredential())
        }
    }

    // MARK: Stable error mapping

    func testStableCodesMapToTheirJourneyBranches() async {
        let cases: [(Int, String, AuthError)] = [
            (400, "invalid_request", .invalidRequest),
            (401, "invalid_apple_credential", .invalidAppleCredential),
            (409, "auth_attempt_replayed", .attemptReplayed),
            (503, "apple_temporarily_unavailable", .serviceUnavailable),
            (500, "auth_service_error", .serviceUnavailable),
        ]

        for (status, code, expected) in cases {
            AuthStubURLProtocol.reset()
            json(#"{"error":{"code":"\#(code)","message":"nope"}}"#, status: status)

            await assertThrows(expected) {
                _ = try await self.service.authenticate(with: AuthFixtures.appleCredential())
            }
        }
    }

    /// The server's own backoff is honoured rather than guessed at.
    func testRateLimitingCarriesRetryAfter() async {
        json(
            #"{"error":{"code":"auth_rate_limited","message":"slow down"}}"#,
            status: 429,
            headers: ["Retry-After": "42"]
        )

        await assertThrows(.rateLimited(retryAfter: 42)) {
            _ = try await self.service.authenticate(with: AuthFixtures.appleCredential())
        }
    }

    func testHTTPStatusWithoutItsStableCodeDoesNotSelectARecoveryPath() async {
        json(#"{"error":{"code":"unknown","message":"nope"}}"#, status: 403)

        await assertThrows(.serviceUnavailable) {
            _ = try await self.service.authenticate(with: AuthFixtures.appleCredential())
        }
    }

    // MARK: /auth/refresh

    private static let refreshBody = """
    {
      "data": {
        "session": {
          "tokenType": "Bearer",
          "accessToken": "access-2",
          "accessTokenExpiresAt": "2026-09-08T17:45:00Z",
          "refreshToken": "refresh-2",
          "refreshTokenExpiresAt": "2026-12-07T17:30:00Z"
        }
      }
    }
    """

    /// The refresh route's authority is the credential in the body. Presenting
    /// the expired bearer alongside it invites a server that accepts either.
    func testRefreshSendsOnlyTheRefreshTokenAndNoBearer() async throws {
        json(Self.refreshBody)

        _ = try await service.refresh(refreshToken: "refresh-1")

        let request = try XCTUnwrap(AuthStubURLProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/api/v1/auth/refresh")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: AuthStubURLProtocol.bodies[0]) as? [String: Any]
        )
        XCTAssertEqual(Set(object.keys), ["refreshToken"])
        XCTAssertEqual(object["refreshToken"] as? String, "refresh-1")
    }

    /// Reuse detection is what makes a stolen refresh token detectable, and it
    /// only works if the server actually rotates. A response that hands back the
    /// same credential is refused.
    func testAnUnrotatedRefreshTokenIsRejected() async {
        json(Self.refreshBody.replacingOccurrences(of: "\"refresh-2\"", with: "\"refresh-1\""))

        await assertThrows(.invalidResponse) {
            _ = try await self.service.refresh(refreshToken: "refresh-1")
        }
    }

    func testRefreshErrorsDistinguishRejectionFromReuseAndOutage() async {
        let cases: [(Int, String, AuthError)] = [
            (401, "invalid_refresh_token", .refreshRejected),
            (409, "refresh_token_reused", .refreshReused),
            (500, "auth_service_error", .serviceUnavailable),
        ]

        for (status, code, expected) in cases {
            AuthStubURLProtocol.reset()
            json(#"{"error":{"code":"\#(code)","message":"nope"}}"#, status: status)

            await assertThrows(expected) {
                _ = try await self.service.refresh(refreshToken: "refresh-1")
            }
        }
    }

    /// Only a definitive rejection may end a session. A `500` must not sign
    /// somebody out.
    func testOnlyDefinitiveRefreshFailuresEndASession() {
        XCTAssertTrue(AuthError.refreshRejected.isDefinitiveRefreshFailure)
        XCTAssertTrue(AuthError.refreshReused.isDefinitiveRefreshFailure)
        XCTAssertFalse(AuthError.serviceUnavailable.isDefinitiveRefreshFailure)
        XCTAssertFalse(AuthError.noConnection.isDefinitiveRefreshFailure)
        XCTAssertFalse(AuthError.timeout.isDefinitiveRefreshFailure)
        XCTAssertFalse(AuthError.rateLimited(retryAfter: nil).isDefinitiveRefreshFailure)
    }

    // MARK: /auth/logout

    func testLogoutPresentsTheBearerAndTheRefreshToken() async throws {
        AuthStubURLProtocol.stub { request in
            (AuthFixtures.response(request.url!, 204), Data())
        }

        try await service.logout(accessToken: "access-1", refreshToken: "refresh-1")

        let request = try XCTUnwrap(AuthStubURLProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/api/v1/auth/logout")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
    }

    // MARK: DELETE /account

    func testDeletionPresentsTheExactBearerAndStableOperationKey() async throws {
        AuthStubURLProtocol.stub { request in
            (AuthFixtures.response(request.url!, 204), Data())
        }
        let operationId = UUID()

        try await service.deleteAccount(accessToken: "exact-bearer", operationId: operationId)

        let request = try XCTUnwrap(AuthStubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/api/v1/account")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer exact-bearer")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), operationId.uuidString)
    }

    /// `202` means the server is still working, and this build has no contract
    /// for polling that — so it is a failure, not a success.
    func testTwoOhTwoIsNotTreatedAsADeletion() async {
        AuthStubURLProtocol.stub { request in
            (AuthFixtures.response(request.url!, 202), Data())
        }

        await assertThrows(.serviceUnavailable) {
            try await self.service.deleteAccount(accessToken: "t", operationId: UUID())
        }
    }

    func testDeletionErrorsMapToTheirRecoveryPaths() async {
        let cases: [(Int, String, AuthError)] = [
            (403, "reauthentication_required", .reauthenticationRequired),
            (409, "apple_revocation_pending", .revocationPending),
            (503, "apple_revocation_pending", .revocationPending),
            (500, "account_deletion_error", .serviceUnavailable),
            (429, "account_action_rate_limited", .rateLimited(retryAfter: 60)),
        ]

        for (status, code, expected) in cases {
            AuthStubURLProtocol.reset()
            json(#"{"error":{"code":"\#(code)","message":"nope"}}"#, status: status)

            await assertThrows(expected) {
                try await self.service.deleteAccount(accessToken: "t", operationId: UUID())
            }
        }
    }

    // MARK: Configuration

    /// A build with no address fails every call rather than inventing one.
    func testAnUnconfiguredBuildRefusesEveryRoute() async {
        let unconfigured = RemoteAuthService(
            baseURL: nil,
            session: AuthStubURLProtocol.makeSession()
        )

        do {
            _ = try await unconfigured.authenticate(with: AuthFixtures.appleCredential())
            XCTFail("An unconfigured build produced a session.")
        } catch {
            XCTAssertEqual(error as? AuthError, .notConfigured)
        }
    }

    /// A response carrying tokens must never reach a URL cache.
    func testTheAuthSessionKeepsNoCacheAndNoCookies() {
        let configuration = RemoteAuthService.makeConfiguration()

        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
    }

    // MARK: Helper

    private func assertThrows(
        _ expected: AuthError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("Expected \(expected).", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? AuthError, expected, file: file, line: line)
        }
    }
}
