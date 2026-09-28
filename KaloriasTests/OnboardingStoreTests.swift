//
//  OnboardingStoreTests.swift
//  KaloriasTests
//
//  The store's three jobs: fetching the questionnaire, keeping a
//  draft, and sealing the finished answers **on this device**.
//
//  A failed fetch leaves the questionnaire unavailable. Saved answers survive
//  and resume once the same questionnaire arrives from the backend.
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
    var fetchError: (any Error)?
    /// Every language the fetch was asked for, so a test can assert what the
    /// public request carried — and, by its absence, what it did not.
    private(set) var fetchedLanguages: [String] = []

    func fetchQuestionnaire(languageCode: String) async throws -> FetchedQuestionnaire {
        fetchedLanguages.append(languageCode)
        if let fetchError { throw fetchError }
        guard let questionnaire else { throw OnboardingError.serviceError }
        return FetchedQuestionnaire(questionnaire: questionnaire)
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
    private func makeStore(_ service: StubService) -> OnboardingStore {
        let box = seals!
        return OnboardingStore(
            service: service,
            storage: storage(),
            pendingStorage: pendingStorage(),
            languageCode: "es",
            onSealed: { box.sealed.append($0) }
        )
    }

    private func storage() -> OnboardingStorage {
        OnboardingStorage(directory: directory)
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
    func testAFailedFetchShowsAnErrorEvenWhenALegacyCacheExists() async throws {
        let questionnaire = OnboardingFixtures.wrap(
            sections: OnboardingFixtures.section(id: "s", questions: OnboardingFixtures.gate("a"))
        )
        try Data("{\"data\": \(questionnaire)}".utf8).write(
            to: directory.appending(path: "questionnaire.json")
        )
        let service = StubService()
        service.fetchError = OnboardingError.noConnection
        let store = makeStore(service)

        await store.load()

        XCTAssertEqual(store.state, .failed(.noConnection))
        XCTAssertNil(store.flow)
        XCTAssertEqual(service.fetchedLanguages, ["es"])
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appending(path: "questionnaire.json").path
        ))
    }

    @MainActor
    func testRetryLoadsTheQuestionnaireAfterANetworkFailure() async throws {
        let service = StubService()
        service.fetchError = OnboardingError.timeout
        let store = makeStore(service)
        await store.load()
        XCTAssertEqual(store.state, .failed(.timeout))

        service.fetchError = nil
        service.questionnaire = try twoQuestionQuestionnaire()
        await store.load()

        XCTAssertEqual(store.state, .asking)
        XCTAssertEqual(store.flow?.questionnaire.onboardingId, "test_v1")
        XCTAssertEqual(service.fetchedLanguages, ["es", "es"])
    }

    @MainActor
    func testAnIncompatibleQuestionnaireBlocksLoadingAndCannotBeRetried() async throws {
        let service = StubService()
        service.fetchError = OnboardingError.updateRequired
        let store = makeStore(service)

        await store.load()

        XCTAssertEqual(store.state, .updateRequired)
        XCTAssertNil(store.flow)
        await store.load()
        XCTAssertEqual(service.fetchedLanguages, ["es"])
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

    @MainActor
    func testDateTimeAnswerSurvivesARelaunchWithItsOriginalZone() async throws {
        let service = StubService()
        let dateQuestion = """
        { "id": "appointment", "type": "date", "prompt": ["When?"],
          "date": { "mode": "dateTime", "minDate": "2020-01-01", "maxDate": "2030-01-01" } }
        """
        service.questionnaire = try OnboardingFixtures.questionnaire(
            OnboardingFixtures.wrap(
                sections: OnboardingFixtures.section(
                    id: "s",
                    questions: [OnboardingFixtures.gate("a"), dateQuestion, OnboardingFixtures.text("b")]
                        .joined(separator: ",")
                )
            )
        )
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-01T12:45:00Z"))
        let zone = try XCTUnwrap(TimeZone(identifier: "Europe/Madrid"))
        let answer = DateTimeAnswer(instant: instant, timeZone: zone)

        let first = makeStore(service)
        await first.load()
        await first.answer(.single(optionId: "yes"), for: "a")
        await first.answer(.dateTime(answer), for: "appointment")

        let second = makeStore(service)
        await second.load()

        XCTAssertEqual(second.flow?.answers["appointment"], .dateTime(answer))
        XCTAssertEqual(second.flow?.currentQuestion?.id, "b")
    }

    @MainActor
    func testSavedAnswersSurviveAnOfflineRelaunchAndResumeAfterFetch() async throws {
        let service = StubService()
        service.questionnaire = try twoQuestionQuestionnaire()
        let first = makeStore(service)
        await first.load()
        await first.answer(.single(optionId: "yes"), for: "a")
        let savedDraft = try await storage().draft()
        let savedSession = try XCTUnwrap(savedDraft?.sessionId)

        service.fetchError = OnboardingError.noConnection
        let second = makeStore(service)
        await second.load()
        XCTAssertEqual(second.state, .failed(.noConnection))
        XCTAssertNil(second.flow)
        let draftDuringOutage = try await storage().draft()
        XCTAssertEqual(draftDuringOutage?.sessionId, savedSession)

        service.fetchError = nil
        await second.load()
        XCTAssertEqual(second.flow?.answers["a"], .single(optionId: "yes"))
        XCTAssertEqual(second.flow?.currentQuestion?.id, "b")
        let resumedDraft = try await storage().draft()
        XCTAssertEqual(resumedDraft?.sessionId, savedSession)
    }

    @MainActor
    func testUpdateRequiredPreservesSavedAnswersWithoutOpeningTheOldFlow() async throws {
        let service = StubService()
        service.questionnaire = try twoQuestionQuestionnaire()
        let first = makeStore(service)
        await first.load()
        await first.answer(.single(optionId: "yes"), for: "a")
        let originalDraftValue = try await storage().draft()
        let originalDraft = try XCTUnwrap(originalDraftValue)

        service.fetchError = OnboardingError.unsupportedSchema(version: 2)
        let second = makeStore(service)
        await second.load()

        XCTAssertEqual(second.state, .updateRequired)
        XCTAssertNil(second.flow)
        let savedDraftValue = try await storage().draft()
        let savedDraft = try XCTUnwrap(savedDraftValue)
        XCTAssertEqual(savedDraft.sessionId, originalDraft.sessionId)
        XCTAssertEqual(savedDraft.answers["a"], .single(optionId: "yes"))
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
