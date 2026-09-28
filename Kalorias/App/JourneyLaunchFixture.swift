//
//  JourneyLaunchFixture.swift
//  Kalorias
//
//  Launching straight into any journey phase, for looking at it
//  (feature 010, `contracts/ui-contracts.md` "DEBUG State Hooks").
//
//  THE WHOLE FILE IS INSIDE `#if DEBUG`. Not a flag checked at runtime, not a
//  configuration value someone can set — the type does not exist in a Release
//  build, so no shipped binary has a code path that fabricates a session.
//
//  IT INJECTS DEPENDENCIES; IT DOES NOT SET A PHASE. The fixtures hand
//  `AppJourneyStore` a Keychain, a storage directory and services that live only
//  in this process, and then let the real bootstrap resolve the phase from them.
//  A hook that assigned `phase` directly would let the screens be reviewed
//  against states the resolution table cannot actually produce — which is the
//  one thing a state hook must never do.
//
//  NOTHING IS WEAKENED. Apple authorization, server verification and the real
//  Keychain are untouched: a fixture run replaces them wholesale with in-memory
//  doubles under a temporary directory, so it can neither read nor overwrite the
//  real user's credentials or answers.
//

#if DEBUG

import Foundation

/// A journey composed from launch arguments instead of from the device.
struct JourneyLaunchFixture {

    /// The states `ui-contracts.md` names, one per screen worth reviewing.
    enum State: String {
        case onboarding
        case accessPending = "access-pending"
        case accessReturning = "access-returning"
        case consent
        case finalizing
        case finalizingError = "finalizing-error"
        case ready
        case deletingAccount = "deleting-account"
        case deletingAccountError = "deleting-account-error"
    }

    let state: State
    /// `-account-deletion-error`: the deletion route fails, so the destructive
    /// flow can be reviewed in its retryable state from `ready`.
    let failsAccountDeletion: Bool

    /// The fixture this process was launched with, if any.
    static func current(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> JourneyLaunchFixture? {
        guard let index = arguments.firstIndex(of: "-journey-state"),
              index + 1 < arguments.count,
              let state = State(rawValue: arguments[index + 1])
        else { return nil }

        return JourneyLaunchFixture(
            state: state,
            failsAccountDeletion: arguments.contains("-account-deletion-error")
                || state == .deletingAccountError
        )
    }

    // MARK: Composition

    /// A journey over doubles, seeded so the real bootstrap resolves to `state`.
    @MainActor
    func makeStore(localData: (any AccountLocalDataClearing)?) -> AppJourneyStore {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "JourneyFixture-\(UUID().uuidString)", directoryHint: .isDirectory)

        let credentials = FixtureCredentialStore()
        credentials.session = seededSession
        credentials.knownAccount = seededKnownAccount
        credentials.deletionAttempt = seededDeletionAttempt

        let protectedDirectory = directory.appending(path: "Protected", directoryHint: .isDirectory)
        let pendingStorage = PendingOnboardingStorage(directory: protectedDirectory)
        if let pending = seededPending {
            // Written synchronously, before the store exists: seeding from a
            // task would race `RootView`'s bootstrap and the fixture would open
            // on the wrong phase about as often as on the right one.
            try? FileManager.default.createDirectory(
                at: protectedDirectory,
                withIntermediateDirectories: true
            )
            if let data = try? ProtectedFileStore.makeEncoder().encode(pending) {
                try? data.write(
                    to: protectedDirectory.appending(path: PendingOnboardingStorage.fileName),
                    options: .atomic
                )
            }
        }

        return AppJourneyStore(
            credentials: credentials,
            auth: FixtureAuthService(failsDeletion: failsAccountDeletion),
            submissions: FixtureSubmissionService(fails: state == .finalizingError),
            credentialState: FixtureCredentialStateChecker(),
            onboardingStorage: OnboardingStorage(directory: directory),
            pendingStorage: pendingStorage,
            localData: localData,
            consentConfiguration: BackendEnvironment.consentConfiguration
        )
    }

    /// The one step a bootstrap cannot reach on its own: the two failed states
    /// exist only after an attempt was made and refused.
    ///
    /// It waits for the phase the seeded state resolves to rather than assuming
    /// an ordering against `RootView`'s own bootstrap task.
    @MainActor
    func settle(_ journey: AppJourneyStore) async {
        switch state {
        case .finalizingError:
            guard await waitForPhase(.finalizing, in: journey) else { return }
            await journey.retryFinalization()
        case .deletingAccountError:
            guard await waitForPhase(.deletingAccount, in: journey) else { return }
            await journey.retryAccountDeletion()
        default:
            break
        }
    }

