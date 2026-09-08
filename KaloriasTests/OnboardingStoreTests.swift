//
//  OnboardingStoreTests.swift
//  KaloriasTests
//
//  The store's three jobs: getting a questionnaire from somewhere, keeping a
//  draft, and submitting once.
//
//  THE FALLBACK CHAIN IS THE POINT. A failed fetch is not a failed onboarding —
//  the cached copy is tried, then the bundled one, and only then does the user
//  see an error. Getting this wrong means a first launch on a train.
//

import XCTest
@testable import Kalorias

// MARK: - Stubs

private nonisolated final class StubService: OnboardingProviding, @unchecked Sendable {
    var questionnaire: Questionnaire?
    /// The bytes the fetch reports having received, which is what gets cached.
    var payload = Data("{}".utf8)
    var fetchError: (any Error)?
    var submitError: (any Error)?
    /// How long the fetch takes to answer, for the first-paint deadline.
    var fetchDelay: Duration = .zero
    private(set) var submissions: [OnboardingSubmission] = []

    func fetchQuestionnaire(languageCode: String) async throws -> FetchedQuestionnaire {
        if fetchDelay > .zero { try await Task.sleep(for: fetchDelay) }
        if let fetchError { throw fetchError }
        guard let questionnaire else { throw OnboardingError.serviceError }
        return FetchedQuestionnaire(questionnaire: questionnaire, payload: payload)
    }

    func submit(_ submission: OnboardingSubmission) async throws {
        submissions.append(submission)
        if let submitError { throw submitError }
    }
}

// MARK: - Tests

