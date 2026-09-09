//
//  AuthenticatedHTTPClient.swift
//  Kalorias
//
//  Every authenticated request in the app goes through here, and the retry rule
//  lives in exactly one place (contracts/auth-api-v1.md, "Authenticated Client
//  Algorithm").
//
//  ONE REFRESH, ONE REPLAY, THEN STOP (FR-032). A `401` buys exactly one
//  coalesced refresh and exactly one identical retry. A second `401` ends the
//  session and asks for Apple. The bound is not a nicety: a client that retries
//  on every `401` against a server that always returns one is an infinite loop
//  that drains a battery and, on the analysis route, an image upload each time.
//
//  A `409` OR `422` IS NOT AN AUTHENTICATION PROBLEM, and refreshing on it would
//  hide a real domain failure behind a token dance. Only `401` triggers refresh.
//
//  THE REPLAY IS THE SAME REQUEST, byte for byte, including its idempotency key.
//  That is what makes it safe: the server either has the original result or
//  never got it. A rebuilt body under a new key would be a second plan.
//
//  A REQUEST THAT CANNOT BE SAFELY REPLAYED SAYS SO. `allowsReplay: false` opts
//  out; account deletion uses its own path entirely, because after a successful
//  deletion there is nothing left to refresh against.
//
//  THE SESSION-REQUIRED SIGNAL IS AN EVENT, NOT A THROW THE UI PARSES. When the
//  session is definitively gone the client tells the journey store once, so a
//  single place decides to show Access.
//

import Foundation

/// What the client tells the app when a session is definitively over.
protocol AuthenticationEventReceiving: Sendable, AnyObject {
    /// The session could not be renewed. Authenticated content must be gated.
    func authenticationRequired() async
}

/// Breaks the initialisation cycle between the journey store and the client it
/// builds: the store composes the client, and the client has to be able to call
/// the store back. The relay is created first, handed to the client, and pointed
/// at the store once that exists.
///
/// The reference is weak, so the relay cannot keep a store alive, and guarded by
/// a lock because it is read from whatever executor a request finished on.
nonisolated final class AuthenticationEventRelay: AuthenticationEventReceiving, @unchecked Sendable {

    private let lock = NSLock()
    private weak var receiver: (any AuthenticationEventReceiving)?

    func connect(_ receiver: any AuthenticationEventReceiving) {
        lock.lock()
        defer { lock.unlock() }
        self.receiver = receiver
    }

    func authenticationRequired() async {
        await connectedReceiver()?.authenticationRequired()
    }

    /// Read under the lock in a synchronous function: `NSLock` may not be held
    /// across a suspension point, and a lock scope that spans an `await` is a
    /// deadlock waiting for the right two callers.
    private func connectedReceiver() -> (any AuthenticationEventReceiving)? {
        lock.lock()
        defer { lock.unlock() }
        return receiver
    }
}

nonisolated final class AuthenticatedHTTPClient: Sendable {

    private let sessions: any AuthSessionProviding
    private let session: URLSession
    private let events: (any AuthenticationEventReceiving)?

    init(
        sessions: any AuthSessionProviding,
        session: URLSession = RemoteAuthService.makeSession(),
        events: (any AuthenticationEventReceiving)? = nil
    ) {
        self.sessions = sessions
        self.session = session
        self.events = events
    }

    /// Send `request` with a valid Bearer attached.
    ///
    /// - Parameter allowsReplay: whether a `401` may be retried once after a
    ///   refresh. `false` for anything not safe to send twice.
    func send(
        _ request: URLRequest,
        allowsReplay: Bool = true
    ) async throws -> (Data, HTTPURLResponse) {
        let token: String
        do {
            token = try await sessions.validAccessToken()
        } catch {
            let mapped = AuthError.from(error)
            if mapped.isDefinitiveRefreshFailure {
                await reportAuthenticationRequired()
            }
            throw mapped
        }

        let (data, http) = try await perform(request, bearer: token)
        guard http.statusCode == 401, allowsReplay else { return (data, http) }

        // Exactly one refresh, shared with any other caller that hit the same
        // wall at the same moment.
        let refreshed: String
        do {
            refreshed = try await sessions.refreshedAccessToken(replacing: token)
        } catch {
            let mapped = AuthError.from(error)
            if mapped.isDefinitiveRefreshFailure {
                await reportAuthenticationRequired()
            }
            throw mapped
        }

        let (replayData, replayHTTP) = try await perform(request, bearer: refreshed)
        if replayHTTP.statusCode == 401 {
            // The token is fresh and the server still refuses it. Retrying again
            // would be a loop; this session is over.
            await sessions.endSession()
            await reportAuthenticationRequired()
            throw AuthError.refreshRejected
        }
        return (replayData, replayHTTP)
    }

    private func perform(
        _ request: URLRequest,
        bearer: String
    ) async throws -> (Data, HTTPURLResponse) {
        var authorized = request
        authorized.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        if authorized.value(forHTTPHeaderField: "X-Request-Id") == nil {
            authorized.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-Id")
        }

        do {
            let (data, response) = try await session.data(for: authorized)
            guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
            return (data, http)
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.from(error)
        }
    }

    private func reportAuthenticationRequired() async {
        await events?.authenticationRequired()
    }
}