    @MainActor
    private func waitForPhase(_ phase: AppJourneyPhase, in journey: AppJourneyStore) async -> Bool {
        for _ in 0..<100 {
            if journey.phase == phase { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    // MARK: Seeds

    private var seededSession: AuthSession? {
        switch state {
        case .onboarding, .accessPending, .accessReturning:
            return nil
        case .consent, .finalizing, .finalizingError:
            return Self.session(status: .required)
        case .ready, .deletingAccount, .deletingAccountError:
            return Self.session(status: .complete)
        }
    }

    private var seededKnownAccount: KnownAccount? {
        guard let session = seededSession else {
            // The returning user: an account this device knows, with no session.
            return state == .accessReturning
                ? KnownAccount(
                    userId: "fixture-user",
                    appleUserIdentifier: "fixture-apple-sub",
                    onboardingStatus: .complete
                )
                : nil
        }
        return KnownAccount(session: session)
    }

    private var seededDeletionAttempt: AccountDeletionAttempt? {
        switch state {
        case .deletingAccount, .deletingAccountError:
            return AccountDeletionAttempt(
                operationId: UUID(),
                presentedAccessToken: "fixture-access",
                ownerUserID: "fixture-user",
                confirmedAt: Date()
            )
        default:
            return nil
        }
    }

    private var seededPending: PendingOnboarding? {
        switch state {
        case .accessPending, .consent:
            return Self.pending(consented: false)
        case .finalizing, .finalizingError:
            return Self.pending(consented: true)
        case .onboarding, .accessReturning, .ready, .deletingAccount, .deletingAccountError:
            return nil
        }
    }

    private static func session(status: OnboardingServerStatus) -> AuthSession {
        AuthSession(
            userId: "fixture-user",
            appleUserIdentifier: "fixture-apple-sub",
            accessToken: "fixture-access",
            accessTokenExpiresAt: Date().addingTimeInterval(3_600),
            refreshToken: "fixture-refresh",
            refreshTokenExpiresAt: Date().addingTimeInterval(86_400),
            onboardingStatus: status
        )
    }

    private static func pending(consented: Bool) -> PendingOnboarding {
        PendingOnboarding(
            submission: OnboardingSubmission(
                sessionId: UUID(),
                onboardingId: "plan_v1",
                schemaVersion: 1,
                contentVersion: 1,
                locale: Locale.current.language.languageCode?.identifier ?? "es",
                startedAt: Date().addingTimeInterval(-600),
                completedAt: Date(),
                answers: []
            ),
            consent: consented
                ? BackendEnvironment.consentConfiguration.map {
                    ConsentReceipt(configuration: $0, grantedAt: Date())
                }
                : nil
        )
    }
}

// MARK: - Doubles

/// The Keychain, in this process only. A fixture run never reads or writes the
/// real one.
private nonisolated final class FixtureCredentialStore: CredentialStoring, @unchecked Sendable {

    private let lock = NSLock()
    private var _session: AuthSession?
    private var _knownAccount: KnownAccount?
    private var _deletionAttempt: AccountDeletionAttempt?

    var session: AuthSession? {
        get { lock.withLock { _session } }
        set { lock.withLock { _session = newValue } }
    }
    var knownAccount: KnownAccount? {
        get { lock.withLock { _knownAccount } }
        set { lock.withLock { _knownAccount = newValue } }
    }
    var deletionAttempt: AccountDeletionAttempt? {
        get { lock.withLock { _deletionAttempt } }
        set { lock.withLock { _deletionAttempt = newValue } }
    }

    func loadSession() throws -> AuthSession? { session }
    func saveSession(_ session: AuthSession) throws { self.session = session }
    func deleteSession() throws { session = nil }

    func loadKnownAccount() throws -> KnownAccount? { knownAccount }
    func saveKnownAccount(_ account: KnownAccount) throws { knownAccount = account }
    func deleteKnownAccount() throws { knownAccount = nil }

    func loadDeletionAttempt() throws -> AccountDeletionAttempt? { deletionAttempt }
    func saveDeletionAttempt(_ attempt: AccountDeletionAttempt) throws { deletionAttempt = attempt }
    func deleteDeletionAttempt() throws { deletionAttempt = nil }
}

/// Answers without a network. `authenticate` is unreachable in a fixture run —
/// every state that has an account is seeded with one — and refuses rather than
/// inventing a session if it ever is reached.
private nonisolated struct FixtureAuthService: AuthenticationServicing {

    let failsDeletion: Bool

    func authenticate(
        with credential: AppleAuthorizationCredential
    ) async throws -> AuthenticationResponse {
        throw AuthError.serviceUnavailable
    }

    func refresh(refreshToken: String) async throws -> SessionCredentials {
        throw AuthError.serviceUnavailable
    }

    func logout(accessToken: String, refreshToken: String) async throws {}

    func deleteAccount(accessToken: String, operationId: UUID) async throws {
        if failsDeletion { throw AuthError.serviceUnavailable }
    }
}

private nonisolated struct FixtureSubmissionService: OnboardingSubmitting {

    let fails: Bool

    func submit(_ pending: PendingOnboarding) async throws -> OnboardingSubmissionResult {
        if fails { throw OnboardingError.serviceError }
        return OnboardingSubmissionResult(onboardingStatus: .complete, planId: "fixture-plan")
    }
}

/// Apple is not asked during a fixture run, and a lookup that did not happen is
/// never evidence that a credential is gone.
private nonisolated struct FixtureCredentialStateChecker: AppleCredentialStateChecking {
    func state(forAppleUserIdentifier identifier: String) async -> AppleCredentialState {
        .authorized
    }
}

#endif
