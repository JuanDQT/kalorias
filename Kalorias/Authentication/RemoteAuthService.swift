//
//  RemoteAuthService.swift
//  Kalorias
//
//  The Kalorias authentication endpoints: exchange an Apple authorization for a
//  session, rotate that session, end it, and delete the account
//  (contracts/auth-api-v1.md).
//
//  PATHS, NEVER WHOLE URLS. The address comes from `BackendEnvironment` and
//  nowhere else (constitution, Backend Environments).
//
//  THE AUTH BODY IS EXACTLY THREE FIELDS, and the encoding is written by hand so
//  a future property added to some shared model cannot silently join the
//  request. No answers, no email, no name, and no client-declared Apple user id
//  — the server derives the subject from the token it verified, and a subject
//  the client asserts is not evidence (FR-014).
//
//  THE REFRESH ROUTE DOES NOT PRESENT THE ACCESS TOKEN. Its authority is the
//  refresh credential in the body; sending an expired bearer alongside it would
//  invite a server that accepts either.
//
//  ERRORS BECOME STABLE CASES, NOT STATUS CODES. The UI must never show an HTTP
//  number or a server sentence (FR-049), and — more importantly — the journey
//  branches differently for "that Apple attempt was replayed" and "Kalorias is
//  down". Mapping happens once, here.
//
//  AN EPHEMERAL SESSION: no cache, no cookies, no credential storage. A response
//  carrying tokens must not be written to a URL cache by accident.
//

import Foundation

/// The authentication boundary, so the coordinator and journey store are
/// testable without a network (Principle II).
protocol AuthenticationServicing: Sendable {
    /// Exchange a verified Apple authorization for a Kalorias session.
    nonisolated func authenticate(
        with credential: AppleAuthorizationCredential
    ) async throws -> AuthenticationResponse

    /// Rotate the session. The refresh credential is the only authority used.
    nonisolated func refresh(refreshToken: String) async throws -> SessionCredentials

    /// End the session family. Best-effort: the local session is cleared either
    /// way, because a device that cannot reach the server must still be able to
    /// stop using a credential.
    nonisolated func logout(accessToken: String, refreshToken: String) async throws

    /// Delete the account, presenting exactly the values a confirmed attempt
    /// recorded. `204` is the only success (contract: `202` is not).
    nonisolated func deleteAccount(
        accessToken: String,
        operationId: UUID
    ) async throws
}

// MARK: - Wire values

/// The session half of an auth or refresh response.
nonisolated struct SessionCredentials: Decodable, Equatable, Sendable {
    let tokenType: String
    let accessToken: String
    let accessTokenExpiresAt: Date
    let refreshToken: String
    let refreshTokenExpiresAt: Date

    /// `Bearer` exactly. A server that starts issuing another scheme is a server
    /// this build does not know how to present credentials to.
    var isValid: Bool {
        tokenType == "Bearer"
            && !accessToken.isEmpty
            && !refreshToken.isEmpty
            && refreshTokenExpiresAt >= accessTokenExpiresAt
    }
}

nonisolated struct AuthenticationResponse: Equatable, Sendable {
    let userId: String
    let session: SessionCredentials
    let onboardingStatus: OnboardingServerStatus

    /// The Keychain record this response commits to, given the Apple identifier
    /// the app kept from the authorization.
    func makeSession(appleUserIdentifier: String) -> AuthSession {
        AuthSession(
            userId: userId,
            appleUserIdentifier: appleUserIdentifier,
            accessToken: session.accessToken,
            accessTokenExpiresAt: session.accessTokenExpiresAt,
            refreshToken: session.refreshToken,
            refreshTokenExpiresAt: session.refreshTokenExpiresAt,
            onboardingStatus: onboardingStatus
        )
    }
}

// MARK: - Errors

