//
//  RemoteCalorieServiceTests.swift
//  KaloriasTests
//
//  Contract A10: status → outcome, and the request properties FR-004/005/006
//  turn on. Nothing here touches the network — every response comes from a
//  `URLProtocol` stub.
//

import XCTest
@testable import Kalorias

/// Serves canned responses in place of the network.
///
/// `nonisolated(unsafe)` with an explicit lock rather than a blanket escape
/// (constitution Principle V): `URLProtocol` is instantiated by URLSession on
/// its own queue, so the handler and the captured request are reachable from
/// two threads. The lock is the invariant — every access below goes through it,
/// and nothing else in the process touches these two values.
private nonisolated final class StubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?
    nonisolated(unsafe) private static var capturedRequests: [URLRequest] = []

    static func stub(_ handler: @escaping Handler) {
        lock.withLock {
            self.handler = handler
            capturedRequests = []
        }
    }

    static func reset() {
        lock.withLock {
            handler = nil
            capturedRequests = []
        }
    }

    static var requests: [URLRequest] { lock.withLock { capturedRequests } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let handler = Self.lock.withLock {
            Self.capturedRequests.append(request)
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
}

nonisolated final class RemoteCalorieServiceTests: XCTestCase {

    private let baseURL = URL(string: "http://localhost:8000")!
    private let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])

    private let successBody = Data("""
    { "data": { "foodDetected": true, "totalCalories": 615, "foods": [
        { "name": "Arroz blanco", "calories": 205, "protein": 4.3, "carbs": 44.5, "fat": 0.4,
          "region": { "x": 0.12, "y": 0.31, "width": 0.4, "height": 0.28 } },
        { "name": "Pechuga de pollo", "calories": 410, "region": null } ] } }
    """.utf8)

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    /// Built from the service's own configuration, so these tests exercise the
    /// real timeouts and cache policy rather than a convenient stand-in.
    private func makeService(baseURL: URL?) -> RemoteCalorieService {
        let configuration = RemoteCalorieService.makeConfiguration()
        configuration.protocolClasses = [StubURLProtocol.self]
        return RemoteCalorieService(baseURL: baseURL, session: URLSession(configuration: configuration))
    }

    private func respond(_ status: Int, _ body: Data = Data(), headers: [String: String] = [:]) {
        StubURLProtocol.stub { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "http://localhost:8000")!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers.merging(["X-Request-Id": "req-test-1"]) { a, _ in a }
            )!
            return (response, body)
        }
    }

    private func analyze(baseURL: URL?) async -> Result<AnalysisOutcome, AnalysisError> {
        do {
            return .success(try await makeService(baseURL: baseURL).analyze(imageData: imageData))
        } catch let error as AnalysisError {
            return .failure(error)
        } catch {
            return .failure(.serviceError)
        }
    }

    private func expectFailure(
        _ expected: AnalysisError,
        status: Int,
        body: Data = Data(),
        headers: [String: String] = [:],
        line: UInt = #line
    ) async {
        respond(status, body, headers: headers)
        let result = await analyze(baseURL: baseURL)

        guard case .failure(let error) = result else {
            return XCTFail("HTTP \(status) must not succeed", line: line)
        }
        XCTAssertEqual(error, expected, "HTTP \(status)", line: line)
    }

    // MARK: A10 — status → outcome

    func test200WithFoodIsASuccess() async throws {
        respond(200, successBody)

        guard case .success(.success(let analysis)) = await analyze(baseURL: baseURL) else {
            return XCTFail("expected a food-bearing success")
        }
        XCTAssertEqual(analysis.totalCalories, 615)
        XCTAssertEqual(analysis.items.count, 2)
    }

    /// `422` and `413` differ only in which layer refused the photo, which is
    /// meaningless to the user: both offer Retake.
    func test422AndT413AreAPhotoRejection() async {
        await expectFailure(
            .photoRejected,
            status: 422,
            body: Data(#"{"message":"La foto no es válida.","errors":{"photo":["Debe ser JPEG."]}}"#.utf8)
        )
        await expectFailure(.photoRejected, status: 413)
    }

    func test429IsRateLimitedCarryingTheServersWait() async {
        await expectFailure(
            .rateLimited(retryAfter: 20),
            status: 429,
            body: Data(#"{"message":"Demasiadas peticiones."}"#.utf8),
            headers: ["Retry-After": "20"]
        )
    }

    /// FR-020a: a `429` with no usable header still produces a definite wait.
    func test429WithoutARetryAfterHeaderFallsBackToOneMinute() async {
        await expectFailure(.rateLimited(retryAfter: 60), status: 429)
    }

    /// `503` is deliberately opaque, and everything unexpected joins it — the
    /// contract may add codes and the app must not break when it does.
    func testServerAndUnexpectedStatusesAreServiceErrors() async {
        await expectFailure(.serviceError, status: 503, body: Data(#"{"message":"No disponible."}"#.utf8))
        await expectFailure(.serviceError, status: 500)
        await expectFailure(.serviceError, status: 418)
        await expectFailure(.serviceError, status: 404)
        await expectFailure(.serviceError, status: 301)
    }

    func testUnreadable200IsAnInvalidResponse() async {
        await expectFailure(.invalidResponse, status: 200, body: Data(#"{"nope":true}"#.utf8))
        await expectFailure(.invalidResponse, status: 200, body: Data("not json".utf8))
        await expectFailure(.invalidResponse, status: 200)
    }

    /// Rule C1: a build with no address fails every analysis with the generic
    /// service message — and makes no request at all, so there is no chance of
    /// a fallback to somewhere else.
    func testAMissingBaseURLIsAServiceErrorAndSendsNothing() async {
        respond(200, successBody)

        guard case .failure(let error) = await analyze(baseURL: nil) else {
            return XCTFail("a missing address must fail")
        }
        XCTAssertEqual(error, .serviceError)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty, "nothing may be sent without an address")
    }

    func testATransportFailureMapsThroughTheExistingURLErrorRules() async {
        StubURLProtocol.reset()   // no handler ⇒ the stub fails the load

        guard case .failure(let error) = await analyze(baseURL: baseURL) else {
            return XCTFail("a transport failure must fail")
        }
        XCTAssertEqual(error, .serviceError)
    }

    // MARK: The request itself

    func testRequestIsAPOSTToTheContractPath() async throws {
        respond(200, successBody)
        _ = await analyze(baseURL: baseURL)

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:8000/api/v1/kalorias/analyzeMeal")
    }

    /// FR-004. Sending a credential here would be a defect, not a precaution:
    /// the server holds the provider key and this endpoint takes no auth.
    func testNoAuthorizationHeaderIsSent() async throws {
        respond(200, successBody)
        _ = await analyze(baseURL: baseURL)

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        let headers = request.allHTTPHeaderFields ?? [:]

        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        for name in headers.keys {
            XCTAssertFalse(
                name.lowercased().contains("auth") || name.lowercased().contains("api-key"),
                "unexpected credential header: \(name)"
            )
        }
    }

    func testContentTypeIsMultipartWithAGeneratedBoundary() async throws {
        respond(200, successBody)
        _ = await analyze(baseURL: baseURL)

        let contentType = try XCTUnwrap(
            XCTUnwrap(StubURLProtocol.requests.first).value(forHTTPHeaderField: "Content-Type")
        )
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
        XCTAssertGreaterThan(
            contentType.components(separatedBy: "boundary=").last?.count ?? 0, 32
        )
    }

    /// Every request generates its own boundary (rule M5) — a boundary reused
    /// across requests is how a body ends up truncated at the wrong place.
    func testEachRequestCarriesItsOwnBoundary() async throws {
        respond(200, successBody)
        _ = await analyze(baseURL: baseURL)
        _ = await analyze(baseURL: baseURL)

        let boundaries = StubURLProtocol.requests.compactMap {
            $0.value(forHTTPHeaderField: "Content-Type")
        }
        XCTAssertEqual(boundaries.count, 2)
        XCTAssertNotEqual(boundaries[0], boundaries[1])
    }

    // MARK: FR-005 / FR-006 — the session's construction

    /// Asserted on the configuration itself rather than trusted to a comment:
    /// these three lines are the whole of "35 seconds of patience, a bounded
    /// wait, and nothing cached".
    func testSessionConfigurationCarriesTheContractsTimeoutsAndNoCache() {
        let configuration = RemoteCalorieService.makeConfiguration()

        XCTAssertEqual(configuration.timeoutIntervalForRequest, 35)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 60)
        XCTAssertNil(configuration.urlCache, "no analysis response may be cached (FR-006)")
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertGreaterThan(
            configuration.timeoutIntervalForResource,
            configuration.timeoutIntervalForRequest,
            "the resource ceiling must bound the inactivity timer, not undercut it"
        )
    }

    /// `.ephemeral` is what keeps cookies and credentials out of the shared,
    /// on-disk stores — it gives the session private in-memory ones instead of
    /// removing them, so the assertion is "not the shared store", not "nil".
    /// Losing `.ephemeral` would silently reattach this session to both, and
    /// put meal-photo requests into state the rest of the app can see.
    func testSessionSharesNoCookieOrCredentialStorageWithTheApp() {
        let configuration = RemoteCalorieService.makeConfiguration()

        XCTAssertFalse(
            configuration.httpCookieStorage === HTTPCookieStorage.shared,
            "an ephemeral session must not use the shared cookie store"
        )
        XCTAssertFalse(
            configuration.urlCredentialStorage === URLCredentialStorage.shared,
            "an ephemeral session must not use the shared credential store"
        )
    }

    // MARK: US2 — no food is a success, not an error (T033 / FR-011)

    /// The trap this closes: a service that treats "no calories" as "nothing
    /// came back" would route a perfectly good `200` into the error state, and
    /// the user would see a failure message for a photo of their desk.
    func test200WithNoFoodIsASuccessfulNoFoodNotAnError() async {
        respond(200, Data(#"{ "data": { "foodDetected": false, "totalCalories": 0, "foods": [] } }"#.utf8))

        switch await analyze(baseURL: baseURL) {
        case .success(let outcome):
            XCTAssertEqual(outcome, .noFood)
        case .failure(let error):
            XCTFail("no food must not reach an error path, got \(error)")
        }
    }

    func test200WithAnEmptyFoodsArrayIsAlsoASuccessfulNoFood() async {
        respond(200, Data(#"{ "data": { "foodDetected": true, "totalCalories": 0, "foods": [] } }"#.utf8))

        guard case .success(.noFood) = await analyze(baseURL: baseURL) else {
            return XCTFail("an empty foods array must be a successful no-food")
        }
    }
}
