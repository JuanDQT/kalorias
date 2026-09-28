//
//  OnboardingSubmissionTests.swift
//  KaloriasTests
//
//  The wire format. It is written by hand rather than synthesised, so these
//  assertions are the only thing standing between a field rename and a silent
//  API change.
//

import XCTest
@testable import Kalorias

nonisolated final class OnboardingSubmissionTests: XCTestCase {

    private func encode(_ entry: OnboardingSubmission.Entry) throws -> [String: Any] {
        let data = try OnboardingSubmission.makeEncoder().encode(entry)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testSingleChoiceTravelsAsAnIdNotAsItsText() throws {
        let json = try encode(
            .init(questionId: "goal_primary", type: .singleChoice, answer: .single(optionId: "lose_weight"))
        )
        XCTAssertEqual(json["optionId"] as? String, "lose_weight")
        XCTAssertEqual(json["type"] as? String, "single_choice")
        XCTAssertNil(json["value"])
    }

    /// Ids and free text stay in separate fields: one is data the backend can
    /// reason about, the other is a string a human will have to read.
    func testMultiChoiceKeepsCustomValuesApartFromOptionIds() throws {
        let json = try encode(
            .init(
                questionId: "allergies",
                type: .multiChoice,
                answer: .multi(optionIds: ["lactose"], customValues: ["Sésamo"])
            )
        )
        XCTAssertEqual(json["optionIds"] as? [String], ["lactose"])
        XCTAssertEqual(json["customValues"] as? [String], ["Sésamo"])
    }

    func testMeasureIsSubmittedInTheCanonicalUnitWithTheDisplayUnitAlongside() throws {
        let json = try encode(
            .init(
                questionId: "weight_current",
                type: .measure,
                answer: .measure(
                    MeasureAnswer(canonical: 84.4, unit: "kg", displayUnit: "lb",
                                  displayComponents: ["lb": 186.0])
                )
            )
        )
        XCTAssertEqual(json["value"] as? Double, 84.4)
        XCTAssertEqual(json["unit"] as? String, "kg", "never unit-less on the wire")
        XCTAssertEqual(json["displayUnit"] as? String, "lb")
        XCTAssertEqual((json["displayComponents"] as? [String: Double])?["lb"], 186.0)
    }

    /// A birthday is a day on a calendar, not an instant. Encoding it as a
    /// `Date` makes the submitted day depend on the phone's time zone.
    func testDateIsSubmittedAsAPlainDay() throws {
        let json = try encode(
            .init(questionId: "birth_date", type: .date, answer: .date(year: 1993, month: 4, day: 18))
        )
        XCTAssertEqual(json["value"] as? String, "1993-04-18")
    }

    func testSingleDigitMonthsAndDaysArePadded() throws {
        let json = try encode(
            .init(questionId: "birth_date", type: .date, answer: .date(year: 2001, month: 2, day: 3))
        )
        XCTAssertEqual(json["value"] as? String, "2001-02-03")
    }

    func testDateTimeKeepsInstantSelectedOffsetAndIANAZoneThroughWireRoundTrip() throws {
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-01T12:45:00Z"))
        let zone = try XCTUnwrap(TimeZone(identifier: "Europe/Madrid"))
        let answer = DateTimeAnswer(instant: instant, timeZone: zone)
        let entry = OnboardingSubmission.Entry(questionId: "appointment", type: .date, answer: .dateTime(answer))

        let data = try OnboardingSubmission.makeEncoder().encode(entry)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "date")
        XCTAssertEqual(json["value"] as? String, "2026-07-01T14:45:00+02:00")
        XCTAssertEqual(json["timeZone"] as? String, "Europe/Madrid")

        let decoded = try OnboardingSubmission.makeDecoder().decode(OnboardingSubmission.Entry.self, from: data)
        XCTAssertEqual(decoded, entry)
        XCTAssertEqual(try OnboardingSubmission.makeEncoder().encode(decoded), data)
    }

    func testDateTimeRetainsOffsetAcrossDaylightSavingBoundary() throws {
        let winter = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-01-15T12:45:00Z"))
        let summer = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-15T12:45:00Z"))
        let zone = try XCTUnwrap(TimeZone(identifier: "Europe/Madrid"))

        XCTAssertEqual(DateTimeAnswer(instant: winter, timeZone: zone).wireValue, "2026-01-15T13:45:00+01:00")
        XCTAssertEqual(DateTimeAnswer(instant: summer, timeZone: zone).wireValue, "2026-07-15T14:45:00+02:00")
    }

    func testDateTimeWireRejectsMissingOffsetOrZone() throws {
        let invalidEntries = [
            #"{"questionId":"appointment","type":"date","value":"2026-07-01T14:45:00","timeZone":"Europe/Madrid"}"#,
            #"{"questionId":"appointment","type":"date","value":"2026-07-01T14:45:00+02:00"}"#,
            #"{"questionId":"appointment","type":"date","value":"2026-07-01T14:45:00+02:00","timeZone":"Invalid/Zone"}"#
        ]
        for raw in invalidEntries {
            XCTAssertThrowsError(try OnboardingSubmission.makeDecoder().decode(
                OnboardingSubmission.Entry.self, from: Data(raw.utf8)
            ))
        }
    }

    func testSkippedIsDistinctFromAnyValue() throws {
        let json = try encode(.init(questionId: "extra_notes", type: .text, answer: .skipped))
        XCTAssertEqual(json["skipped"] as? Bool, true)
        XCTAssertNil(json["value"], "skipped is not an empty string")
    }

    func testAcknowledgedInfoBubblesAreRecorded() throws {
        let json = try encode(.init(questionId: "welcome", type: .info, answer: .acknowledged))
        XCTAssertEqual(json["acknowledged"] as? Bool, true)
    }

    func testTimestampsAreISO8601() throws {
        let submission = OnboardingSubmission(
            sessionId: UUID(),
            onboardingId: "plan_v1",
            schemaVersion: 1,
            contentVersion: 4,
            locale: "es",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            completedAt: Date(timeIntervalSince1970: 1_700_000_120),
            answers: []
        )
        let data = try OnboardingSubmission.makeEncoder().encode(submission)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["startedAt"] as? String, "2023-11-14T22:13:20Z")
        XCTAssertEqual(json["contentVersion"] as? Int, 4)
    }
}