/// Why an authentication call did not produce a session. Each case exists
/// because the journey does something different with it.
nonisolated enum AuthError: Error, Equatable, Sendable {
    case noConnection
    case timeout
    /// The address is missing or unparseable. A build configuration problem.
    case notConfigured
    /// Malformed, or valid JSON describing an unusable session.
    case invalidResponse

    /// `400 invalid_request`
    case invalidRequest
    /// `401 invalid_apple_credential`
    case invalidAppleCredential
    /// `409 auth_attempt_replayed` — a wholly fresh Apple attempt is required.
    case attemptReplayed
    /// `429`, with the server's own backoff when it gave one.
    case rateLimited(retryAfter: TimeInterval?)
    /// `503`/`500` — recoverable; nothing local is discarded.
    case serviceUnavailable

    /// `401 invalid_refresh_token` — this session is definitively over.
    case refreshRejected
    /// `409 refresh_token_reused` — the whole local family is invalidated.
    case refreshReused

    /// `403 reauthentication_required` on deletion.
    case reauthenticationRequired
    /// `409/503 apple_revocation_pending` — retryable, nothing deleted.
    case revocationPending

    var messageKey: String.LocalizationValue {
        switch self {
        case .invalidAppleCredential, .invalidRequest, .invalidResponse:
            "access.error.invalidCredential"
        case .attemptReplayed:
            "access.error.replayed"
        case .rateLimited:
            "access.error.rateLimited"
        case .noConnection, .timeout, .serviceUnavailable, .revocationPending, .notConfigured:
            "access.error.serviceUnavailable"
        case .refreshRejected, .refreshReused, .reauthenticationRequired:
            "access.error.generic"
        }
    }

    /// Whether the refresh credential is definitively gone, as opposed to
    /// temporarily unreachable. Only the former may end a session (FR-034's
    /// sibling rule for tokens): a 500 must not log a user out.
    var isDefinitiveRefreshFailure: Bool {
        switch self {
        case .refreshRejected, .refreshReused, .invalidRequest: true
        default: false
        }
    }

    /// The backoff the server asked for, if any.
    var retryAfter: TimeInterval? {
        if case let .rateLimited(retryAfter) = self { return retryAfter }
        return nil
    }

    static func from(_ error: any Error) -> AuthError {
        if let authError = error as? AuthError { return authError }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return .noConnection
            case .timedOut:
                return .timeout
            default:
                return .serviceUnavailable
            }
        }
        if error is DecodingError { return .invalidResponse }
        return .serviceUnavailable
    }
}

// MARK: - Service

