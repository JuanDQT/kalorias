//
//  RemoteCalorieService.swift
//  Kalorias
//
//  The real `CalorieAnalyzing` implementation: uploads the photo to the Kalorias
//  backend and maps the reply to a domain outcome. It replaced a direct
//  AI-provider call behind the **unchanged** protocol, which is why the store,
//  the views and persistence carried on untouched.
//
//  IT SENDS A PHOTO AND NOTHING ELSE. No prompt, no response schema, no token
//  ceiling, and NO AUTHORIZATION HEADER — the server owns all of it, and sending
//  a credential here would be a defect rather than a precaution (FR-004).
//
//  TIMEOUTS ARE TWO NUMBERS, NOT ONE. `timeoutIntervalForRequest` is an
//  *inactivity* timer that resets on every byte received, so on its own it lets
//  a slow-drip response hang far past the 35 s of patience the server needs
//  while it waits on the model. `timeoutIntervalForResource` is the wall-clock
//  ceiling for the whole transfer, and it is what actually guarantees the flow
//  terminates.
//
//  NOTHING IS CACHED. The session is built from `.ephemeral`, which removes the
//  URL cache, cookie storage and credential storage in one line — so FR-006 is a
//  property of how the session is constructed rather than a chain of assumptions
//  about `POST` defaults.
//
//  Networking and decoding run in the async context, off the main thread; the
//  type is a `Sendable` value type holding no mutable state.
//

import Foundation

nonisolated struct RemoteCalorieService: CalorieAnalyzing {

    /// Appended to the environment's base URL. A path, never a whole URL — the
    /// address comes from `BackendEnvironment` and nowhere else (constitution,
    /// Backend Environments).
    static let analyzeMealPath = "/api/v1/kalorias/analyzeMeal"

    /// 35 s of patience while the server waits on the model (FR-005).
    static let requestTimeout: TimeInterval = 35
    /// The ceiling on the whole transfer, so the flow always terminates.
    static let resourceTimeout: TimeInterval = 60

    let baseURL: URL?
    let session: URLSession

    init(
        baseURL: URL? = BackendEnvironment.analysisBaseURL,
        session: URLSession = Self.makeSession()
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    /// The analysis session. Exposed so a test can assert the three properties
    /// FR-005 and FR-006 turn on, rather than trusting the comment above.
    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    static func makeSession() -> URLSession {
        URLSession(configuration: makeConfiguration())
    }

    // MARK: Analyzing

    func analyze(imageData: Data) async throws -> AnalysisOutcome {
        // A build with no usable address fails every analysis with the generic
        // service message. It does NOT quietly call a provider directly — that
        // fallback is what would reintroduce the key this feature removed
        // (rule C1 / FR-009).
        guard let baseURL else {
            AnalysisLog.failure(outcome: "notConfigured", duration: 0, status: nil, requestId: nil)
            throw AnalysisError.serviceError
        }

        let request = makeRequest(baseURL: baseURL, imageData: imageData)
        let startedAt = Date()

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let mapped = AnalysisError.from(error)
            AnalysisLog.failure(
                outcome: String(describing: mapped),
                duration: Date().timeIntervalSince(startedAt),
                status: nil,
                requestId: nil
            )
            throw mapped
        }

        let duration = Date().timeIntervalSince(startedAt)

        guard let http = response as? HTTPURLResponse else {
            AnalysisLog.failure(outcome: "serviceError", duration: duration, status: nil, requestId: nil)
            throw AnalysisError.serviceError
        }

        let requestId = http.value(forHTTPHeaderField: "X-Request-Id")

        do {
            let outcome = try Self.outcome(status: http.statusCode, headers: http, body: data)
            AnalysisLog.success(
                outcome: outcome.logDescription,
                duration: duration,
                foodCount: outcome.foodCount,
                requestId: requestId
            )
            return outcome
        } catch {
            let mapped = AnalysisError.from(error)
            AnalysisLog.failure(
                outcome: String(describing: mapped),
                duration: duration,
                status: http.statusCode,
                requestId: requestId,
                // The server's own text goes HERE and only here: it arrives
                // Spanish-only while the app is bilingual, so the screen shows
                // the app's copy and the log keeps the detail (FR-021a).
                serverMessage: mapped == .photoRejected ? Self.serverMessage(from: data) : nil
            )
            throw mapped
        }
    }

    /// The `message` field of an error body, when there is one. Never displayed.
    private static func serverMessage(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = object["message"] as? String
        else {
            return nil
        }
        return message
    }

    private func makeRequest(baseURL: URL, imageData: Data) -> URLRequest {
        let form = MultipartFormData()

        var request = URLRequest(url: baseURL.appending(path: Self.analyzeMealPath))
        request.httpMethod = "POST"
        // Set once, by the type that owns the boundary. Hardcoding this header —
        // or letting its boundary drift from the body's — produces a `422`
        // complaining the photo is missing, which reads like a server bug.
        request.setValue(form.contentTypeHeaderValue, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.body(imageData: imageData)
        return request
    }

    // MARK: Status → outcome

    /// The mapping in `contracts/analyze-meal-v1.md`, in one place.
    ///
    /// An unexpected status falls to `.serviceError` rather than crashing or
    /// inventing a case: the contract may add codes, and the app must not break
    /// when it does.
    static func outcome(
        status: Int,
        headers: HTTPURLResponse,
        body: Data,
        now: Date = Date()
    ) throws -> AnalysisOutcome {
        switch status {
        case 200:
            // `.noFood` travels this path too — it is a success, not an error
            // (FR-011).
            return try AnalyzeMealResponse.parse(body)

        case 413, 422:
            // Which layer refused the photo is meaningless to the user: the move
            // is the same either way, a different photo.
            throw AnalysisError.photoRejected

        case 429:
            let header = headers.value(forHTTPHeaderField: "Retry-After")
            throw AnalysisError.rateLimited(
                retryAfter: RetryCooldown.parseRetryAfter(header, now: now)
            )

        default:
            // `503` is deliberately opaque, and so is everything with it: a
            // provider that is down, slow, out of quota, or holding bad
            // credentials are all the server's business to distinguish, in the
            // log where it can be acted on.
            throw AnalysisError.serviceError
        }
    }
}