// MARK: - The requests themselves

//  The wire format above says what the fields are called. This part says who is
//  allowed to see them, which is the whole of feature 010: the questionnaire is
//  fetched by nobody in particular, and the answers are sent by an account that
//  has given consent — with a key that makes a lost response harmless.

/// A session actor stand-in. These tests are about what the submission puts on
/// the wire, not about refresh: `AuthenticatedHTTPClientTests` owns that rule,
/// and restating it here would let the two drift.
private nonisolated final class FixedSessionProvider: AuthSessionProviding, @unchecked Sendable {

    private let lock = NSLock()
    private var _tokenRequests = 0
    var tokenRequests: Int { lock.withLock { _tokenRequests } }

    func validAccessToken() async throws -> String {
        lock.withLock { _tokenRequests += 1 }
        return "access-1"
    }
    func refreshedAccessToken(replacing spentToken: String) async throws -> String { "access-2" }
    func currentSession() async -> AuthSession? { AuthFixtures.session() }
    func commit(_ session: AuthSession) async throws {}
    func commitOnboardingStatus(_ status: OnboardingServerStatus) async throws {}
    func endSession() async {}
}

nonisolated final class OnboardingRequestTests: XCTestCase {

    private let baseURL = AuthFixtures.baseURL

    override func tearDown() async throws {
        AuthStubURLProtocol.reset()
    }

    private func makeSubmissionService() -> RemoteOnboardingSubmissionService {
        RemoteOnboardingSubmissionService(
            baseURL: baseURL,
            client: AuthenticatedHTTPClient(
                sessions: FixedSessionProvider(),
                session: AuthStubURLProtocol.makeSession()
            )
        )
    }

    private func body(at index: Int) throws -> [String: Any] {
        let data = AuthStubURLProtocol.bodies[index]
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: T089 — the public fetch identifies nobody

    /// The questionnaire is public content. A request that carried a bearer, a
    /// device id or an analytics id would make "who is about to answer this"
    /// server-visible before the user has agreed to anything at all.
    func testThePublicQuestionnaireFetchCarriesNoIdentityAndNoDraft() async throws {
        let questionnaire = OnboardingFixtures.wrap(
            sections: OnboardingFixtures.section(id: "s", questions: OnboardingFixtures.gate("a"))
        )
        AuthStubURLProtocol.stub { request in
            (AuthFixtures.response(request.url!, 200), Data("{\"data\": \(questionnaire)}".utf8))
        }
        let service = RemoteOnboardingService(
            baseURL: baseURL,
            session: AuthStubURLProtocol.makeSession()
        )

        _ = try await service.fetchQuestionnaire(languageCode: "es")

        let request = try XCTUnwrap(AuthStubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.url?.path(), "/api/v1/kalorias/onboarding")

        let components = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
        XCTAssertEqual(
            components?.queryItems?.map(\.name),
            ["stage"],
            "one query item: the tranche. No user, device or analytics id rides along"
        )
        XCTAssertEqual(components?.queryItems?.first?.value, "onboarding")

        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let headers = request.allHTTPHeaderFields ?? [:]
        for name in headers.keys {
            XCTAssertFalse(
                ["authorization", "x-user-id", "x-device-id", "x-install-id", "x-session-id", "cookie"]
                    .contains(name.lowercased()),
                "\(name) identifies the person asking for public content"
            )
        }
        XCTAssertNil(request.httpBody, "a fetch sends no draft")
        XCTAssertEqual(AuthStubURLProtocol.bodies.first, Data())
    }

    func testQuestionnaireSessionDisablesURLCache() {
        let configuration = RemoteOnboardingService.makeConfiguration()
        XCTAssertNil(configuration.urlCache)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testNewSchemaRequiresAnUpdateEvenWhenItsQuestionTypeCannotDecode() async throws {
        let questionnaire = OnboardingFixtures.wrap(
            sections: OnboardingFixtures.section(id: "s", questions: OnboardingFixtures.gate("a"))
        )
        .replacingOccurrences(of: "\"schemaVersion\": 1", with: "\"schemaVersion\": 2")
        .replacingOccurrences(of: "single_choice", with: "slider")
        AuthStubURLProtocol.stub { request in
            (AuthFixtures.response(request.url!, 200), Data("{\"data\": \(questionnaire)}".utf8))
        }

        let service = RemoteOnboardingService(baseURL: baseURL, session: AuthStubURLProtocol.makeSession())
        do {
            _ = try await service.fetchQuestionnaire(languageCode: "es")
            XCTFail("An incompatible schema must block the entire questionnaire")
        } catch {
            XCTAssertEqual(error as? OnboardingError, .unsupportedSchema(version: 2))
        }
    }

    func testUnknownQuestionTypeOrFieldRequiresAnUpdate() async throws {
        let base = OnboardingFixtures.wrap(
            sections: OnboardingFixtures.section(id: "s", questions: OnboardingFixtures.gate("a"))
        )
        for questionnaire in [
            base.replacingOccurrences(of: "single_choice", with: "slider"),
            base.replacingOccurrences(
                of: "\"type\": \"single_choice\"",
                with: "\"type\": \"single_choice\", \"slider\": { \"min\": 0 }"
            )
        ] {
            AuthStubURLProtocol.stub { request in
                (AuthFixtures.response(request.url!, 200), Data("{\"data\": \(questionnaire)}".utf8))
            }
            let service = RemoteOnboardingService(baseURL: baseURL, session: AuthStubURLProtocol.makeSession())
            do {
                _ = try await service.fetchQuestionnaire(languageCode: "es")
                XCTFail("An unknown question structure must block the entire questionnaire")
            } catch {
                XCTAssertEqual(error as? OnboardingError, .updateRequired)
            }
        }
    }

    func testDateTimeQuestionIsAccepted() async throws {
        let question = """
        { "id": "when", "type": "date", "prompt": ["When?"],
          "date": { "mode": "dateTime", "minDate": "2020-01-01", "maxDate": "2030-01-01" } }
        """
        let questionnaire = OnboardingFixtures.wrap(
            sections: OnboardingFixtures.section(id: "s", questions: question)
        )
        AuthStubURLProtocol.stub { request in
            (AuthFixtures.response(request.url!, 200), Data("{\"data\": \(questionnaire)}".utf8))
        }

        let service = RemoteOnboardingService(baseURL: baseURL, session: AuthStubURLProtocol.makeSession())
        let fetched = try await service.fetchQuestionnaire(languageCode: "es")
        XCTAssertEqual(fetched.questionnaire.questions.first?.date?.mode, .dateTime)
    }

    func testMalformedQuestionnaireRemainsAnInvalidResponseInsteadOfForcingAnUpdate() async throws {
        let questionnaire = OnboardingFixtures.wrap(
            sections: OnboardingFixtures.section(id: "s", questions: OnboardingFixtures.gate("a"))
        ).replacingOccurrences(of: "\"prompt\": [\"a?\"]", with: "\"prompt\": 42")
        AuthStubURLProtocol.stub { request in
            (AuthFixtures.response(request.url!, 200), Data("{\"data\": \(questionnaire)}".utf8))
        }

        let service = RemoteOnboardingService(baseURL: baseURL, session: AuthStubURLProtocol.makeSession())
        do {
            _ = try await service.fetchQuestionnaire(languageCode: "es")
            XCTFail("A malformed response must not open onboarding")
        } catch {
            XCTAssertEqual(OnboardingError.from(error), .invalidResponse)
        }
    }

    // MARK: T035 — the authenticated submission

    func testTheSubmissionCarriesTheBearerTheConsentEnvelopeAndTheSessionKey() async throws {
        AuthStubURLProtocol.stub { request in
            (
                AuthFixtures.response(request.url!, 200),
                Data(#"{"data": {"onboardingStatus": "complete", "planId": "plan-1"}}"#.utf8)
            )
        }
        let pending = AuthFixtures.pending(consented: true)

        let result = try await makeSubmissionService().submit(pending)

        XCTAssertEqual(result.onboardingStatus, .complete)
        XCTAssertEqual(result.planId, "plan-1")

        let request = try XCTUnwrap(AuthStubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path(), "/api/v1/kalorias/onboarding")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Idempotency-Key"),
            pending.submission.sessionId.uuidString,
            "the key is the session that produced the answers, not a fresh one"
        )

        let json = try body(at: 0)
        let consent = try XCTUnwrap(json["consent"] as? [String: Any])
        XCTAssertEqual(
            consent["privacyNoticeVersion"] as? String,
            AuthFixtures.consentConfiguration.privacyNoticeVersion
        )
        XCTAssertEqual(
            consent["healthDataConsentVersion"] as? String,
            AuthFixtures.consentConfiguration.healthDataConsentVersion
        )
        XCTAssertNotNil(consent["grantedAt"], "the receipt says when, not just whether")
        XCTAssertEqual(json["sessionId"] as? String, pending.submission.sessionId.uuidString)
        XCTAssertNotNil(json["answers"])
        XCTAssertNil(json["appleUserIdentifier"], "the bearer is the only authority the server needs")
        XCTAssertNil(json["email"])
    }

    /// A `200` that does not say the plan exists is not a success. Cleaning up
    /// on it would delete the only copy of the answers.
    func testAResponseWithoutACompleteStatusIsRejectedBeforeAnyCleanup() async throws {
        AuthStubURLProtocol.stub { request in
            (
                AuthFixtures.response(request.url!, 200),
                Data(#"{"data": {"onboardingStatus": "required", "planId": null}}"#.utf8)
            )
        }

        do {
            _ = try await makeSubmissionService().submit(AuthFixtures.pending(consented: true))
            XCTFail("a plan the server does not confirm is not a plan")
        } catch {
            XCTAssertEqual(error as? OnboardingError, .invalidResponse)
        }
    }

    /// No receipt, no upload. Unreachable through the journey, and a hard stop
    /// if it ever became reachable.
    func testAPayloadWithoutAConsentReceiptIsNeverSent() async throws {
        AuthStubURLProtocol.stub { request in
            (AuthFixtures.response(request.url!, 200), Data())
        }

        do {
            _ = try await makeSubmissionService().submit(AuthFixtures.pending(consented: false))
            XCTFail("health data cannot be sent without the permission that covers it")
        } catch {
            XCTAssertEqual(error as? OnboardingError, .serviceError)
        }
        XCTAssertTrue(AuthStubURLProtocol.requests.isEmpty, "nothing left the device")
    }

    // MARK: T052 — retrying is byte-identical

    /// The single most expensive mistake available here is a new key after a
    /// lost response: the server makes a second plan for an account that already
    /// has one. The retry must be indistinguishable from the first attempt.
    func testARetryAfterATimeoutReusesTheIdenticalBodyAndKey() async throws {
        let attempts = Counter()
        AuthStubURLProtocol.stub { request in
            if attempts.next() == 0 {
                return (AuthFixtures.response(request.url!, 504), Data())
            }
            return (
                AuthFixtures.response(request.url!, 200),
                Data(#"{"data": {"onboardingStatus": "complete", "planId": "plan-1"}}"#.utf8)
            )
        }
        let service = makeSubmissionService()
        let pending = AuthFixtures.pending(consented: true)

        do {
            _ = try await service.submit(pending)
            XCTFail("a gateway timeout is not a success")
        } catch {
            XCTAssertEqual(error as? OnboardingError, .serviceError)
        }

        _ = try await service.submit(pending)

        XCTAssertEqual(AuthStubURLProtocol.requests.count, 2)
        XCTAssertEqual(
            AuthStubURLProtocol.requests[0].value(forHTTPHeaderField: "Idempotency-Key"),
            AuthStubURLProtocol.requests[1].value(forHTTPHeaderField: "Idempotency-Key")
        )
        XCTAssertEqual(
            String(decoding: AuthStubURLProtocol.bodies[0], as: UTF8.self),
            String(decoding: AuthStubURLProtocol.bodies[1], as: UTF8.self),
            "byte-identical, so the server can recognise its own answer"
        )
    }

    /// The ambiguous-timeout case, resolved by the server: it already has a
    /// plan. Nothing is resent.
    func testAlreadyCompleteIsReportedForReconciliationRatherThanResubmitted() async throws {
        AuthStubURLProtocol.stub { request in
            (
                AuthFixtures.response(request.url!, 409),
                Data(#"{"error": {"code": "onboarding_already_complete", "message": "x"}}"#.utf8)
            )
        }

        do {
            _ = try await makeSubmissionService().submit(AuthFixtures.pending(consented: true))
            XCTFail("the caller has to hear about this to reconcile")
        } catch {
            XCTAssertEqual(error as? OnboardingError, .alreadyComplete)
        }
        XCTAssertEqual(AuthStubURLProtocol.requests.count, 1, "it is not retried")
    }

    /// A mismatched payload under an existing key means the body changed after
    /// an attempt began. Retrying cannot fix it, and a fresh key would create the
    /// duplicate the key existed to prevent.
    func testAnIdempotencyMismatchStopsWithoutGeneratingANewKey() async throws {
        AuthStubURLProtocol.stub { request in
            (
                AuthFixtures.response(request.url!, 409),
                Data(#"{"error": {"code": "idempotency_payload_mismatch", "message": "x"}}"#.utf8)
            )
        }
        let pending = AuthFixtures.pending(consented: true)

        do {
            _ = try await makeSubmissionService().submit(pending)
            XCTFail("a mismatch is not retryable")
        } catch {
            XCTAssertEqual(error as? OnboardingError, .idempotencyMismatch)
        }

        XCTAssertEqual(AuthStubURLProtocol.requests.count, 1)
        XCTAssertEqual(
            AuthStubURLProtocol.requests[0].value(forHTTPHeaderField: "Idempotency-Key"),
            pending.submission.sessionId.uuidString,
            "still the session's own key: no new one was minted on the way out"
        )
    }

    /// Counts attempts from the protocol's own queue.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func next() -> Int { lock.withLock { defer { value += 1 }; return value } }
    }
}