nonisolated final class OnboardingStoreTests: XCTestCase {

    private var directory: URL!

    override func setUp() async throws {
        directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    @MainActor
    private func makeStore(
        _ service: StubService,
        deadline: Duration = .milliseconds(50)
    ) -> OnboardingStore {
        OnboardingStore(
            service: service, storage: storage(), languageCode: "es", firstPaintDeadline: deadline
        )
    }

    private func storage() -> OnboardingStorage {
        OnboardingStorage(directory: directory, bundle: .main)
    }

    private func twoQuestionQuestionnaire() throws -> Questionnaire {
        try OnboardingFixtures.questionnaire(
            OnboardingFixtures.wrap(
                sections: OnboardingFixtures.section(
                    id: "s",
                    questions: [OnboardingFixtures.gate("a"), OnboardingFixtures.text("b")]
                        .joined(separator: ",")
                )
            )
        )
    }

    // MARK: Loading

    @MainActor
    func testTheServerCopyIsUsedWhenItAnswers() async throws {
        let service = StubService()
        service.questionnaire = try twoQuestionQuestionnaire()
        let store = makeStore(service)

        await store.load()

        XCTAssertEqual(store.state, .asking)
        XCTAssertEqual(store.flow?.questionnaire.onboardingId, "test_v1")
    }

    @MainActor
    func testAFailedFetchFallsBackToTheBundledCopy() async throws {
        let service = StubService()
        service.fetchError = OnboardingError.noConnection
        let store = makeStore(service)

        await store.load()

        XCTAssertEqual(store.state, .asking, "no network is not a dead end")
        XCTAssertEqual(store.flow?.questionnaire.onboardingId, "plan_v1", "the real bundled questionnaire")
    }

    @MainActor
    func testACachedCopyIsPreferredOverTheBundledOne() async throws {
        // Seeded with the bytes the network would have written, not with a
        // re-encoded model: the app only ever caches what it received, and a
        // synthesised encoder would not produce the same keys the decoder reads.
        let payload = OnboardingFixtures.wrap(
            sections: OnboardingFixtures.section(id: "s", questions: OnboardingFixtures.gate("a"))
        )
        storage().cacheQuestionnaire(Data("{\"data\": \(payload)}".utf8))

        let service = StubService()
        service.fetchError = OnboardingError.timeout
        let store = makeStore(service)

        await store.load()

        XCTAssertEqual(store.flow?.questionnaire.onboardingId, "test_v1")
    }

    /// The cache had no writer at all until the app was actually run: the
    /// service handed back a decoded value, so there were never any bytes to
    /// store, and the fallback below could only ever reach the bundled copy.
    @MainActor
    func testAFetchedQuestionnaireIsCachedForNextTime() async throws {
        let payload = OnboardingFixtures.wrap(
            sections: OnboardingFixtures.section(id: "s", questions: OnboardingFixtures.gate("a"))
        )
        let service = StubService()
        service.questionnaire = try twoQuestionQuestionnaire()
        service.payload = Data("{\"data\": \(payload)}".utf8)

        await makeStore(service).load()

        XCTAssertNotNil(storage().cachedQuestionnaire(), "the bytes the server sent are kept")
    }

    /// A build pointing at a server that is not up must not hold the app's very
    /// first screen on a blank spinner for the whole request timeout.
    @MainActor
    func testASlowServerDoesNotHoldTheFirstPaint() async throws {
        let service = StubService()
        service.questionnaire = try twoQuestionQuestionnaire()
        service.fetchDelay = .seconds(30)

        let store = makeStore(service, deadline: .milliseconds(20))
        await store.load()

        XCTAssertEqual(store.state, .asking, "the chat opened without waiting")
        XCTAssertEqual(store.flow?.questionnaire.onboardingId, "plan_v1", "on the bundled copy")
    }

    /// And the background refresh updates the cache without disturbing the flow
    /// the user is already in.
    @MainActor
    func testTheBackgroundRefreshNeverSwapsTheRunningQuestionnaire() async throws {
        let service = StubService()
        service.questionnaire = try twoQuestionQuestionnaire()
        service.fetchDelay = .seconds(30)
        let store = makeStore(service, deadline: .milliseconds(20))
        await store.load()
        let opened = store.flow?.questionnaire.onboardingId

        service.fetchDelay = .zero
        service.payload = Data("{\"data\": \(OnboardingFixtures.wrap(sections: OnboardingFixtures.section(id: "s", questions: OnboardingFixtures.gate("a"))))}".utf8)
        await store.refreshCacheInBackground()

        XCTAssertEqual(store.flow?.questionnaire.onboardingId, opened, "the chat did not change underneath")
        XCTAssertNotNil(storage().cachedQuestionnaire(), "but next launch gets the new one")
    }

    // MARK: Drafts

    @MainActor
    func testAnswersSurviveARelaunch() async throws {
        let service = StubService()
        service.questionnaire = try twoQuestionQuestionnaire()

        let first = makeStore(service)
        await first.load()
        first.answer(.single(optionId: "yes"), for: "a")

        let second = makeStore(service)
        await second.load()

        XCTAssertEqual(second.flow?.answers["a"], .single(optionId: "yes"))
        XCTAssertEqual(second.flow?.currentQuestion?.id, "b")
    }

    /// A draft is pinned to the content it was answered against. Replaying it
    /// over reworded questions is worse than losing two minutes of typing.
    @MainActor
    func testADraftFromAnotherContentVersionIsDiscarded() async throws {
        let service = StubService()
        service.questionnaire = try twoQuestionQuestionnaire()
        let first = makeStore(service)
        await first.load()
        first.answer(.single(optionId: "yes"), for: "a")

        // The server has moved on.
        let moved = try OnboardingFixtures.questionnaire(
            OnboardingFixtures.wrap(
                sections: OnboardingFixtures.section(id: "s", questions: OnboardingFixtures.gate("a"))
            )
            .replacingOccurrences(of: "\"contentVersion\": 1", with: "\"contentVersion\": 2")
        )
        service.questionnaire = moved

        let second = makeStore(service)
        await second.load()

        XCTAssertNil(second.flow?.answers["a"], "answers to version 1 do not carry over")
    }

    // MARK: Submitting

    @MainActor
    func testSubmittingSendsEveryVisibleAnswerAndClearsTheDraft() async throws {
        let service = StubService()
        service.questionnaire = try twoQuestionQuestionnaire()
        let store = makeStore(service)
        await store.load()

        store.answer(.single(optionId: "yes"), for: "a")
        store.answer(.text("hello"), for: "b")
        XCTAssertTrue(store.canSubmit)

        await store.submit()

        XCTAssertEqual(store.state, .finished)
        XCTAssertEqual(service.submissions.count, 1)
        XCTAssertEqual(service.submissions[0].answers.map(\.questionId), ["a", "b"])

        // The draft is gone, so a relaunch does not reopen a finished flow.
        let next = makeStore(service)
        await next.load()
        XCTAssertNil(next.flow?.answers["a"])
    }

    /// A failed submission keeps every answer and reuses the same session id, so
    /// the retry reads as a repeat rather than as a second person.
    @MainActor
    func testAFailedSubmissionCanBeRetriedUnderTheSameSessionId() async throws {
        let service = StubService()
        service.questionnaire = try twoQuestionQuestionnaire()
        service.submitError = OnboardingError.timeout
        let store = makeStore(service)
        await store.load()
        store.answer(.single(optionId: "yes"), for: "a")
        store.answer(.text("hello"), for: "b")

        await store.submit()
        XCTAssertEqual(store.state, .failed(.timeout))

        store.dismissFailure()
        XCTAssertEqual(store.state, .asking)
        XCTAssertEqual(store.flow?.answers.count, 2, "nothing was lost")

        service.submitError = nil
        await store.submit()

        XCTAssertEqual(service.submissions.count, 2)
        XCTAssertEqual(service.submissions[0].sessionId, service.submissions[1].sessionId)
    }

    // MARK: Cross-checks

    @MainActor
    func testAContradictedAnswerWaitsForTheUserInsteadOfBeingRecorded() async throws {
        let json = OnboardingFixtures.wrap(
            sections: OnboardingFixtures.section(
                id: "s",
                questions: [
                    OnboardingFixtures.weightMeasure,
                    """
                    { "id": "target", "type": "measure", "prompt": ["target"],
                      "measure": { "widget": "wheel", "canonicalUnit": "kg", "defaultUnit": "kg",
                        "units": [{ "id": "kg", "label": "kg", "components": [
                          { "id": "kg", "min": 30, "max": 250, "step": 0.1, "default": 70,
                            "decimals": 1, "toCanonical": 1 }] }] },
                      "crossChecks": [{ "severity": "warning", "rule": "lessThan", "compareTo": "weight",
                        "message": "Higher than your current weight." }] }
                    """,
                ].joined(separator: ",")
            )
        )
        let service = StubService()
        service.questionnaire = try OnboardingFixtures.questionnaire(json)
        let store = makeStore(service)
        await store.load()

        let heavier = MeasureAnswer(canonical: 80, unit: "kg", displayUnit: "kg", displayComponents: ["kg": 80])
        store.answer(.measure(heavier), for: "weight")
        let higher = MeasureAnswer(canonical: 90, unit: "kg", displayUnit: "kg", displayComponents: ["kg": 90])
        store.answer(.measure(higher), for: "target")

        XCTAssertNotNil(store.warning, "the contradiction is raised")
        XCTAssertNil(store.flow?.answers["target"], "and nothing is recorded yet")

        store.acceptWarning()

        XCTAssertNil(store.warning)
        XCTAssertEqual(store.flow?.answers["target"], .measure(higher), "insisting is allowed")
    }
}
