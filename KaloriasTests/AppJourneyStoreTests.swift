//
//  AppJourneyStoreTests.swift
//  KaloriasTests
//
//  The bootstrap resolution table from `data-model.md`, asserted row by row.
//
//  EVERY ROW IS A RELAUNCH THAT ALREADY WENT WRONG ONCE. The table exists
//  because a boolean flag answered "has this device finished the chat?" and the
//  real question has five parts; each row below is a state a real device can be
//  in when it is next launched, and getting one wrong either restarts a finished
//  onboarding, offers a second account to someone who has one, or renders an
//  authenticated shell over an account the server may already have deleted.
//
//  "COULD NOT READ" IS TESTED AGAINST A REAL UNREADABLE FILE. The locked-device
//  row is exercised by revoking POSIX read permission rather than by stubbing
//  the store: `ProtectedFileStore` classifies any non-missing read failure as
//  `.unavailableWhileLocked`, and a double that returned the error directly
//  would prove the journey handles a value it was handed, not that a genuinely
//  unreadable file produces it.
//
//  NOTHING HERE REACHES APPLE OR A BACKEND. The doubles come from
//  `AuthFixtures.swift`; the session actor is the real `AuthSessionCoordinator`
//  over an in-memory Keychain, so the paired-write ordering the phase depends on
//  is the production one and not a restatement of it.
//

import XCTest
@testable import Kalorias

// MARK: - Doubles

/// Records the order of credential writes, so "session, then marker, then a
/// phase" can be asserted as an order rather than as an end state — the end
/// state is identical whichever way round the two writes happened.
private nonisolated final class OrderedCredentialStore: CredentialStoring, @unchecked Sendable {

    private let inner: InMemoryCredentialStore
    private let lock = NSLock()
    private var _log: [String] = []

    var log: [String] { lock.withLock { _log } }
    var storedSession: AuthSession? { inner.storedSession }
    var storedKnownAccount: KnownAccount? { inner.storedKnownAccount }
    var storedDeletionAttempt: AccountDeletionAttempt? { inner.storedDeletionAttempt }

    init(_ inner: InMemoryCredentialStore) { self.inner = inner }

    private func record(_ entry: String) { lock.withLock { _log.append(entry) } }

    func loadSession() throws -> AuthSession? { try inner.loadSession() }
    func saveSession(_ session: AuthSession) throws {
        record("session")
        try inner.saveSession(session)
    }
    func deleteSession() throws {
        record("deleteSession")
        try inner.deleteSession()
    }
    func loadKnownAccount() throws -> KnownAccount? { try inner.loadKnownAccount() }
    func saveKnownAccount(_ account: KnownAccount) throws {
        record("knownAccount")
        try inner.saveKnownAccount(account)
    }
    func deleteKnownAccount() throws {
        record("deleteKnownAccount")
        try inner.deleteKnownAccount()
    }
    func loadDeletionAttempt() throws -> AccountDeletionAttempt? { try inner.loadDeletionAttempt() }
    func saveDeletionAttempt(_ attempt: AccountDeletionAttempt) throws {
        record("deletionAttempt")
        try inner.saveDeletionAttempt(attempt)
    }
    func deleteDeletionAttempt() throws {
        record("deleteDeletionAttempt")
        try inner.deleteDeletionAttempt()
    }
}

/// A fetching-only onboarding service, so a test that drives the real
/// `OnboardingStore` cannot accidentally reach a submission path.
private nonisolated final class SilentQuestionnaireService: OnboardingFetching, @unchecked Sendable {
    var questionnaire: Questionnaire?

    func fetchQuestionnaire(languageCode: String) async throws -> FetchedQuestionnaire {
        guard let questionnaire else { throw OnboardingError.serviceError }
        return FetchedQuestionnaire(questionnaire: questionnaire)
    }
}

// MARK: - Tests

