//
//  PendingOnboardingStorageTests.swift
//  KaloriasTests
//
//  The sealed payload is the only copy of two minutes of a user's answers
//  between the last question and a confirmed plan. These cover the ways it can
//  be lost: a partial write, a silent decode failure, a cleanup that runs twice,
//  and a locked device being mistaken for an empty one.
//

import XCTest
@testable import Kalorias

nonisolated final class PendingOnboardingStorageTests: XCTestCase {

    private var directory: URL!
    private var storage: PendingOnboardingStorage!

    override func setUp() {
        super.setUp()
        directory = URL.temporaryDirectory.appending(path: "pending-\(UUID().uuidString)")
        storage = PendingOnboardingStorage(directory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        storage = nil
        directory = nil
        super.tearDown()
    }

    // MARK: Fixtures

    private func makeSubmission(sessionId: UUID = UUID()) -> OnboardingSubmission {
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
                ),
                OnboardingSubmission.Entry(
                    questionId: "weight",
                    type: .measure,
                    answer: .measure(
                        MeasureAnswer(
                            canonical: 72.5,
                            unit: "kg",
                            displayUnit: "lb",
                            displayComponents: ["lb": 159.8]
                        )
                    )
                ),
                OnboardingSubmission.Entry(
                    questionId: "birth_date",
                    type: .date,
                    answer: .date(year: 1990, month: 3, day: 7)
                ),
                OnboardingSubmission.Entry(
                    questionId: "conditions",
                    type: .multiChoice,
                    answer: .multi(optionIds: ["none"], customValues: [])
                ),
                OnboardingSubmission.Entry(
                    questionId: "notes",
                    type: .text,
                    answer: .skipped
                ),
            ]
        )
    }

    // MARK: Round trip

    func testAbsentPayloadLoadsAsNil() async throws {
        let loaded = try await storage.load()
        XCTAssertNil(loaded)
    }

    /// The whole sealed value must come back byte-identical, because every retry
    /// resends exactly this body under the same idempotency key.
    func testSealedPayloadRoundTripsExactly() async throws {
        let pending = PendingOnboarding(submission: makeSubmission())
        try await storage.save(pending)

        let loaded = try await storage.load()
        XCTAssertEqual(loaded, pending)
    }

    func testRoundTripPreservesEveryAnswerVariant() async throws {
        let pending = PendingOnboarding(submission: makeSubmission())
        try await storage.save(pending)

        let reloaded = try await storage.load()
        let answers = try XCTUnwrap(reloaded).submission.answers
        XCTAssertEqual(answers.map(\.questionId),
                       ["goal_primary", "weight", "birth_date", "conditions", "notes"])
        XCTAssertEqual(answers[0].answer, .single(optionId: "lose_weight"))
        XCTAssertEqual(answers[2].answer, .date(year: 1990, month: 3, day: 7))
        XCTAssertEqual(answers[3].answer, .multi(optionIds: ["none"], customValues: []))
        XCTAssertEqual(answers[4].answer, .skipped)
        if case let .measure(measure) = answers[1].answer {
            XCTAssertEqual(measure.canonical, 72.5, accuracy: 0.0001)
            XCTAssertEqual(measure.displayUnit, "lb")
        } else {
            XCTFail("The measure answer did not survive the round trip.")
        }
    }

    func testSealedDateTimeRetainsInstantZoneOffsetAndWireBodyAfterRelaunch() async throws {
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-01T12:45:00Z"))
        let zone = try XCTUnwrap(TimeZone(identifier: "Europe/Madrid"))
        let answer = DateTimeAnswer(instant: instant, timeZone: zone)
        let submission = OnboardingSubmission(
            sessionId: UUID(), onboardingId: "plan_v1", schemaVersion: 1,
            contentVersion: 5, locale: "es", startedAt: instant,
            completedAt: instant,
            answers: [.init(questionId: "appointment", type: .date, answer: .dateTime(answer))]
        )
        let pending = PendingOnboarding(submission: submission)
        let before = try OnboardingSubmission.makeEncoder().encode(submission)

        try await storage.save(pending)
        let stored = try await storage.load()
        let reloaded = try XCTUnwrap(stored)

        XCTAssertEqual(reloaded.submission.answers.first?.answer, .dateTime(answer))
        XCTAssertEqual(try OnboardingSubmission.makeEncoder().encode(reloaded.submission), before)
    }

    /// Resealing after a review edit keeps the session identity, so the server
    /// still sees one plan request rather than two.
    func testResavingReplacesThePayloadKeepingItsSessionId() async throws {
        let sessionId = UUID()
        try await storage.save(PendingOnboarding(submission: makeSubmission(sessionId: sessionId)))
        try await storage.save(PendingOnboarding(submission: makeSubmission(sessionId: sessionId)))

        let stored = try await storage.load()
        let loaded = try XCTUnwrap(stored)
        XCTAssertEqual(loaded.submission.sessionId, sessionId)
        XCTAssertEqual(loaded.idempotencyKey, sessionId)
    }

    // MARK: Consent

    func testFreshPayloadHasNoConsentAndIsNotUploadable() async throws {
        let pending = PendingOnboarding(submission: makeSubmission())
        XCTAssertNil(pending.consent)
        XCTAssertFalse(pending.isReadyToUpload(using: AuthFixtures.consentConfiguration))
    }

    func testGrantingConsentPersistsTheReceipt() async throws {
        try await storage.save(PendingOnboarding(submission: makeSubmission()))

        let receipt = ConsentReceipt(
            configuration: AuthFixtures.consentConfiguration,
            grantedAt: Date(timeIntervalSince1970: 5_000)
        )
        let returned = try await storage.grantConsent(receipt)

        XCTAssertEqual(returned.consent, receipt)
        let storedConsent = try await storage.load()?.consent
        XCTAssertEqual(storedConsent, receipt)
        XCTAssertTrue(returned.isReadyToUpload(using: AuthFixtures.consentConfiguration))
    }

    func testGrantingConsentDoesNotAlterTheSubmission() async throws {
        let submission = makeSubmission()
        try await storage.save(PendingOnboarding(submission: submission))

        try await storage.grantConsent(
            ConsentReceipt(
                configuration: AuthFixtures.consentConfiguration,
                grantedAt: Date(timeIntervalSince1970: 5_000)
            )
        )

        let storedSubmission = try await storage.load()?.submission
        XCTAssertEqual(storedSubmission, submission)
    }

    /// A receipt for retired wording cannot authorize an upload.
    func testReceiptForOutdatedVersionsIsNotUploadable() async throws {
        let stale = ConsentReceipt(
            privacyNoticeVersion: "1970-01-01",
            healthDataConsentVersion: "1970-01-01",
            grantedAt: Date(timeIntervalSince1970: 5_000)
        )
        let pending = PendingOnboarding(submission: makeSubmission(), consent: stale)
        XCTAssertFalse(pending.isReadyToUpload(using: AuthFixtures.consentConfiguration))
    }

    func testGrantingConsentWithNothingSealedFails() async {
        do {
            _ = try await storage.grantConsent(
                ConsentReceipt(configuration: AuthFixtures.consentConfiguration, grantedAt: .now)
            )
            XCTFail("Consent was granted against no payload.")
        } catch {
            XCTAssertNotNil(error as? PendingOnboardingStorage.StorageError)
        }
    }

    // MARK: Protection and corruption

    /// The bytes hold a date of birth and a weight; the file must be written
    /// with complete protection, not merely atomically.
    ///
    /// The declared class is asserted unconditionally, and the on-disk attribute
    /// only where the file system actually keeps one. **The iOS Simulator does
    /// not implement data protection**, so it reports `nil` there — a test that
    /// only read the attribute would pass by checking nothing on every simulator
    /// run, which is the most expensive kind of green. The device-level
    /// verification is the quickstart's physical-device pass.
    func testStoredPayloadUsesCompleteProtection() async throws {
        try await storage.save(PendingOnboarding(submission: makeSubmission()))

        XCTAssertEqual(storage.protection, .complete)

        let url = directory.appending(path: PendingOnboardingStorage.fileName)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let onDisk = attributes[.protectionKey] as? FileProtectionType {
            XCTAssertEqual(onDisk, .complete)
        }
    }

    /// Undecodable bytes are reported, not swallowed and not deleted. Silently
    /// dropping them is how a user's answers disappear with nobody noticing.
    func testCorruptedPayloadIsSurfacedAndLeftInPlace() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: PendingOnboardingStorage.fileName)
        try Data("{ not json".utf8).write(to: url)

        do {
            _ = try await storage.load()
            XCTFail("A corrupted payload decoded successfully.")
        } catch {
            XCTAssertEqual(error as? PendingOnboardingStorage.StorageError, .corrupted)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: Cleanup

    func testClearRemovesThePayload() async throws {
        try await storage.save(PendingOnboarding(submission: makeSubmission()))
        await storage.clear()
        let remaining = try await storage.load()
        XCTAssertNil(remaining)
    }

    /// Cleanup after a confirmed submission can be interrupted and resumed.
    func testClearIsIdempotent() async throws {
        try await storage.save(PendingOnboarding(submission: makeSubmission()))
        await storage.clear()
        await storage.clear()
        let remaining = try await storage.load()
        XCTAssertNil(remaining)
    }

    // MARK: Restart recovery

    /// A new storage instance over the same directory — what a relaunch is —
    /// sees exactly what the previous process sealed.
    func testPayloadSurvivesANewStorageInstance() async throws {
        let sessionId = UUID()
        try await storage.save(PendingOnboarding(submission: makeSubmission(sessionId: sessionId)))
        try await storage.grantConsent(
            ConsentReceipt(
                configuration: AuthFixtures.consentConfiguration,
                grantedAt: Date(timeIntervalSince1970: 5_000)
            )
        )

        let relaunched = PendingOnboardingStorage(directory: directory)
        let stored = try await relaunched.load()
        let loaded = try XCTUnwrap(stored)

        XCTAssertEqual(loaded.submission.sessionId, sessionId)
        XCTAssertNotNil(loaded.consent)
        XCTAssertTrue(loaded.isReadyToUpload(using: AuthFixtures.consentConfiguration))
    }
}

