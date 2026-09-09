//
//  OnboardingStoreTests.swift
//  KaloriasTests
//
//  The store's three jobs: getting a questionnaire from somewhere, keeping a
//  draft, and sealing the finished answers **on this device**.
//
//  THE FALLBACK CHAIN IS THE POINT. A failed fetch is not a failed onboarding —
//  the cached copy is tried, then the bundled one, and only then does the user
//  see an error. Getting this wrong means a first launch on a train.
//
//  IT NO LONGER SUBMITS, AND THAT IS ASSERTED, NOT ASSUMED (feature 010). The
//  stub service below has no `submit` at all — the store holds only the fetching
//  half of the boundary, so a test cannot accidentally prove "it did not upload"
//  against a type that could have.
//

import XCTest
@testable import Kalorias

// MARK: - Stubs

private nonisolated final class StubService: OnboardingFetching, @unchecked Sendable {
    var questionnaire: Questionnaire?
    /// The bytes the fetch reports having received, which is what gets cached.
    var payload = Data("{}".utf8)
    var fetchError: (any Error)?
    /// How long the fetch takes to answer, for the first-paint deadline.
    var fetchDelay: Duration = .zero
    /// Every language the fetch was asked for, so a test can assert what the
    /// public request carried — and, by its absence, what it did not.
    private(set) var fetchedLanguages: [String] = []

    func fetchQuestionnaire(languageCode: String) async throws -> FetchedQuestionnaire {
        fetchedLanguages.append(languageCode)
        if fetchDelay > .zero { try await Task.sleep(for: fetchDelay) }
        if let fetchError { throw fetchError }
        guard let questionnaire else { throw OnboardingError.serviceError }
        return FetchedQuestionnaire(questionnaire: questionnaire, payload: payload)
    }
}

// MARK: - Tests

