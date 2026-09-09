//
//  AuthenticatedHTTPClientTests.swift
//  KaloriasTests
//
//  The one-refresh/one-replay boundary shared by every authenticated feature.
//

import XCTest
@testable import Kalorias

private nonisolated final class ScriptedSessionProvider: AuthSessionProviding, @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) var validResult: Result<String, AuthError> = .success("access-1")
    nonisolated(unsafe) var refreshResult: Result<String, AuthError> = .success("access-2")
    private var _validCalls = 0
    private var _refreshCalls: [String] = []
    private var _endSessionCalls = 0

    var validCalls: Int { lock.withLock { _validCalls } }
    var refreshCalls: [String] { lock.withLock { _refreshCalls } }
    var endSessionCalls: Int { lock.withLock { _endSessionCalls } }

    func validAccessToken() async throws -> String {
        lock.withLock { _validCalls += 1 }
        return try validResult.get()
    }

    func refreshedAccessToken(replacing spentToken: String) async throws -> String {
        lock.withLock { _refreshCalls.append(spentToken) }
        return try refreshResult.get()
    }

    func currentSession() async -> AuthSession? { nil }
    func commit(_ session: AuthSession) async throws {}
    func commitOnboardingStatus(_ status: OnboardingServerStatus) async throws {}

    func endSession() async {
        lock.withLock { _endSessionCalls += 1 }
    }
}

private nonisolated final class AuthenticationEventSpy: AuthenticationEventReceiving, @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    var count: Int { lock.withLock { _count } }

    func authenticationRequired() async {
        lock.withLock { _count += 1 }
    }
}

nonisolated final class AuthenticatedHTTPClientTests: XCTestCase {
    private let url = URL(string: "https://api.example/protected")!

    override func tearDown() {
        AuthStubURLProtocol.reset()
        super.tearDown()
    }

    private func makeClient(
        sessions: ScriptedSessionProvider,
        events: (any AuthenticationEventReceiving)? = nil
    ) -> AuthenticatedHTTPClient {
        AuthenticatedHTTPClient(
            sessions: sessions,
            session: AuthStubURLProtocol.makeSession(),
            events: events
        )
    }

    private func stub(status: Int, body: Data = Data()) {
        AuthStubURLProtocol.stub { request in
            (AuthFixtures.response(request.url!, status), body)
        }
    }

    func testBearerIsAttachedBeforeSending() async throws {
        let sessions = ScriptedSessionProvider()
        stub(status: 200, body: Data("ok".utf8))

        let (data, response) = try await makeClient(sessions: sessions)
            .send(URLRequest(url: url))

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(data, Data("ok".utf8))
        XCTAssertEqual(
            AuthStubURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization"),
            "Bearer access-1"
        )
    }

    func testA401RefreshesOnceAndReplaysOnce() async throws {
        let sessions = ScriptedSessionProvider()
        AuthStubURLProtocol.stub { request in
            let token = request.value(forHTTPHeaderField: "Authorization")
            let status = token == "Bearer access-1" ? 401 : 200
            return (AuthFixtures.response(request.url!, status), Data())
        }

        let (_, response) = try await makeClient(sessions: sessions)
            .send(URLRequest(url: url))

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(sessions.refreshCalls, ["access-1"])
        XCTAssertEqual(AuthStubURLProtocol.requests.count, 2)
        XCTAssertEqual(
            AuthStubURLProtocol.requests.last?.value(forHTTPHeaderField: "Authorization"),
            "Bearer access-2"
        )
    }

    func testASecond401EndsTheSessionAndDoesNotLoop() async {
        let sessions = ScriptedSessionProvider()
        let events = AuthenticationEventSpy()
        stub(status: 401)

        do {
            _ = try await makeClient(sessions: sessions, events: events)
                .send(URLRequest(url: url))
            XCTFail("A replayed 401 must fail.")
        } catch {
            XCTAssertEqual(error as? AuthError, .refreshRejected)
        }

        XCTAssertEqual(AuthStubURLProtocol.requests.count, 2)
        XCTAssertEqual(sessions.refreshCalls.count, 1)
        XCTAssertEqual(sessions.endSessionCalls, 1)
        XCTAssertEqual(events.count, 1)
    }

    func testDomain409And422NeverRefresh() async throws {
        for status in [409, 422] {
            let sessions = ScriptedSessionProvider()
            stub(status: status)

            let (_, response) = try await makeClient(sessions: sessions)
                .send(URLRequest(url: url))

            XCTAssertEqual(response.statusCode, status)
            XCTAssertTrue(sessions.refreshCalls.isEmpty)
            XCTAssertEqual(AuthStubURLProtocol.requests.count, 1)
        }
    }

    func testNonReplayableRequestReturns401WithoutRefreshing() async throws {
        let sessions = ScriptedSessionProvider()
        let events = AuthenticationEventSpy()
        stub(status: 401)

        let (_, response) = try await makeClient(sessions: sessions, events: events)
            .send(URLRequest(url: url), allowsReplay: false)

        XCTAssertEqual(response.statusCode, 401)
        XCTAssertTrue(sessions.refreshCalls.isEmpty)
        XCTAssertEqual(AuthStubURLProtocol.requests.count, 1)
        XCTAssertEqual(events.count, 0)
    }

    func testTransientRefreshFailureDoesNotPublishAuthenticationRequired() async {
        let sessions = ScriptedSessionProvider()
        sessions.refreshResult = .failure(.serviceUnavailable)
        let events = AuthenticationEventSpy()
        stub(status: 401)

        do {
            _ = try await makeClient(sessions: sessions, events: events)
                .send(URLRequest(url: url))
            XCTFail("A failed refresh must fail the request.")
        } catch {
            XCTAssertEqual(error as? AuthError, .serviceUnavailable)
        }

        XCTAssertEqual(events.count, 0, "an outage is not proof the session ended")
        XCTAssertEqual(sessions.endSessionCalls, 0)
    }

    @MainActor
    func testAuthenticationRequiredEventReachesTheJourneyStore() async {
        let sessions = ScriptedSessionProvider()
        sessions.validResult = .failure(.refreshRejected)
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journey = AppJourneyStore(
            credentials: InMemoryCredentialStore(),
            sessions: sessions,
            auth: StubAuthService(),
            submissions: StubSubmissionService(),
            credentialState: StubCredentialStateChecker(),
            onboardingStorage: OnboardingStorage(directory: directory),
            pendingStorage: PendingOnboardingStorage(
                directory: directory.appending(path: "Protected")
            )
        )
        await journey.bootstrap()
        XCTAssertEqual(journey.phase, .onboarding)

        stub(status: 200)
        let client = AuthenticatedHTTPClient(
            sessions: sessions,
            session: AuthStubURLProtocol.makeSession(),
            events: journey.eventRelay
        )
        _ = try? await client.send(URLRequest(url: url))

        XCTAssertEqual(journey.phase, .access)
    }
}
