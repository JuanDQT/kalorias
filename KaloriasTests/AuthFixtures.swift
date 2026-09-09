//
//  AuthFixtures.swift
//  KaloriasTests
//
//  The doubles feature 010's suites share: a Keychain that lives in memory, an
//  auth service that answers from a script, and a `URLProtocol` that stands in
//  for the network.
//
//  NOTHING HERE REACHES APPLE OR A BACKEND. Every test in this feature is
//  deterministic and offline — a suite that needed a staging server would be a
//  suite nobody runs.
//

import Foundation
import XCTest
@testable import Kalorias

// MARK: - Credential storage

/// The Keychain, in memory. Faithful about the two behaviours the journey
/// depends on: a second save updates, and the three records have independent
/// lifetimes.
nonisolated final class InMemoryCredentialStore: CredentialStoring, @unchecked Sendable {

    private let lock = NSLock()
    private var _session: AuthSession?
    private var _knownAccount: KnownAccount?
    private var _deletionAttempt: AccountDeletionAttempt?

    /// When set, every operation throws it — the "the Keychain is unreadable"
    /// branch, which must never be resolved by guessing.
    nonisolated(unsafe) var failure: (any Error)?

    init(
        session: AuthSession? = nil,
        knownAccount: KnownAccount? = nil,
        deletionAttempt: AccountDeletionAttempt? = nil
    ) {
        _session = session
        _knownAccount = knownAccount
        _deletionAttempt = deletionAttempt
    }

    private func guardFailure() throws {
        if let failure { throw failure }
    }

    func loadSession() throws -> AuthSession? {
        try guardFailure()
        return lock.withLock { _session }
    }

    func saveSession(_ session: AuthSession) throws {
        try guardFailure()
        lock.withLock { _session = session }
    }

    func deleteSession() throws {
        try guardFailure()
        lock.withLock { _session = nil }
    }

    func loadKnownAccount() throws -> KnownAccount? {
        try guardFailure()
        return lock.withLock { _knownAccount }
    }

    func saveKnownAccount(_ account: KnownAccount) throws {
        try guardFailure()
        lock.withLock { _knownAccount = account }
    }

    func deleteKnownAccount() throws {
        try guardFailure()
        lock.withLock { _knownAccount = nil }
    }

    func loadDeletionAttempt() throws -> AccountDeletionAttempt? {
        try guardFailure()
        return lock.withLock { _deletionAttempt }
    }

    func saveDeletionAttempt(_ attempt: AccountDeletionAttempt) throws {
        try guardFailure()
        lock.withLock { _deletionAttempt = attempt }
    }

    func deleteDeletionAttempt() throws {
        try guardFailure()
        lock.withLock { _deletionAttempt = nil }
    }

    // Read directly, for assertions.
    var storedSession: AuthSession? { lock.withLock { _session } }
    var storedKnownAccount: KnownAccount? { lock.withLock { _knownAccount } }
    var storedDeletionAttempt: AccountDeletionAttempt? { lock.withLock { _deletionAttempt } }
}

// MARK: - Auth service

/// A scripted `AuthenticationServicing`, with a call log so a test can assert
/// how many times a route was hit — which is the whole question for single-flight
/// refresh and one-replay retry.
nonisolated final class StubAuthService: AuthenticationServicing, @unchecked Sendable {

    private let lock = NSLock()

    nonisolated(unsafe) var authenticateResult: Result<AuthenticationResponse, any Error>?
    nonisolated(unsafe) var refreshResult: Result<SessionCredentials, any Error>?
    /// Extra latency on refresh, so two callers genuinely overlap.
    nonisolated(unsafe) var refreshDelay: Duration = .zero
    nonisolated(unsafe) var deleteResult: Result<Void, any Error> = .success(())

    private var _authenticateCalls: [AppleAuthorizationCredential] = []
    private var _refreshCalls: [String] = []
    private var _deleteCalls: [(token: String, operationId: UUID)] = []
    private var _logoutCalls = 0

    var authenticateCalls: [AppleAuthorizationCredential] { lock.withLock { _authenticateCalls } }
    var refreshCalls: [String] { lock.withLock { _refreshCalls } }
    var deleteCalls: [(token: String, operationId: UUID)] { lock.withLock { _deleteCalls } }
    var logoutCalls: Int { lock.withLock { _logoutCalls } }

    func authenticate(
        with credential: AppleAuthorizationCredential
    ) async throws -> AuthenticationResponse {
        lock.withLock { _authenticateCalls.append(credential) }
        switch authenticateResult {
        case let .success(response): return response
        case let .failure(error): throw error
        case .none: throw AuthError.serviceUnavailable
        }
    }

    func refresh(refreshToken: String) async throws -> SessionCredentials {
        lock.withLock { _refreshCalls.append(refreshToken) }
        if refreshDelay > .zero { try? await Task.sleep(for: refreshDelay) }
        switch refreshResult {
        case let .success(session): return session
        case let .failure(error): throw error
        case .none: throw AuthError.serviceUnavailable
        }
    }

    func logout(accessToken: String, refreshToken: String) async throws {
        lock.withLock { _logoutCalls += 1 }
    }

    func deleteAccount(accessToken: String, operationId: UUID) async throws {
        lock.withLock { _deleteCalls.append((accessToken, operationId)) }
        if case let .failure(error) = deleteResult { throw error }
    }
}

// MARK: - Onboarding submission