nonisolated final class OnboardingStoreTests: XCTestCase {

    private var directory: URL!

    override func setUp() async throws {
        directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        seals = SealBox()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The payload the store sealed, captured the way the journey receives it.
    private final class SealBox: @unchecked Sendable {
        var sealed: [PendingOnboarding] = []
    }

    private var seals: SealBox!

    @MainActor
    private func makeStore(
        _ service: StubService,
        deadline: Duration = .milliseconds(50)
    ) -> OnboardingStore {
        let box = seals!
        return OnboardingStore(
            service: service,
            storage: storage(),
            pendingStorage: pendingStorage(),
            languageCode: "es",
            firstPaintDeadline: deadline,
            onSealed: { box.sealed.append($0) }
        )
    }

    private func storage() -> OnboardingStorage {
        OnboardingStorage(directory: directory, bundle: .main)
    }

    private func pendingStorage() -> PendingOnboardingStorage {
        PendingOnboardingStorage(
            directory: directory.appending(path: "Protected", directoryHint: .isDirectory)
        )
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
        await first.answer(.single(optionId: "yes"), for: "a")

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
        await first.answer(.single(optionId: "yes"), for: "a")

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

    // MARK: Sealing locally

    /// The end of the chat is a protected local write and nothing else.
    @MainActor
    func testFinishingSealsEveryVisibleAnswerLocally() async throws {
        let service = StubService()
        service.questionnaire = try twoQuestionQuestionnaire()
        let store = makeStore(service)
        await store.load()

        await store.answer(.single(optionId: "yes"), for: "a")
        await store.answer(.text("hello"), for: "b")
        XCTAssertTrue(store.canFinish)

        await store.finish()

        XCTAssertEqual(store.state, .finished)
        XCTAssertEqual(seals.sealed.count, 1)
        XCTAssertEqual(seals.sealed[0].submission.answers.map(\.questionId), ["a", "b"])

        // And it is on disk, not merely in the callback.
        let onDisk = try await pendingStorage().load()
        XCTAssertEqual(onDisk?.submission.sessionId, seals.sealed[0].submission.sessionId)
    }

    /// The whole point of feature 010: no answer reaches the network before an
    /// account exists. The store's service can only fetch, and it was asked for
    /// nothing but the questionnaire.
    @MainActor
    func testFinishingMakesNoRequestAtAll() async throws {
        let service = StubService()
        service.questionnaire = try twoQuestionQuestionnaire()
        let store = makeStore(service)
        await store.load()
        let fetchesAfterLoad = service.fetchedLanguages.count

        await store.answer(.single(optionId: "yes"), for: "a")
        await store.answer(.text("hello"), for: "b")
        await store.finish()

        XCTAssertEqual(service.fetchedLanguages.count, fetchesAfterLoad,
                       "answering and finishing sent nothing")
    }

    /// A sealed payload carries the moment the answers were finished, not the
    /// moment they are eventually uploaded — those can be days apart.
    @MainActor
    func testSealedPayloadKeepsItsOwnTimestampsAndSessionIdentity() async throws {
        let service = StubService()
        service.questionnaire = try twoQuestionQuestionnaire()
        let store = makeStore(service)
        await store.load()
        await store.answer(.single(optionId: "yes"), for: "a")
        await store.answer(.text("hello"), for: "b")

        await store.finish()

        let sealed = try XCTUnwrap(seals.sealed.first).submission
        XCTAssertEqual(sealed.onboardingId, "test_v1")
        XCTAssertEqual(sealed.contentVersion, 1)
        XCTAssertEqual(sealed.locale, "es")
        XCTAssertLessThanOrEqual(sealed.startedAt, sealed.completedAt)
    }

    /// Resealing after a review edit keeps the same session id, so the server
    /// still sees one plan request rather than two.
    @MainActor
    func testResumingAReviewResealsUnderTheSameSessionId() async throws {
        let service = StubService()
        service.questionnaire = try twoQuestionQuestionnaire()

        let first = makeStore(service)
        await first.load()
        await first.answer(.single(optionId: "yes"), for: "a")
        await first.answer(.text("hello"), for: "b")
        await first.finish()
        let original = try XCTUnwrap(seals.sealed.first).submission

        // What the root does when the user taps "Review answers".
        let second = makeStore(service)
        await second.load()
        second.resume(sessionId: original.sessionId, startedAt: original.startedAt)
        await second.answer(.text("changed"), for: "b")
        await second.finish()

        let resealed = try XCTUnwrap(seals.sealed.last).submission
        XCTAssertEqual(resealed.sessionId, original.sessionId)
        XCTAssertEqual(resealed.startedAt, original.startedAt)
        XCTAssertEqual(resealed.answers.last?.answer, .text("changed"))
    }

    /// An incomplete flow cannot be sealed: the key it would claim is the key a
    /// complete payload will need.
    @MainActor
    func testAnIncompleteFlowCannotBeSealed() async throws {
        let service = StubService()
        service.questionnaire = try twoQuestionQuestionnaire()
        let store = makeStore(service)
        await store.load()
        await store.answer(.single(optionId: "yes"), for: "a")

        XCTAssertFalse(store.canFinish)
        await store.finish()

        XCTAssertEqual(store.state, .asking)
        XCTAssertTrue(seals.sealed.isEmpty)
    }

    // MARK: Storage failures

    /// The thread must not advance past an answer the disk does not have. A
    /// regular file where the protected directory belongs makes every write
    /// fail, which is the same shape as a full disk.
    @MainActor
    func testAnAnswerThatCannotBeSavedDoesNotAdvanceTheQuestion() async throws {
        let service = StubService()
        service.questionnaire = try twoQuestionQuestionnaire()
        let store = makeStore(service)
        await store.load()
        let openQuestion = store.flow?.currentQuestion?.id

        blockProtectedDirectory()
        await store.answer(.single(optionId: "yes"), for: "a")

        XCTAssertEqual(store.storageFailure, .answer)
        XCTAssertNil(store.flow?.answers["a"], "nothing was recorded")
        XCTAssertEqual(store.flow?.currentQuestion?.id, openQuestion, "and nothing advanced")
    }

    /// And the message it raises is about the device, not the network — those
    /// call for completely different actions.
    @MainActor
    func testAFailedSealKeepsTheUserInTheChat() async throws {
        let service = StubService()
        service.questionnaire = try twoQuestionQuestionnaire()
        let store = makeStore(service)
        await store.load()
        await store.answer(.single(optionId: "yes"), for: "a")
        await store.answer(.text("hello"), for: "b")

        blockProtectedDirectory()
        await store.finish()

        XCTAssertEqual(store.storageFailure, .seal)
        XCTAssertEqual(store.state, .asking, "access is not shown with nothing behind it")
        XCTAssertTrue(seals.sealed.isEmpty)
    }

    @MainActor
    func testDismissingAStorageFailureClearsIt() async throws {
        let service = StubService()
        service.questionnaire = try twoQuestionQuestionnaire()
        let store = makeStore(service)
        await store.load()

        blockProtectedDirectory()
        await store.answer(.single(optionId: "yes"), for: "a")
        XCTAssertNotNil(store.storageFailure)

        store.dismissStorageFailure()
        XCTAssertNil(store.storageFailure)
    }

    /// Put a regular file where `Protected/` needs to be.
    private func blockProtectedDirectory() {
        let blocked = directory.appending(path: "Protected", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: blocked)
        FileManager.default.createFile(atPath: blocked.path, contents: Data("x".utf8))
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
        await store.answer(.measure(heavier), for: "weight")
        let higher = MeasureAnswer(canonical: 90, unit: "kg", displayUnit: "kg", displayComponents: ["kg": 90])
        await store.answer(.measure(higher), for: "target")

        XCTAssertNotNil(store.warning, "the contradiction is raised")
        XCTAssertNil(store.flow?.answers["target"], "and nothing is recorded yet")

        await store.acceptWarning()

        XCTAssertNil(store.warning)
        XCTAssertEqual(store.flow?.answers["target"], .measure(higher), "insisting is allowed")
    }
}
