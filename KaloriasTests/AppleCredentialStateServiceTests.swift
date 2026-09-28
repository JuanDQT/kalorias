//
//  AppleCredentialStateServiceTests.swift
//  KaloriasTests
//
//  The one distinction this type exists to protect: an answer from Apple versus
//  no answer at all.
//
//  `ASAuthorizationAppleIDProvider` reports `.notFound` when the user really did
//  revoke the app, and reports an error — sitting right next to a `.notFound`
//  the callback also hands you — when the lookup could not be performed at all.
//  Flattening the second into the first signs people out on a bad connection.
//  These tests assert both halves: the mapping that keeps the two apart, and
//  what the journey does with each result.
//
//  THE PROVIDER ITSELF IS NOT STUBBED, AND THAT IS DELIBERATE. Apple's provider
//  is a concrete class with no seam; a test that subclassed it would assert
//  against a shape of our own invention. What is asserted here instead is the
//  part the app actually decides: the state vocabulary, the empty-identifier
//  guard, and every consequence the journey draws from a state.
//

import XCTest
@testable import Kalorias

nonisolated final class AppleCredentialStateServiceTests: XCTestCase {

    private var directory: URL!

    override func setUp() async throws {
        directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: The vocabulary

    /// Only the two definitive outcomes may end a session. This is the rule the
    /// whole feature's revocation behaviour rests on, stated once.
    func testOnlyDefinitiveOutcomesInvalidateASession() {
        XCTAssertTrue(AppleCredentialState.revoked.invalidatesSession)
        XCTAssertTrue(AppleCredentialState.notFound.invalidatesSession)

        XCTAssertFalse(AppleCredentialState.authorized.invalidatesSession)
        XCTAssertFalse(
            AppleCredentialState.temporarilyUnavailable.invalidatesSession,
            "a failed lookup is not evidence of anything"
        )
        XCTAssertFalse(
            AppleCredentialState.transferred.invalidatesSession,
            "a moved developer account needs migrating, not deleting"
        )
    }

    /// No identifier, no question asked — and certainly no conclusion drawn.
    func testAnEmptyIdentifierIsNotAskedAboutAndIsNotTakenAsAbsence() async {
        let state = await AppleCredentialStateService().state(forAppleUserIdentifier: "")

        XCTAssertEqual(state, .temporarilyUnavailable)
        XCTAssertFalse(state.invalidatesSession)
    }

    // MARK: What the journey does with each state

    private struct Harness {
        let store: AppJourneyStore
        let credentials: InMemoryCredentialStore
        let checker: StubCredentialStateChecker
    }

    @MainActor
    private func makeHarness(
        _ state: AppleCredentialState,
        onboardingStatus: OnboardingServerStatus = .complete
    ) -> Harness {
        let credentials = InMemoryCredentialStore(
            session: AuthFixtures.session(onboardingStatus: onboardingStatus),
            knownAccount: KnownAccount(
                userId: "user-1",
                appleUserIdentifier: "apple-sub-1",
                onboardingStatus: onboardingStatus
            )
        )
        let auth = StubAuthService()
        let checker = StubCredentialStateChecker(state: state)
        let store = AppJourneyStore(
            credentials: credentials,
            sessions: AuthSessionCoordinator(credentials: credentials, service: auth),
            auth: auth,
            submissions: StubSubmissionService(),
            credentialState: checker,
            onboardingStorage: OnboardingStorage(directory: directory),
            pendingStorage: PendingOnboardingStorage(
                directory: directory.appending(path: "Protected", directoryHint: .isDirectory)
            ),
            localData: SpyLocalDataClearer()
        )
        return Harness(store: store, credentials: credentials, checker: checker)
    }

    @MainActor
    func testARevokedCredentialEndsTheSessionAndKeepsTheAccountMarker() async {
        let harness = makeHarness(.revoked)

        await harness.store.bootstrap()

        XCTAssertEqual(harness.checker.identifiers, ["apple-sub-1"], "asked about the stored subject")
        XCTAssertEqual(harness.store.phase, .access)
        XCTAssertNil(harness.store.activeUserID)
        XCTAssertNil(harness.credentials.storedSession, "the credential is dropped")
        XCTAssertNotNil(
            harness.credentials.storedKnownAccount,
            "the account still exists; only this device's session ended"
        )
        XCTAssertFalse(harness.store.needsAccountTransferHelp)
    }

    @MainActor
    func testANotFoundCredentialEndsTheSessionToo() async {
        let harness = makeHarness(.notFound)

        await harness.store.bootstrap()

        XCTAssertEqual(harness.store.phase, .access)
        XCTAssertNil(harness.credentials.storedSession)
        XCTAssertNotNil(harness.credentials.storedKnownAccount)
    }

    /// The failure this type was written to prevent: an offline launch must not
    /// look like a revocation.
    @MainActor
    func testATransientLookupFailureChangesNothingAtAll() async {
        let harness = makeHarness(.temporarilyUnavailable)

        await harness.store.bootstrap()

        XCTAssertEqual(harness.store.phase, .ready, "a failed lookup does not gate the app")
        XCTAssertEqual(harness.store.activeUserID, "user-1")
        XCTAssertNotNil(harness.credentials.storedSession)
        XCTAssertNotNil(harness.credentials.storedKnownAccount)
        XCTAssertFalse(harness.store.needsAccountTransferHelp)
    }

    @MainActor
    func testAnAuthorizedCredentialLeavesTheSessionAlone() async {
        let harness = makeHarness(.authorized)

        await harness.store.bootstrap()

        XCTAssertEqual(harness.store.phase, .ready)
        XCTAssertNotNil(harness.credentials.storedSession)
        XCTAssertFalse(harness.store.needsAccountTransferHelp)
    }

    /// Recoverable, and recoverable by a person: the account needs migrating,
    /// which support has to do. Nothing local is removed on the way there.
    @MainActor
    func testATransferredCredentialSurfacesMigrationWithoutRemovingAnything() async {
        let harness = makeHarness(.transferred)

        await harness.store.bootstrap()

        XCTAssertTrue(harness.store.needsAccountTransferHelp)
        XCTAssertEqual(harness.store.phase, .ready, "not a revocation, so not a gate")
        XCTAssertNotNil(harness.credentials.storedSession)
        XCTAssertNotNil(harness.credentials.storedKnownAccount)
        XCTAssertEqual(harness.store.activeUserID, "user-1")
    }

    /// A user can revoke in Settings while the app sits in the background, so
    /// the answer at launch is not the answer forever.
    @MainActor
    func testTheCheckRunsAgainOnForegroundAndActsOnAChangedAnswer() async {
        let harness = makeHarness(.authorized)
        await harness.store.bootstrap()
        XCTAssertEqual(harness.store.phase, .ready)

        harness.checker.state = .revoked
        await harness.store.applicationDidBecomeActive()

        XCTAssertEqual(harness.checker.identifiers.count, 2, "asked again, not cached")
        XCTAssertEqual(harness.store.phase, .access)
        XCTAssertNil(harness.credentials.storedSession)
    }

    /// Apple's notification arrives mid-session. It is definitive on its own.
    @MainActor
    func testTheRevocationNotificationEndsTheSessionImmediately() async {
        let harness = makeHarness(.authorized)
        await harness.store.bootstrap()

        await harness.store.appleCredentialWasRevoked()

        XCTAssertEqual(harness.store.phase, .access)
        XCTAssertNil(harness.store.activeUserID)
        XCTAssertNil(harness.credentials.storedSession)
        XCTAssertNotNil(harness.credentials.storedKnownAccount)
    }

    /// A foreground check with no session left asks Apple nothing: there is no
    /// subject to ask about, and no session to end.
    @MainActor
    func testForegroundingWithoutASessionAsksAppleNothing() async {
        let harness = makeHarness(.revoked)
        await harness.store.bootstrap()
        let asked = harness.checker.identifiers.count

        await harness.store.applicationDidBecomeActive()

        XCTAssertEqual(harness.checker.identifiers.count, asked)
        XCTAssertEqual(harness.store.phase, .access)
    }
}