nonisolated final class StubSubmissionService: OnboardingSubmitting, @unchecked Sendable {

    private let lock = NSLock()
    nonisolated(unsafe) var result: Result<OnboardingSubmissionResult, any Error> =
        .success(OnboardingSubmissionResult(onboardingStatus: .complete, planId: "plan-1"))

    private var _submissions: [PendingOnboarding] = []
    var submissions: [PendingOnboarding] { lock.withLock { _submissions } }

    func submit(_ pending: PendingOnboarding) async throws -> OnboardingSubmissionResult {
        lock.withLock { _submissions.append(pending) }
        switch result {
        case let .success(value): return value
        case let .failure(error): throw error
        }
    }
}

// MARK: - Apple credential state

nonisolated final class StubCredentialStateChecker: AppleCredentialStateChecking, @unchecked Sendable {
    nonisolated(unsafe) var state: AppleCredentialState = .authorized
    private let lock = NSLock()
    private var _identifiers: [String] = []
    var identifiers: [String] { lock.withLock { _identifiers } }

    init(state: AppleCredentialState = .authorized) {
        self.state = state
    }

    func state(forAppleUserIdentifier identifier: String) async -> AppleCredentialState {
        lock.withLock { _identifiers.append(identifier) }
        return state
    }
}

// MARK: - Local data

@MainActor
final class SpyLocalDataClearer: AccountLocalDataClearing {
    private(set) var clearedOwners: [String] = []

    func clearLocalData(ownedBy ownerUserID: String) async {
        clearedOwners.append(ownerUserID)
    }
}

// MARK: - Network

/// Serves canned responses in place of the network, and records what was sent.
///
/// `nonisolated(unsafe)` with an explicit lock rather than a blanket escape
/// (Principle V): `URLProtocol` is instantiated by URLSession on its own queue,
/// so the handler and the captured requests are reachable from two threads. The
/// lock is the invariant — every access below goes through it.
nonisolated final class AuthStubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?
    nonisolated(unsafe) private static var capturedRequests: [URLRequest] = []
    nonisolated(unsafe) private static var capturedBodies: [Data] = []

    static func stub(_ handler: @escaping Handler) {
        lock.withLock {
            self.handler = handler
            capturedRequests = []
            capturedBodies = []
        }
    }

    static func reset() {
        lock.withLock {
            handler = nil
            capturedRequests = []
            capturedBodies = []
        }
    }

    static var requests: [URLRequest] { lock.withLock { capturedRequests } }
    static var bodies: [Data] { lock.withLock { capturedBodies } }

    /// A session wired to this protocol and nothing else.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // `httpBody` is stripped by the loading system once a request is in
        // flight; `httpBodyStream` is what survives, so the body is read back
        // from there or the assertion would always see `nil`.
        let body = request.httpBody ?? Self.readStream(request.httpBodyStream)

        let handler = Self.lock.withLock {
            Self.capturedRequests.append(request)
            Self.capturedBodies.append(body ?? Data())
            return Self.handler
        }

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readStream(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

// MARK: - Value fixtures

nonisolated enum AuthFixtures {

    static let baseURL = URL(string: "https://api.example")!

    static func session(
        userId: String = "user-1",
        appleUserIdentifier: String = "apple-sub-1",
        accessToken: String = "access-1",
        accessExpiry: Date = Date(timeIntervalSince1970: 10_000),
        refreshToken: String = "refresh-1",
        refreshExpiry: Date = Date(timeIntervalSince1970: 900_000),
        onboardingStatus: OnboardingServerStatus = .required
    ) -> AuthSession {
        AuthSession(
            userId: userId,
            appleUserIdentifier: appleUserIdentifier,
            accessToken: accessToken,
            accessTokenExpiresAt: accessExpiry,
            refreshToken: refreshToken,
            refreshTokenExpiresAt: refreshExpiry,
            onboardingStatus: onboardingStatus
        )
    }

    static func credentials(
        accessToken: String = "access-2",
        refreshToken: String = "refresh-2"
    ) -> SessionCredentials {
        SessionCredentials(
            tokenType: "Bearer",
            accessToken: accessToken,
            accessTokenExpiresAt: Date(timeIntervalSince1970: 20_000),
            refreshToken: refreshToken,
            refreshTokenExpiresAt: Date(timeIntervalSince1970: 950_000)
        )
    }

    static func authResponse(
        userId: String = "user-1",
        status: OnboardingServerStatus = .required
    ) -> AuthenticationResponse {
        AuthenticationResponse(
            userId: userId,
            session: credentials(accessToken: "access-1", refreshToken: "refresh-1"),
            onboardingStatus: status
        )
    }

    static func appleCredential(
        appleUserIdentifier: String = "apple-sub-1"
    ) -> AppleAuthorizationCredential {
        AppleAuthorizationCredential(
            identityToken: "identity-token",
            authorizationCode: "authorization-code",
            appleUserIdentifier: appleUserIdentifier,
            rawNonce: "raw-nonce"
        )
    }

    static func submission(sessionId: UUID = UUID()) -> OnboardingSubmission {
        OnboardingSubmission(
            sessionId: sessionId,
            onboardingId: "plan_v1",
            schemaVersion: 1,
            contentVersion: 5,
            locale: "es",
            startedAt: Date(timeIntervalSince1970: 1_000),
            completedAt: Date(timeIntervalSince1970: 1_160),
            answers: [
                OnboardingSubmission.Entry(
                    questionId: "goal_primary",
                    type: .singleChoice,
                    answer: .single(optionId: "lose_weight")
                )
            ]
        )
    }

    static func pending(
        sessionId: UUID = UUID(),
        consented: Bool = false
    ) -> PendingOnboarding {
        PendingOnboarding(
            submission: submission(sessionId: sessionId),
            consent: consented ? ConsentReceipt(grantedAt: Date(timeIntervalSince1970: 2_000)) : nil
        )
    }

    static func response(_ url: URL, _ status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }
}