nonisolated struct RemoteAuthService: AuthenticationServicing {

    static let applePath = "/api/v1/auth/apple"
    static let refreshPath = "/api/v1/auth/refresh"
    static let logoutPath = "/api/v1/auth/logout"
    static let accountPath = "/api/v1/account"

    static let requestTimeout: TimeInterval = 20
    static let resourceTimeout: TimeInterval = 40

    let baseURL: URL?
    let session: URLSession

    init(baseURL: URL? = BackendEnvironment.analysisBaseURL, session: URLSession = Self.makeSession()) {
        self.baseURL = baseURL
        self.session = session
    }

    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        // Belt and braces over `.ephemeral`: a response carrying tokens must
        // never reach a URL cache.
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return configuration
    }

    static func makeSession() -> URLSession {
        URLSession(configuration: makeConfiguration())
    }

    // MARK: Apple

    func authenticate(
        with credential: AppleAuthorizationCredential
    ) async throws -> AuthenticationResponse {
        var request = try makeRequest(path: Self.applePath, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Hand-written, so exactly these three fields can ever be sent.
        request.httpBody = try Self.encoder.encode(
            AppleAuthRequestBody(
                identityToken: credential.identityToken,
                authorizationCode: credential.authorizationCode,
                nonce: credential.rawNonce
            )
        )

        let (data, http) = try await send(request)
        guard http.statusCode == 200 || http.statusCode == 201 else {
            throw Self.mapError(status: http.statusCode, data: data, headers: http)
        }

        // Decoding failures are mapped here, not left to escape. A raw
        // `DecodingError` reaching the journey is an error with no branch and no
        // copy — an unknown onboarding status and an unparseable date are both
        // "this response is unusable", and that is a case the UI already has.
        guard let envelope = try? Self.decoder.decode(AuthEnvelope.self, from: data) else {
            throw AuthError.invalidResponse
        }
        guard !envelope.data.user.id.isEmpty, envelope.data.session.isValid else {
            throw AuthError.invalidResponse
        }
        return AuthenticationResponse(
            userId: envelope.data.user.id,
            session: envelope.data.session,
            onboardingStatus: envelope.data.onboarding.status
        )
    }

    // MARK: Refresh

    func refresh(refreshToken: String) async throws -> SessionCredentials {
        var request = try makeRequest(path: Self.refreshPath, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.encoder.encode(RefreshRequestBody(refreshToken: refreshToken))

        let (data, http) = try await send(request)
        guard http.statusCode == 200 else {
            throw Self.mapError(status: http.statusCode, data: data, headers: http)
        }

        guard let envelope = try? Self.decoder.decode(RefreshEnvelope.self, from: data) else {
            throw AuthError.invalidResponse
        }
        guard envelope.data.session.isValid else { throw AuthError.invalidResponse }
        // The contract requires a *rotated* refresh token. Getting the same one
        // back means the server is not rotating, and reuse detection — the thing
        // that makes a stolen refresh token detectable — cannot work.
        guard envelope.data.session.refreshToken != refreshToken else {
            throw AuthError.invalidResponse
        }
        return envelope.data.session
    }

    // MARK: Logout

    func logout(accessToken: String, refreshToken: String) async throws {
        var request = try makeRequest(path: Self.logoutPath, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try Self.encoder.encode(RefreshRequestBody(refreshToken: refreshToken))

        let (data, http) = try await send(request)
        guard http.statusCode == 204 else {
            throw Self.mapError(status: http.statusCode, data: data, headers: http)
        }
    }

    // MARK: Deletion

    /// Presents the exact values the confirmed attempt recorded, deliberately
    /// bypassing the authenticated client: after a successful server deletion
    /// there is nothing left to refresh against, and only these values match the
    /// backend's deletion tombstone.
    func deleteAccount(accessToken: String, operationId: UUID) async throws {
        var request = try makeRequest(path: Self.accountPath, method: "DELETE")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(operationId.uuidString, forHTTPHeaderField: "Idempotency-Key")

        let (data, http) = try await send(request)
        // `204` and nothing else. `202` would mean the server is still working,
        // and this build has no contract for polling that.
        guard http.statusCode == 204 else {
            throw Self.mapError(status: http.statusCode, data: data, headers: http)
        }
    }

    // MARK: Plumbing

    private func makeRequest(path: String, method: String) throws -> URLRequest {
        guard let baseURL else { throw AuthError.notConfigured }
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-Id")
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
            return (data, http)
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.from(error)
        }
    }

    /// Status plus the server's stable machine code. The code decides, because
    /// two different `409`s mean two different things here.
    static func mapError(status: Int, data: Data, headers: HTTPURLResponse?) -> AuthError {
        let code = (try? decoder.decode(ErrorEnvelope.self, from: data))?.error.code

        switch status {
        case 400: return .invalidRequest
        case 401:
            return code == "invalid_refresh_token" ? .refreshRejected : .invalidAppleCredential
        case 403: return .reauthenticationRequired
        case 409:
            switch code {
            case "refresh_token_reused": return .refreshReused
            case "apple_revocation_pending": return .revocationPending
            default: return .attemptReplayed
            }
        case 429:
            let retryAfter = headers?.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            return .rateLimited(retryAfter: retryAfter)
        case 503:
            return code == "apple_revocation_pending" ? .revocationPending : .serviceUnavailable
        default:
            return .serviceUnavailable
        }
    }

    // MARK: Bodies

    /// The whole `/auth/apple` request. Adding a field here is the only way to
    /// add one to the wire, which is the point.
    private struct AppleAuthRequestBody: Encodable {
        let identityToken: String
        let authorizationCode: String
        let nonce: String
    }

    private struct RefreshRequestBody: Encodable {
        let refreshToken: String
    }

    private struct AuthEnvelope: Decodable {
        struct Payload: Decodable {
            struct User: Decodable { let id: String }
            struct Onboarding: Decodable { let status: OnboardingServerStatus }
            let user: User
            let session: SessionCredentials
            let onboarding: Onboarding
        }
        let data: Payload
    }

    private struct RefreshEnvelope: Decodable {
        struct Payload: Decodable { let session: SessionCredentials }
        let data: Payload
    }

    struct ErrorEnvelope: Decodable {
        struct Failure: Decodable { let code: String }
        let error: Failure
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