// MARK: - Protected draft storage

nonisolated final class ProtectedDraftStorageTests: XCTestCase {

    private var directory: URL!
    private var storage: OnboardingStorage!

    override func setUp() {
        super.setUp()
        directory = URL.temporaryDirectory.appending(path: "onboarding-\(UUID().uuidString)")
        storage = OnboardingStorage(directory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        storage = nil
        directory = nil
        super.tearDown()
    }

    private func makeDraft(contentVersion: Int = 1) -> OnboardingDraft {
        OnboardingDraft(
            sessionId: UUID(),
            onboardingId: "test_v1",
            contentVersion: contentVersion,
            locale: "es",
            startedAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_100),
            answers: ["a": .text("hello")],
            shadowed: ["b": .text("hidden")]
        )
    }

    func testDraftRoundTrips() async throws {
        let draft = makeDraft()
        try await storage.save(draft)
        let stored = try await storage.draft()
        XCTAssertEqual(stored, draft)
    }

    /// The draft holds the same health values as the sealed payload and gets the
    /// same protection. See the payload test above for why the on-disk attribute
    /// is only checked where the file system keeps one.
    func testDraftUsesCompleteProtection() async throws {
        try await storage.save(makeDraft())

        XCTAssertEqual(storage.protected.protection, .complete)

        let url = directory
            .appending(path: "Protected", directoryHint: .isDirectory)
            .appending(path: OnboardingStorage.draftFileName)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let onDisk = attributes[.protectionKey] as? FileProtectionType {
            XCTAssertEqual(onDisk, .complete)
        }
    }

    /// The classification bug this suite exists to catch: a read of a file that
    /// is simply not there must be `nil`, never "unreadable". Getting it wrong
    /// parks the app on the restoring screen forever on a first launch.
    func testAMissingDraftIsAbsentRatherThanUnreadable() async throws {
        let empty = try await storage.draft()
        XCTAssertNil(empty)
    }

    func testDraftIsDroppedWhenTheQuestionnaireHasMovedOn() async throws {
        try await storage.save(makeDraft(contentVersion: 1))

        let newer = try OnboardingFixtures.questionnaire("""
        {
          "onboardingId": "test_v1", "schemaVersion": 1, "contentVersion": 2,
          "locale": "es", "sections": []
        }
        """)

        let mismatched = try await storage.draft(matching: newer)
        XCTAssertNil(mismatched)
        // Still readable in its own right: only the *match* failed.
        let stillReadable = try await storage.draft()
        XCTAssertNotNil(stillReadable)
    }

    func testDraftIsResumedForTheSameQuestionnaire() async throws {
        try await storage.save(makeDraft(contentVersion: 1))

        let same = try OnboardingFixtures.questionnaire("""
        {
          "onboardingId": "test_v1", "schemaVersion": 1, "contentVersion": 1,
          "locale": "es", "sections": []
        }
        """)

        let resumed = try await storage.draft(matching: same)?.answers["a"]
        XCTAssertEqual(resumed, .text("hello"))
    }

    func testCorruptedDraftIsSurfacedRatherThanReadAsAbsent() async throws {
        let protectedDirectory = directory.appending(path: "Protected", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: protectedDirectory, withIntermediateDirectories: true)
        try Data("nonsense".utf8).write(
            to: protectedDirectory.appending(path: OnboardingStorage.draftFileName)
        )

        do {
            _ = try await storage.draft()
            XCTFail("A corrupted draft decoded successfully.")
        } catch {
            XCTAssertEqual(error as? OnboardingStorage.DraftError, .corrupted)
        }
    }

    func testClearDraftIsIdempotent() async throws {
        try await storage.save(makeDraft())
        await storage.clearDraft()
        await storage.clearDraft()
        let clearedDraft = try await storage.draft()
        XCTAssertNil(clearedDraft)
    }
}