nonisolated final class AppJourneyStoreTests: XCTestCase {

    private var directory: URL!
    private var protectedDirectory: URL!

    override func setUp() async throws {
        directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        protectedDirectory = directory.appending(path: "Protected", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        // A locked-device test leaves a file with no read permission behind.
        if let protectedDirectory {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: protectedDirectory.appending(path: PendingOnboardingStorage.fileName).path
            )
        }
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Composition

    private struct Harness {
        let store: AppJourneyStore
        let credentials: OrderedCredentialStore
        let auth: StubAuthService
        let submissions: StubSubmissionService
        let credentialState: StubCredentialStateChecker
        let localData: SpyLocalDataClearer
        let onboardingStorage: OnboardingStorage
        let pendingStorage: PendingOnboardingStorage
    }

    @MainActor
    private func makeHarness(
        session: AuthSession? = nil,
        knownAccount: KnownAccount? = nil,
        deletionAttempt: AccountDeletionAttempt? = nil,
        credentialState: AppleCredentialState = .authorized,
        keychainFailure: (any Error)? = nil,
        consentConfiguration: ConsentConfiguration? = AuthFixtures.consentConfiguration
    ) -> Harness {
        let inner = InMemoryCredentialStore(
            session: session,
            knownAccount: knownAccount,
            deletionAttempt: deletionAttempt
        )
        inner.failure = keychainFailure
        let credentials = OrderedCredentialStore(inner)
        let auth = StubAuthService()
        let submissions = StubSubmissionService()
        let state = StubCredentialStateChecker(state: credentialState)
        let localData = SpyLocalDataClearer()
        let onboardingStorage = OnboardingStorage(directory: directory)
        let pendingStorage = PendingOnboardingStorage(directory: protectedDirectory)

        let store = AppJourneyStore(
            credentials: credentials,
            sessions: AuthSessionCoordinator(credentials: credentials, service: auth),
            auth: auth,
            submissions: submissions,
            credentialState: state,
            onboardingStorage: onboardingStorage,
            pendingStorage: pendingStorage,
            localData: localData,
            consentConfiguration: consentConfiguration
        )
        return Harness(
            store: store,
            credentials: credentials,
            auth: auth,
            submissions: submissions,
            credentialState: state,
            localData: localData,
            onboardingStorage: onboardingStorage,
            pendingStorage: pendingStorage
        )
    }

    private func writePending(consented: Bool = false) async throws -> PendingOnboarding {
        let pending = AuthFixtures.pending(consented: consented)
        try await PendingOnboardingStorage(directory: protectedDirectory).save(pending)
        return pending
    }

    private func writeDraft() async throws {
        try await OnboardingStorage(directory: directory).save(
            OnboardingDraft(
                sessionId: UUID(),
                onboardingId: "plan_v1",
                contentVersion: 5,
                startedAt: Date(timeIntervalSince1970: 1_000),
                answers: [:],
                shadowed: [:]
            )
        )
    }

    private var pendingFileURL: URL {
        protectedDirectory.appending(path: PendingOnboardingStorage.fileName)
    }

    // MARK: - Row: a confirmed deletion outranks everything

    /// The first row of the table, and the only one with no exceptions: an
    /// outstanding attempt means the server may already have removed the
    /// account, so authenticated content stays hidden even over a session that
    /// still validates and reports `complete`.
    @MainActor
    func testAnOutstandingDeletionAttemptOutranksAValidCompleteSession() async throws {
        _ = try await writePending()
        let harness = makeHarness(
            session: AuthFixtures.session(onboardingStatus: .complete),
            knownAccount: KnownAccount(
                userId: "user-1",
                appleUserIdentifier: "apple-sub-1",
                onboardingStatus: .complete
            ),
            deletionAttempt: AccountDeletionAttempt(
                operationId: UUID(),
                presentedAccessToken: "access-1",
                ownerUserID: "user-1",
                confirmedAt: Date(timeIntervalSince1970: 5_000)
            )
        )

        await harness.store.bootstrap()

        XCTAssertEqual(harness.store.phase, .deletingAccount)
        XCTAssertNil(harness.store.activeUserID, "no owner is active while a deletion is outstanding")
        XCTAssertFalse(harness.store.isDeleting, "restored, not resumed: the replay waits for Continue")
        XCTAssertTrue(harness.auth.deleteCalls.isEmpty, "bootstrap sends nothing on its own")
    }

    // MARK: - Rows: a live session, the server's status decides

    @MainActor
    func testACompleteSessionIsReadyAndDiscardsTheRedundantLocalCopy() async throws {
        _ = try await writePending(consented: true)
        try await writeDraft()
        let harness = makeHarness(session: AuthFixtures.session(onboardingStatus: .complete))

        await harness.store.bootstrap()

        XCTAssertEqual(harness.store.phase, .ready)
        XCTAssertEqual(harness.store.activeUserID, "user-1")
        XCTAssertNil(harness.store.pending, "the redundant payload goes once `complete` is durable")
        let onDisk = try await harness.pendingStorage.load()
        XCTAssertNil(onDisk)
        let draft = try await harness.onboardingStorage.draft()
        XCTAssertNil(draft)
        XCTAssertTrue(harness.submissions.submissions.isEmpty, "a complete account is never sent a payload")
    }

    @MainActor
    func testARequiredSessionWithAnUnconsentedPayloadAsksForConsent() async throws {
        _ = try await writePending(consented: false)
        let harness = makeHarness(session: AuthFixtures.session(onboardingStatus: .required))

        await harness.store.bootstrap()

        XCTAssertEqual(harness.store.phase, .consent)
        XCTAssertNotNil(harness.store.pending)
        XCTAssertTrue(harness.submissions.submissions.isEmpty)
    }

    @MainActor
    func testARequiredSessionWithAConsentedPayloadWaitsOnTheFinalizationScreen() async throws {
        _ = try await writePending(consented: true)
        let harness = makeHarness(session: AuthFixtures.session(onboardingStatus: .required))

        await harness.store.bootstrap()

        XCTAssertEqual(harness.store.phase, .finalizing)
        XCTAssertTrue(harness.store.finalizationAwaitsUser, "recoverable/manual-retry mode after relaunch")
    }

    /// The returning-account-on-a-new-install case: an account that still needs a
    /// plan, with nothing sealed on this device, builds one — it does not sit on
    /// a finalization screen with nothing to send.
    @MainActor
    func testARequiredSessionWithNoPayloadRebuildsTheOnboarding() async throws {
        let harness = makeHarness(session: AuthFixtures.session(onboardingStatus: .required))

        await harness.store.bootstrap()

        XCTAssertEqual(harness.store.phase, .onboarding)
        XCTAssertEqual(harness.store.activeUserID, "user-1", "already authenticated, only the plan is missing")
    }

    /// A lost paired write leaves a valid session with no marker. Rebuilding it
    /// here is what stops a later session loss from restarting a finished user's
    /// first run.
    @MainActor
    func testAValidSessionRebuildsAMissingKnownAccountMarker() async throws {
        let harness = makeHarness(
            session: AuthFixtures.session(onboardingStatus: .complete),
            knownAccount: nil
        )

        await harness.store.bootstrap()

        let marker = harness.credentials.storedKnownAccount
        XCTAssertEqual(marker?.userId, "user-1")
        XCTAssertEqual(marker?.appleUserIdentifier, "apple-sub-1")
        XCTAssertEqual(marker?.onboardingStatus, .complete)
    }

    // MARK: - Rows: no live session

    @MainActor
    func testAKnownCompleteAccountWithNoSessionGoesToAccess() async throws {
        let harness = makeHarness(
            session: nil,
            knownAccount: KnownAccount(
                userId: "user-1",
                appleUserIdentifier: "apple-sub-1",
                onboardingStatus: .complete
            )
        )

        await harness.store.bootstrap()

        XCTAssertEqual(harness.store.phase, .access, "a known account never restarts first run")
        XCTAssertNil(harness.store.activeUserID)
    }

    @MainActor
    func testAKnownRequiredAccountWithAPayloadGoesToAccessAndKeepsIt() async throws {
        let pending = try await writePending(consented: true)
        let harness = makeHarness(
            session: nil,
            knownAccount: KnownAccount(
                userId: "user-1",
                appleUserIdentifier: "apple-sub-1",
                onboardingStatus: .required
            )
        )

        await harness.store.bootstrap()

        XCTAssertEqual(harness.store.phase, .access)
        XCTAssertEqual(harness.store.pending?.submission.sessionId, pending.submission.sessionId)
        XCTAssertNotNil(harness.store.pending?.consent, "the receipt is preserved with the payload")
    }

    @MainActor
    func testAKnownRequiredAccountWithNoPayloadStillGoesToAccessRatherThanOnboarding() async throws {
        let harness = makeHarness(
            session: nil,
            knownAccount: KnownAccount(
                userId: "user-1",
                appleUserIdentifier: "apple-sub-1",
                onboardingStatus: .required
            )
        )

        await harness.store.bootstrap()

        XCTAssertEqual(harness.store.phase, .access,
                       "the status is resumed after reauthentication, not guessed at now")
    }

    @MainActor
    func testNoAccountWithASealedPayloadGoesToAccess() async throws {
        _ = try await writePending()
        let harness = makeHarness()

        await harness.store.bootstrap()

        XCTAssertEqual(harness.store.phase, .access)
        XCTAssertNotNil(harness.store.pending)
    }

    @MainActor
    func testAGenuineFirstRunStartsTheOnboarding() async throws {
        let harness = makeHarness()

        await harness.store.bootstrap()

        XCTAssertEqual(harness.store.phase, .onboarding)
        XCTAssertNil(harness.store.pending)
        XCTAssertNil(harness.store.localDataError)
    }

    // MARK: - Additional resolution rules

    /// A locked device waits. Treating an unreadable file as an absent one sends
    /// a user who already answered back to question one.
    @MainActor
    func testAnUnreadableProtectedPayloadKeepsTheAppRestoring() async throws {
        _ = try await writePending()
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: pendingFileURL.path
        )
        let harness = makeHarness()

        await harness.store.bootstrap()

        XCTAssertEqual(harness.store.phase, .restoring, "cannot read yet is not there is nothing there")
        XCTAssertNil(harness.store.localDataError, "waiting is not a failure to report")
        XCTAssertTrue(FileManager.default.fileExists(atPath: pendingFileURL.path),
                      "an unreadable payload is never removed")
    }

    /// Damaged bytes are surfaced, never silently deleted and never sent.
    @MainActor
    func testACorruptedProtectedPayloadIsReportedAndKept() async throws {
        _ = try await writePending()
        try Data("not json".utf8).write(to: pendingFileURL)
        let harness = makeHarness()

        await harness.store.bootstrap()

        XCTAssertEqual(harness.store.localDataError, .corruptedOnboardingData)
        XCTAssertNil(harness.store.pending)
        XCTAssertTrue(FileManager.default.fileExists(atPath: pendingFileURL.path),
                      "corrupt answers are the user's to decide about")
        XCTAssertTrue(harness.submissions.submissions.isEmpty)
    }

    /// Guessing at an unreadable Keychain means either exposing an account's data
    /// or offering to create a duplicate of it.
    @MainActor
    func testAnUnreadableKeychainStaysRestoringAndSaysSo() async throws {
        let harness = makeHarness(keychainFailure: AuthError.serviceUnavailable)

        await harness.store.bootstrap()

        XCTAssertEqual(harness.store.phase, .restoring)
        XCTAssertEqual(harness.store.localDataError, .unreadableCredentials)
    }

    // MARK: - T024: onboarding publishes access only behind a durable write

    /// The write is the transition. The access screen must never appear with
    /// nothing behind it, so the journey is driven here by the real
    /// `OnboardingStore` rather than by calling the intent directly.
    @MainActor
    func testAccessAppearsOnlyAfterTheSealedPayloadIsOnDisk() async throws {
        let harness = makeHarness()
        await harness.store.bootstrap()
        XCTAssertEqual(harness.store.phase, .onboarding)

        let service = SilentQuestionnaireService()
        service.questionnaire = try twoQuestionQuestionnaire()
        let journey = harness.store
        let onboarding = OnboardingStore(
            service: service,
            storage: harness.onboardingStorage,
            pendingStorage: harness.pendingStorage,
            languageCode: "es",
            onSealed: { journey.onboardingDidSeal($0) }
        )
        await onboarding.load()
        await onboarding.answer(.single(optionId: "yes"), for: "a")
        await onboarding.answer(.text("hello"), for: "b")

        await onboarding.finish()

        XCTAssertEqual(harness.store.phase, .access)
        let onDisk = try await harness.pendingStorage.load()
        XCTAssertNotNil(onDisk, "the payload was durable before the phase changed")
        XCTAssertEqual(onDisk?.submission.sessionId, harness.store.pending?.submission.sessionId)
    }

    /// A seal that could not be written leaves the user in the chat with their
    /// answers, not on an access screen backed by nothing.
    @MainActor
    func testAFailedSealLeavesThePhaseOnOnboarding() async throws {
        let harness = makeHarness()
        await harness.store.bootstrap()

        // A regular file where the protected directory must be: the write cannot
        // land, and the store has to treat that as a failure rather than proceed.
        let blocked = directory.appending(path: "Blocked", directoryHint: .isDirectory)
        try Data().write(to: blocked)

        let service = SilentQuestionnaireService()
        service.questionnaire = try twoQuestionQuestionnaire()
        let journey = harness.store
        let onboarding = OnboardingStore(
            service: service,
            storage: harness.onboardingStorage,
            pendingStorage: PendingOnboardingStorage(directory: blocked),
            languageCode: "es",
            onSealed: { journey.onboardingDidSeal($0) }
        )
        await onboarding.load()
        await onboarding.answer(.single(optionId: "yes"), for: "a")
        await onboarding.answer(.text("hello"), for: "b")

        await onboarding.finish()

        XCTAssertEqual(onboarding.storageFailure, .seal)
        XCTAssertEqual(harness.store.phase, .onboarding, "no durable payload, no access screen")
        XCTAssertNil(harness.store.pending)
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

    // MARK: - T036: access transitions are driven by the persisted backend status

    @MainActor
    func testRegistrationCommitsTheSessionThenTheMarkerThenPublishesThePhase() async throws {
        _ = try await writePending(consented: false)
        let harness = makeHarness()
        await harness.store.bootstrap()
        harness.auth.authenticateResult = .success(AuthFixtures.authResponse(status: .required))

        await harness.store.signIn(with: AuthFixtures.appleCredential())

        XCTAssertEqual(harness.credentials.log, ["session", "knownAccount"],
                       "the marker never lands before the session it is derived from")
        XCTAssertEqual(harness.store.phase, .consent, "the phase is published only after both writes")
        XCTAssertEqual(harness.credentials.storedSession?.userId, "user-1")
        XCTAssertEqual(harness.credentials.storedKnownAccount?.userId, "user-1")
    }

    @MainActor
    func testAServerCompleteStatusAtRegistrationGoesStraightToReady() async throws {
        _ = try await writePending(consented: true)
        let harness = makeHarness()
        await harness.store.bootstrap()
        harness.auth.authenticateResult = .success(AuthFixtures.authResponse(status: .complete))

        await harness.store.signIn(with: AuthFixtures.appleCredential())

        XCTAssertEqual(harness.store.phase, .ready)
        XCTAssertTrue(harness.submissions.submissions.isEmpty,
                      "an existing plan is never overwritten by a local payload")
        let onDisk = try await harness.pendingStorage.load()
        XCTAssertNil(onDisk, "the redundant copy is discarded, not sent")
    }

    @MainActor
    func testAServerRequiredStatusWithNoPayloadSendsTheUserToOnboarding() async throws {
        let harness = makeHarness()
        await harness.store.bootstrap()
        harness.auth.authenticateResult = .success(AuthFixtures.authResponse(status: .required))

        await harness.store.signIn(with: AuthFixtures.appleCredential())

        XCTAssertEqual(harness.store.phase, .onboarding)
        XCTAssertEqual(harness.store.activeUserID, "user-1")
    }

    /// The one automatic upload: fresh consent in this process.
    @MainActor
    func testAServerRequiredStatusWithAConsentedPayloadFinalizesImmediately() async throws {
        _ = try await writePending(consented: true)
        let harness = makeHarness()
        await harness.store.bootstrap()
        harness.auth.authenticateResult = .success(AuthFixtures.authResponse(status: .required))

        await harness.store.signIn(with: AuthFixtures.appleCredential())

        XCTAssertEqual(harness.submissions.submissions.count, 1)
        XCTAssertEqual(harness.store.phase, .ready)
        XCTAssertEqual(harness.credentials.storedSession?.onboardingStatus, .complete,
                       "the status is durable before the local files are removed")
    }

    @MainActor
    func testAppleRateLimitBlocksAnotherExchangeUntilRetryAfter() async throws {
        _ = try await writePending(consented: false)
        let harness = makeHarness()
        await harness.store.bootstrap()
        harness.auth.authenticateResult = .failure(AuthError.rateLimited(retryAfter: 20))

        await harness.store.signIn(with: AuthFixtures.appleCredential())
        await harness.store.signIn(with: AuthFixtures.appleCredential())

        XCTAssertEqual(harness.auth.authenticateCalls.count, 1)
        XCTAssertNotNil(harness.store.accessSecondsUntilRetry)
        XCTAssertEqual(harness.store.accessError, .rateLimited(retryAfter: 20))
    }

    // MARK: - T049: relaunch at each boundary

    @MainActor
    func testMissingLegalConfigurationCannotMintAReceiptOrUploadAnswers() async throws {
        _ = try await writePending(consented: false)
        let harness = makeHarness(
            session: AuthFixtures.session(onboardingStatus: .required),
            consentConfiguration: nil
        )
        await harness.store.bootstrap()

        await harness.store.acceptHealthDataConsent()

        XCTAssertEqual(harness.store.consentError, .notConfigured)
        XCTAssertNil(harness.store.pending?.consent)
        XCTAssertTrue(harness.submissions.submissions.isEmpty)
        XCTAssertEqual(harness.store.phase, .consent)
    }

    @MainActor
    func testConsentReceiptUsesTheExactConfiguredVersions() async throws {
        _ = try await writePending(consented: false)
        let harness = makeHarness(session: AuthFixtures.session(onboardingStatus: .required))
        await harness.store.bootstrap()

        await harness.store.acceptHealthDataConsent()

        let sent = try XCTUnwrap(harness.submissions.submissions.first?.consent)
        XCTAssertEqual(
            sent.privacyNoticeVersion,
            AuthFixtures.consentConfiguration.privacyNoticeVersion
        )
        XCTAssertEqual(
            sent.healthDataConsentVersion,
            AuthFixtures.consentConfiguration.healthDataConsentVersion
        )
    }

    /// Before Apple: answers sealed, no account. The chat is not restarted and
    /// no account is created on the user's behalf.
    @MainActor
    func testRelaunchBeforeAppleResumesAtAccessWithTheAnswersIntact() async throws {
        let pending = try await writePending()
        let harness = makeHarness()

        await harness.store.bootstrap()

        XCTAssertEqual(harness.store.phase, .access)
        XCTAssertEqual(harness.store.pending?.submission.sessionId, pending.submission.sessionId)
        XCTAssertTrue(harness.auth.authenticateCalls.isEmpty)
    }

    /// After Apple but before the auth response: nothing was committed, so the
    /// device looks exactly as it did before the tap.
    @MainActor
    func testRelaunchAfterAppleButBeforeTheAuthResponseIsIndistinguishableFromBeforeIt() async throws {
        _ = try await writePending()
        let first = makeHarness()
        await first.store.bootstrap()
        first.auth.authenticateResult = .failure(AuthError.noConnection)

        await first.store.signIn(with: AuthFixtures.appleCredential())
        XCTAssertNil(first.credentials.storedSession, "an unanswered request commits nothing")

        // The next launch, over the same durable state.
        let second = makeHarness()
        await second.store.bootstrap()

        XCTAssertEqual(second.store.phase, .access)
        XCTAssertNotNil(second.store.pending)
    }

    /// After registration, before consent: the account exists, the payload is
    /// unconsented, and the relaunch lands on the consent gate.
    @MainActor
    func testRelaunchAfterRegistrationLandsOnConsent() async throws {
        _ = try await writePending(consented: false)
        let harness = makeHarness(session: AuthFixtures.session(onboardingStatus: .required))

        await harness.store.bootstrap()

        XCTAssertEqual(harness.store.phase, .consent)
        XCTAssertTrue(harness.submissions.submissions.isEmpty)
    }

    /// During submission: the request may or may not have arrived, so the
    /// relaunch offers Continue and sends nothing until the user asks.
    @MainActor
    func testRelaunchDuringSubmissionWaitsForTheUser() async throws {
        _ = try await writePending(consented: true)
        let harness = makeHarness(session: AuthFixtures.session(onboardingStatus: .required))

        await harness.store.bootstrap()

        XCTAssertEqual(harness.store.phase, .finalizing)
        XCTAssertTrue(harness.store.finalizationAwaitsUser)
        XCTAssertTrue(harness.submissions.submissions.isEmpty)
    }

    /// After the server accepted but before the client processed the response:
    /// the durable status is still `required`, so the retry re-sends the
    /// identical body and the server's `onboarding_already_complete` reconciles
    /// it without a second plan.
    @MainActor
    func testRelaunchAfterServerAcceptanceReconcilesInsteadOfCreatingASecondPlan() async throws {
        _ = try await writePending(consented: true)
        let harness = makeHarness(session: AuthFixtures.session(onboardingStatus: .required))
        harness.submissions.result = .failure(OnboardingError.alreadyComplete)
        await harness.store.bootstrap()
        XCTAssertEqual(harness.store.phase, .finalizing)

        await harness.store.retryFinalization()

        XCTAssertEqual(harness.store.phase, .ready)
        XCTAssertEqual(harness.credentials.storedSession?.onboardingStatus, .complete)
        let onDisk = try await harness.pendingStorage.load()
        XCTAssertNil(onDisk, "the duplicate is dropped; the server's plan is kept")
    }

    // MARK: - T050: bootstrap never uploads silently

    /// A previous process may already have shown this user an error, or died
    /// mid-request. Retrying on every launch quietly hammers a struggling server
    /// and takes the decision away from the only person who can see the failure.
    @MainActor
    func testABootstrapWithAConsentedPayloadUploadsNothingUntilTheUserAsks() async throws {
        _ = try await writePending(consented: true)
        let harness = makeHarness(session: AuthFixtures.session(onboardingStatus: .required))

        await harness.store.bootstrap()

        XCTAssertEqual(harness.submissions.submissions.count, 0, "no automatic attempt on launch")
        XCTAssertTrue(harness.store.finalizationAwaitsUser)

        await harness.store.retryFinalization()

        XCTAssertEqual(harness.submissions.submissions.count, 1, "and exactly one when they do")
    }

    @MainActor
    func testAFailedUploadPreservesBothTheSealedPayloadAndTheSession() async throws {
        let pending = try await writePending(consented: true)
        let harness = makeHarness(session: AuthFixtures.session(onboardingStatus: .required))
        harness.submissions.result = .failure(OnboardingError.serviceError)
        await harness.store.bootstrap()

        await harness.store.retryFinalization()

        XCTAssertEqual(harness.store.phase, .finalizing)
        XCTAssertNotNil(harness.store.finalizationError)
        XCTAssertTrue(harness.store.finalizationAwaitsUser, "the next attempt is the user's to make")

        let onDisk = try await harness.pendingStorage.load()
        XCTAssertEqual(onDisk?.submission.sessionId, pending.submission.sessionId)
        XCTAssertNotNil(onDisk?.consent, "the receipt survives a failed upload")
        XCTAssertEqual(harness.credentials.storedSession?.userId, "user-1", "the session is untouched")
        XCTAssertEqual(harness.credentials.storedSession?.onboardingStatus, .required)
    }

    // MARK: - Account actions from the backend handoff

    @MainActor
    func testConfirmedLogoutClearsOnlyTheLiveSessionAndReturnsToAccess() async throws {
        let live = AuthFixtures.session(
            accessExpiry: Date().addingTimeInterval(3_600),
            refreshExpiry: Date().addingTimeInterval(86_400),
            onboardingStatus: .complete
        )
        let harness = makeHarness(session: live)
        await harness.store.bootstrap()

        await harness.store.logout()

        XCTAssertEqual(harness.auth.logoutCalls, 1)
        XCTAssertNil(harness.credentials.storedSession)
        XCTAssertNotNil(harness.credentials.storedKnownAccount, "logout is not account deletion")
        XCTAssertEqual(harness.localData.clearedOwners, [live.userId])
        XCTAssertNil(harness.store.activeUserID)
        XCTAssertEqual(harness.store.phase, .access)
    }

    @MainActor
    func testUnconfirmedLogoutPreservesSessionAndAuthenticatedState() async throws {
        let live = AuthFixtures.session(
            accessExpiry: Date().addingTimeInterval(3_600),
            refreshExpiry: Date().addingTimeInterval(86_400),
            onboardingStatus: .complete
        )
        let harness = makeHarness(session: live)
        harness.auth.logoutResult = .failure(AuthError.serviceUnavailable)
        await harness.store.bootstrap()

        await harness.store.logout()

        XCTAssertEqual(harness.store.logoutError, .serviceUnavailable)
        XCTAssertEqual(harness.credentials.storedSession, live)
        XCTAssertEqual(harness.store.activeUserID, live.userId)
        XCTAssertEqual(harness.store.phase, .ready)
    }

    // MARK: - T064: account deletion

    @MainActor
    func testAnyNonSuccessfulDeletionPerformsZeroLocalCleanup() async throws {
        let harness = makeHarness(session: AuthFixtures.session(onboardingStatus: .complete))
        harness.auth.deleteResult = .failure(AuthError.serviceUnavailable)
        await harness.store.bootstrap()

        await harness.store.confirmAccountDeletion()

        XCTAssertEqual(harness.store.phase, .deletingAccount)
        XCTAssertEqual(harness.store.deletionError, .serviceUnavailable)
        XCTAssertEqual(harness.localData.clearedOwners, [], "no meal or image is removed")
        XCTAssertNotNil(harness.credentials.storedSession, "the credential stays until the server confirms")
        XCTAssertNotNil(harness.credentials.storedKnownAccount)
        XCTAssertNotNil(harness.credentials.storedDeletionAttempt, "the attempt is kept for the replay")
        XCTAssertFalse(
            harness.credentials.log.contains("deleteSession"),
            "an outage is not a deletion: nothing is removed until the server says 204"
        )
    }

    @MainActor
    func testDeletionRateLimitBlocksAnImmediateRetry() async throws {
        let harness = makeHarness(session: AuthFixtures.session(onboardingStatus: .complete))
        harness.auth.deleteResult = .failure(AuthError.rateLimited(retryAfter: 20))
        await harness.store.bootstrap()

        await harness.store.confirmAccountDeletion()
        await harness.store.retryAccountDeletion()

        XCTAssertEqual(harness.auth.deleteCalls.count, 1)
        XCTAssertNotNil(harness.store.deletionSecondsUntilRetry)
        XCTAssertEqual(harness.store.deletionError, .rateLimited(retryAfter: 20))
        XCTAssertNotNil(harness.credentials.storedDeletionAttempt)
    }

    @MainActor
    func testDeletionAuthenticationFailureRefreshesOnceAndRestartsTheOperation() async throws {
        let live = AuthFixtures.session(
            accessExpiry: Date().addingTimeInterval(3_600),
            refreshExpiry: Date().addingTimeInterval(86_400),
            onboardingStatus: .complete
        )
        let harness = makeHarness(session: live)
        harness.auth.refreshResult = .success(AuthFixtures.credentials())
        harness.auth.deleteResults = [
            .failure(AuthError.refreshRejected),
            .success(()),
        ]
        await harness.store.bootstrap()

        await harness.store.confirmAccountDeletion()

        XCTAssertEqual(harness.auth.refreshCalls, [live.refreshToken])
        XCTAssertEqual(harness.auth.deleteCalls.map(\.token), [live.accessToken, "access-2"])
        XCTAssertNotEqual(
            harness.auth.deleteCalls[0].operationId,
            harness.auth.deleteCalls[1].operationId
        )
        XCTAssertEqual(harness.store.phase, .onboarding)
    }

    @MainActor
    func testSecondDeletionAuthenticationFailureRequiresApple() async throws {
        let live = AuthFixtures.session(
            accessExpiry: Date().addingTimeInterval(3_600),
            refreshExpiry: Date().addingTimeInterval(86_400),
            onboardingStatus: .complete
        )
        let harness = makeHarness(session: live)
        harness.auth.refreshResult = .success(AuthFixtures.credentials())
        harness.auth.deleteResults = [
            .failure(AuthError.refreshRejected),
            .failure(AuthError.refreshRejected),
        ]
        await harness.store.bootstrap()

        await harness.store.confirmAccountDeletion()

        XCTAssertEqual(harness.auth.deleteCalls.count, 2)
        XCTAssertEqual(harness.store.deletionError, .reauthenticationRequired)
        XCTAssertEqual(harness.store.phase, .deletingAccount)
        XCTAssertNotNil(harness.credentials.storedDeletionAttempt)
    }

    /// The cleanup order from the data model, asserted as an order: the owner's
    /// rows and images go before the credentials that identify them, because a
    /// crash the other way round strands data nobody can attribute or remove.
    @MainActor
    func testAConfirmedDeletionRunsTheCleanupOrderAndReturnsToOnboarding() async throws {
        _ = try await writePending(consented: true)
        try await writeDraft()
        let harness = makeHarness(session: AuthFixtures.session(onboardingStatus: .complete))
        await harness.store.bootstrap()

        await harness.store.confirmAccountDeletion()

        XCTAssertEqual(harness.store.phase, .onboarding)
        XCTAssertEqual(harness.localData.clearedOwners, ["user-1"], "only that owner's rows")
        XCTAssertEqual(harness.auth.deleteCalls.count, 1)
        XCTAssertEqual(harness.auth.deleteCalls[0].token, "access-1",
                       "the exact bearer the user confirmed with, not a refreshed one")

        let cleanup = harness.credentials.log.drop { $0 != "deleteSession" }
        XCTAssertEqual(
            Array(cleanup.prefix(3)),
            ["deleteSession", "deleteKnownAccount", "deleteDeletionAttempt"],
            "all three records go, and the attempt goes last"
        )
        XCTAssertNil(harness.credentials.storedSession)
        XCTAssertNil(harness.credentials.storedKnownAccount)
        XCTAssertNil(harness.credentials.storedDeletionAttempt)

        let onDisk = try await harness.pendingStorage.load()
        XCTAssertNil(onDisk)
        let draft = try await harness.onboardingStorage.draft()
        XCTAssertNil(draft)
        XCTAssertNil(harness.store.pending)
        XCTAssertNil(harness.store.activeUserID)
    }

    /// The replay presents the confirmed operation again, unchanged, so a server
    /// that already processed it answers the same way rather than treating it as
    /// a second request.
    @MainActor
    func testTheDeletionReplayPresentsTheSameOperationAndToken() async throws {
        let attempt = AccountDeletionAttempt(
            operationId: UUID(),
            presentedAccessToken: "access-1",
            ownerUserID: "user-1",
            confirmedAt: Date(timeIntervalSince1970: 5_000)
        )
        let harness = makeHarness(
            session: AuthFixtures.session(onboardingStatus: .complete),
            deletionAttempt: attempt
        )
        await harness.store.bootstrap()

        await harness.store.retryAccountDeletion()

        XCTAssertEqual(harness.auth.deleteCalls.count, 1)
        XCTAssertEqual(harness.auth.deleteCalls[0].operationId, attempt.operationId)
        XCTAssertEqual(harness.auth.deleteCalls[0].token, attempt.presentedAccessToken)
        XCTAssertEqual(harness.store.phase, .onboarding)
    }

    @MainActor
    func testDeletionReauthenticationRestartsWithANewBearerAndOperationKey() async throws {
        let harness = makeHarness(session: AuthFixtures.session(onboardingStatus: .complete))
        harness.auth.deleteResult = .failure(AuthError.reauthenticationRequired)
        await harness.store.bootstrap()

        await harness.store.confirmAccountDeletion()

        let original = try XCTUnwrap(harness.credentials.storedDeletionAttempt)
        XCTAssertEqual(harness.store.deletionError, .reauthenticationRequired)

        harness.auth.authenticateResult = .success(
            AuthFixtures.authResponse(
                userId: original.ownerUserID,
                status: .complete,
                accessToken: "access-reauth",
                refreshToken: "refresh-reauth"
            )
        )
        harness.auth.deleteResult = .success(())
        await harness.store.reauthenticateAccountDeletion(
            with: AuthFixtures.appleCredential()
        )

        XCTAssertEqual(harness.auth.authenticateCalls.count, 1)
        XCTAssertEqual(harness.auth.deleteCalls.count, 2)
        XCTAssertEqual(harness.auth.deleteCalls[1].token, "access-reauth")
        XCTAssertNotEqual(harness.auth.deleteCalls[1].operationId, original.operationId)
        XCTAssertEqual(harness.store.phase, .onboarding)
        XCTAssertNil(harness.credentials.storedDeletionAttempt)
    }

    @MainActor
    func testDeletionReauthenticationRefusesADifferentKaloriasUser() async throws {
        let harness = makeHarness(session: AuthFixtures.session(onboardingStatus: .complete))
        harness.auth.deleteResult = .failure(AuthError.reauthenticationRequired)
        await harness.store.bootstrap()
        await harness.store.confirmAccountDeletion()
        let original = try XCTUnwrap(harness.credentials.storedDeletionAttempt)

        harness.auth.authenticateResult = .success(
            AuthFixtures.authResponse(userId: "different-user", status: .complete)
        )
        await harness.store.reauthenticateAccountDeletion(
            with: AuthFixtures.appleCredential(appleUserIdentifier: "different-apple-sub")
        )

        XCTAssertEqual(harness.store.deletionError, .invalidAppleCredential)
        XCTAssertEqual(harness.auth.deleteCalls.count, 1, "the other account is never sent to deletion")
        XCTAssertEqual(harness.credentials.storedDeletionAttempt, original)
        XCTAssertEqual(harness.store.phase, .deletingAccount)
    }
}
