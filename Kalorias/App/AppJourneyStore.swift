//
//  AppJourneyStore.swift
//  Kalorias
//
//  The one place that decides what the app is showing (feature 010, FR-027).
//
//  IT RESTORES; IT DOES NOT REPLAY. On launch this reads Keychain and protected
//  storage once and resolves a single phase from the `data-model.md` table. The
//  alternative — starting at "first run" and letting transitions accumulate —
//  means every relaunch has to re-derive where it got to, and gets it wrong at
//  exactly the boundaries that matter: after Apple but before the auth response,
//  after registration but before consent, after an upload the server accepted
//  but the client never heard about.
//
//  THE SERVER'S STATUS OUTRANKS ANY LOCAL FLAG. A sealed payload on disk does
//  not mean the account needs one — a returning user who reinstalled has both a
//  local payload and an existing plan, and sending it would overwrite the plan
//  they already have (FR-022). So `AuthSession.onboardingStatus`, which only a
//  backend response can set, is consulted first and the redundant local copy is
//  discarded only after that status is durable.
//
//  A CONFIRMED DELETION OUTRANKS EVERYTHING. If an attempt record exists, the
//  server may already have deleted the account, and showing the tab shell would
//  be showing someone data that no longer exists anywhere else.
//
//  "COULD NOT READ" IS NOT "IS NOT THERE". A locked device makes protected files
//  unreadable; treating that as absence restarts a finished onboarding or offers
//  to create a second account. Those reads keep the app in `restoring`.
//
//  WRITES COMMIT BEFORE THE PHASE CHANGES, ALWAYS IN THE ORDER THE DATA MODEL
//  FIXES. Nothing here publishes a phase whose precondition is not already on
//  disk, because a crash one line later must land the next launch somewhere
//  recoverable rather than somewhere that loses data.
//
//  EXACTLY ONE UPLOAD IS AUTOMATIC: the first one, immediately after consent is
//  given in this process. Everything after a visible failure — including after a
//  relaunch — waits for the user to ask (FR-033). A screen that silently retries
//  on every launch is a screen that can quietly hammer a struggling server, and
//  it takes the decision away from the only person who can see the error.
//

import Observation
import SwiftUI

@MainActor
@Observable
final class AppJourneyStore {

    // MARK: Published state

    private(set) var phase: AppJourneyPhase = .restoring

    /// A local-storage problem worth telling the user about. Never a reason to
    /// delete or send anything.
    private(set) var localDataError: JourneyLocalDataError?

    /// The sealed payload this device is holding, when there is one.
    private(set) var pending: PendingOnboarding?

    /// The authenticated backend user, or `nil` when there is no live session.
    /// Local meals are scoped by exactly this value (FR-042).
    private(set) var activeUserID: String?

    // MARK: Access state

    /// What the access screen shows beneath the Apple button.
    private(set) var accessError: AuthError?
    /// The Apple/registration result the user should read, without it being
    /// styled as a failure.
    private(set) var accessNotice: AppleAuthorizationError?
    /// True from the tap until the backend has answered. Disables the button and
    /// the review action so a sealed payload cannot change mid-authentication.
    private(set) var isAuthenticating = false
    /// Remaining server-directed pause after `auth_rate_limited`. While set,
    /// the Apple control is disabled and another exchange cannot be sent.
    private(set) var accessSecondsUntilRetry: Int?

    // MARK: Consent and finalization state

    private(set) var consentError: ConsentFailure?
    private(set) var isFinalizing = false
    private(set) var finalizationError: OnboardingError?
    /// True when finalization was restored by a relaunch: the screen offers
    /// Continue and sends nothing on its own.
    private(set) var finalizationAwaitsUser = false

    // MARK: Account state

    private(set) var deletionError: AuthError?
    private(set) var deletionAuthorizationNotice: AppleAuthorizationError?
    private(set) var isDeleting = false
    private(set) var deletionSecondsUntilRetry: Int?
    private(set) var logoutError: AuthError?
    private(set) var isLoggingOut = false
    /// The app moved developer accounts. Support, not deletion.
    private(set) var needsAccountTransferHelp = false

    nonisolated enum ConsentFailure: Equatable, Sendable {
        /// Product/Legal release values are absent or invalid. No receipt can be
        /// created until the build is configured with the approved inputs.
        case notConfigured
        /// The receipt could not be written. Nothing was sent.
        case storage
        /// The accepted versions are no longer the approved ones.
        case outdated
    }

    // MARK: Dependencies

    private let credentials: any CredentialStoring
    private let sessions: any AuthSessionProviding
    private let auth: any AuthenticationServicing
    private let submissions: any OnboardingSubmitting
    private let credentialState: any AppleCredentialStateChecking
    private let onboardingStorage: OnboardingStorage
    private let pendingStorage: PendingOnboardingStorage
    private let localData: (any AccountLocalDataClearing)?
    private let now: () -> Date
    private var accessCooldownTask: Task<Void, Never>?
    private var deletionCooldownTask: Task<Void, Never>?

    /// The exact policy URL and version identifiers shipped by this build.
    /// Exposed read-only so the consent and privacy views render the same values
    /// that are written into the receipt.
    let consentConfiguration: ConsentConfiguration?

    init(
        credentials: any CredentialStoring = KeychainCredentialStore(),
        sessions: (any AuthSessionProviding)? = nil,
        auth: any AuthenticationServicing = RemoteAuthService(),
        submissions: (any OnboardingSubmitting)? = nil,
        credentialState: any AppleCredentialStateChecking = AppleCredentialStateService(),
        onboardingStorage: OnboardingStorage = OnboardingStorage(),
        pendingStorage: PendingOnboardingStorage = PendingOnboardingStorage(),
        localData: (any AccountLocalDataClearing)? = nil,
        consentConfiguration: ConsentConfiguration? = BackendEnvironment.consentConfiguration,
        now: @escaping () -> Date = Date.init
    ) {
        let coordinator = sessions
            ?? AuthSessionCoordinator(credentials: credentials, service: auth)
        let relay = AuthenticationEventRelay()
        self.eventRelay = relay
        self.credentials = credentials
        self.sessions = coordinator
        self.auth = auth
        self.submissions = submissions
            ?? RemoteOnboardingSubmissionService(
                client: AuthenticatedHTTPClient(sessions: coordinator, events: relay)
            )
        self.credentialState = credentialState
        self.onboardingStorage = onboardingStorage
        self.pendingStorage = pendingStorage
        self.localData = localData
        self.consentConfiguration = consentConfiguration
        self.now = now
        // Now that `self` exists, the client it just built can call back into it.
        relay.connect(self)
    }

    /// The relay every authenticated client reports a dead session through.
    /// Exposed so the analysis service composed elsewhere shares this one.
    let eventRelay: AuthenticationEventRelay

    /// A client that shares this journey's session actor and event relay.
    ///
    /// Every authenticated feature composes its service from here rather than
    /// building its own: two clients over two coordinators would each refresh
    /// independently, and the second one's rotation would look to the server
    /// exactly like a stolen refresh token being replayed.
    func makeAuthenticatedClient() -> AuthenticatedHTTPClient {
        AuthenticatedHTTPClient(sessions: sessions, events: eventRelay)
    }

    // MARK: Bootstrap

    /// Resolve the phase from durable state. Runs once at launch, before the
    /// authenticated shell can be built.
    func bootstrap() async {
        localDataError = nil

        // 1. A confirmed deletion beats every other state, including a session
        //    that still looks perfectly valid.
        let attempt: AccountDeletionAttempt?
        let session: AuthSession?
        let knownAccount: KnownAccount?
        do {
            attempt = try credentials.loadDeletionAttempt()
            session = try credentials.loadSession()
            knownAccount = try credentials.loadKnownAccount()
        } catch {
            // The Keychain is unreadable. Guessing here means either exposing an
            // account's data or offering to create a duplicate of it.
            localDataError = .unreadableCredentials
            phase = .restoring
            return
        }

        if attempt != nil {
            activeUserID = nil
            // Restored, not resumed: the replay waits for the user's Continue,
            // because the last process may already have shown them an error.
            isDeleting = false
            phase = .deletingAccount
            return
        }

        // 2. Protected local state. A locked device waits rather than being told
        //    it has nothing saved.
        let pending: PendingOnboarding?
        do {
            pending = try await pendingStorage.load()
        } catch ProtectedFileStore.StoreError.unavailableWhileLocked {
            phase = .restoring
            return
        } catch {
            // Damaged bytes are surfaced. They are neither deleted nor sent.
            localDataError = .corruptedOnboardingData
            pending = nil
        }
        self.pending = pending

        // 3. A live session: the server's committed status decides.
        if let session, session.isValid {
            activeUserID = session.userId

            // Reconciliation: a lost paired write can leave a valid session with
            // no marker. Rebuilding it here costs nothing and keeps a later
            // session loss from restarting a finished user's first run.
            if knownAccount == nil {
                try? credentials.saveKnownAccount(KnownAccount(session: session))
            }

            switch session.onboardingStatus {
            case .complete:
                phase = .ready
                // The redundant local copy goes only now that `complete` is
                // known durable — the other order can lose an unconfirmed one.
                await discardRedundantLocalOnboarding()
            case .required:
                guard let pending else {
                    // An account that still needs a plan, with nothing sealed:
                    // build one. This is the returning-account-on-a-new-install
                    // case, not a first run.
                    phase = .onboarding
                    return
                }
                // A consented payload does **not** upload itself on launch: a
                // previous process may have already shown the user a failure, or
                // died mid-request. The finalization screen asks (FR-033).
                if pending.isReadyToUpload(using: consentConfiguration) {
                    finalizationAwaitsUser = true
                    phase = .finalizing
                } else {
                    phase = .consent
                }
            }
            await verifyAppleCredential(for: session)
            return
        }

        // 4. No live session.
        activeUserID = nil

        if knownAccount != nil {
            // A known account never restarts the questionnaire, whatever its
            // status: it reauthenticates (FR-008).
            phase = .access
            return
        }

        phase = pending == nil ? .onboarding : .access
    }

    /// Re-check the phase when the app comes back to the foreground, so a
    /// revocation that happened elsewhere is noticed.
    func applicationDidBecomeActive() async {
        guard let session = await sessions.currentSession() else { return }
        await verifyAppleCredential(for: session)
    }

    /// Apple's revocation notification fired while the app was running.
    func appleCredentialWasRevoked() async {
        await endSessionAndGate()
    }

    // MARK: Onboarding

    /// The onboarding sealed its answers. Called only after the protected write
    /// returned, so access can never appear with nothing behind it (FR-005).
    func onboardingDidSeal(_ pending: PendingOnboarding) {
        self.pending = pending
        localDataError = nil
        accessError = nil
        accessNotice = nil

        // A returning account that had to rebuild its onboarding is already
        // authenticated: it goes straight to consent rather than back to Apple.
        if activeUserID != nil {
            phase = .consent
        } else {
            phase = .access
        }
    }

    /// "Review answers" on the access screen: back to the chat, same session
    /// identity, sealed payload left exactly where it is until a new one
    /// replaces it (FR-007).
    func reviewAnswers() {
        guard canReviewAnswers else { return }
        accessError = nil
        accessNotice = nil
        phase = .onboarding
    }

    /// Whether reviewing is offered at all.
    ///
    /// It is not while an authorization is running, and not once a backend
    /// account has been committed in this journey: the sealed payload is then
    /// the body of an idempotent request that may already be in flight, and
    /// editing it under the same key is how a retry becomes an
    /// `idempotency_payload_mismatch`.
    var canReviewAnswers: Bool {
        pending != nil && activeUserID == nil && !isAuthenticating
    }

    /// The identity a resumed chat must keep, so a review edit reseals under the
    /// same session id rather than starting a second onboarding.
    var resumableOnboardingIdentity: (sessionId: UUID, startedAt: Date)? {
        guard let pending else { return nil }
        return (pending.submission.sessionId, pending.submission.startedAt)
    }

    // MARK: Access

    /// A successful native authorization. Exchanges it for a Kalorias session
    /// and moves to whatever the *server* says this account needs.
    func signIn(with credential: AppleAuthorizationCredential) async {
        guard !isAuthenticating, accessSecondsUntilRetry == nil else { return }
        isAuthenticating = true
        accessError = nil
        accessNotice = nil
        defer { isAuthenticating = false }

        do {
            let response = try await auth.authenticate(with: credential)
            AuthLog.success(.registration)
            let session = response.makeSession(
                appleUserIdentifier: credential.appleUserIdentifier
            )
            // Session, then marker, then a phase. Nothing is published until
            // both writes have landed (data model, "Backend registration").
            try await sessions.commit(session)
            activeUserID = session.userId
            accessCooldownTask?.cancel()
            accessCooldownTask = nil
            accessSecondsUntilRetry = nil

            switch response.onboardingStatus {
            case .complete:
                phase = .ready
                await discardRedundantLocalOnboarding()
            case .required:
                guard let pending else {
                    phase = .onboarding
                    return
                }
                if pending.isReadyToUpload(using: consentConfiguration) {
                    await finalize(automatic: true)
                } else {
                    phase = .consent
                }
            }
        } catch {
            let authError = AuthError.from(error)
            AuthLog.failure(.registration, outcome: String(describing: authError))
            accessError = authError
            if case let .rateLimited(retryAfter) = authError {
                beginAccessCooldown(
                    seconds: retryAfter ?? RetryCooldown.defaultSeconds
                )
            }
            // Nothing local changed: the sealed payload and every answer in it
            // are exactly where they were (FR-029).
        }
    }

    /// The native sheet was cancelled or failed before any request was made.
    func appleAuthorizationDidFail(_ error: AppleAuthorizationError) {
        accessError = nil
        accessNotice = error
    }

    func clearAccessFeedback() {
        accessError = nil
        accessNotice = nil
    }

    private func beginAccessCooldown(seconds: TimeInterval) {
        accessCooldownTask?.cancel()
        let cooldown = RetryCooldown(seconds: seconds, now: now())
        accessSecondsUntilRetry = cooldown.secondsRemaining(at: now())

        accessCooldownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                let remaining = cooldown.secondsRemaining(at: self.now())
                self.accessSecondsUntilRetry = remaining == 0 ? nil : remaining
                if remaining == 0 { return }
            }
        }
    }

    // MARK: Consent

    /// "Accept and create my plan": persist the receipt first, then start the
    /// one automatic upload.
    func acceptHealthDataConsent() async {
        guard phase == .consent else { return }
        consentError = nil

        guard let consentConfiguration else {
            consentError = .notConfigured
            return
        }

        let receipt = ConsentReceipt(configuration: consentConfiguration, grantedAt: now())
        do {
            pending = try await pendingStorage.grantConsent(receipt)
        } catch {
            // Nothing is sent. The permission has to be recorded before the data
            // it covers leaves the device.
            consentError = .storage
            return
        }

        await finalize(automatic: true)
    }

    /// "Not now": stay registered, keep everything local, send nothing (FR-018).
    func declineHealthDataConsent() {
        consentError = nil
    }

    // MARK: Finalization

    /// The user asked to retry. Identical body, identical key.
    func retryFinalization() async {
        await finalize(automatic: false)
    }

    /// Submit the sealed payload.
    ///
    /// - Parameter automatic: true only for the single attempt that follows
    ///   fresh consent in this process. Every other attempt is user-initiated.
    private func finalize(automatic: Bool) async {
        guard
            !isFinalizing,
            let pending,
            pending.isReadyToUpload(using: consentConfiguration)
        else { return }

        phase = .finalizing
        finalizationAwaitsUser = false
        finalizationError = nil
        isFinalizing = true
        defer { isFinalizing = false }

        do {
            _ = try await submissions.submit(pending)
            AuthLog.success(.onboardingSubmission)
            // Status first, files second. A crash between them leaves a
            // redundant payload that bootstrap discards; the other order loses
            // answers the server may never have received.
            try await sessions.commitOnboardingStatus(.complete)
            phase = .ready
            await discardRedundantLocalOnboarding()
        } catch OnboardingError.alreadyComplete {
            // The account already has a plan — the ambiguous-timeout case. Trust
            // the server, keep its plan, drop the duplicate.
            try? await sessions.commitOnboardingStatus(.complete)
            phase = .ready
            await discardRedundantLocalOnboarding()
        } catch OnboardingError.authenticationRequired {
            await endSessionAndGate()
        } catch OnboardingError.consentOutdated {
            consentError = .outdated
            phase = .consent
        } catch {
            let mapped = OnboardingError.from(error)
            AuthLog.failure(.onboardingSubmission, outcome: String(describing: mapped))
            finalizationError = mapped
            // Whatever happened, the payload and the session are untouched and
            // the next attempt is the user's to make.
            finalizationAwaitsUser = !automatic
        }
    }

    // MARK: Account

    /// Close only this Kalorias session. The server's `204` is the commit point;
    /// failures keep the Keychain session and authenticated shell intact.
    func logout() async {
        guard phase == .ready, !isLoggingOut else { return }
        let ownerUserID = activeUserID
        isLoggingOut = true
        logoutError = nil
        defer { isLoggingOut = false }

        do {
            try await sessions.logout()
            AuthLog.success(.logout)
            if let ownerUserID {
                await localData?.clearLocalData(ownedBy: ownerUserID)
            }
            await pendingStorage.clear()
            await onboardingStorage.clearDraft()
            pending = nil
            activeUserID = nil
            phase = .access
        } catch {
            let mapped = AuthError.from(error)
            AuthLog.failure(.logout, outcome: String(describing: mapped))
            logoutError = mapped

            // Refresh rejection has its own contract: the session is already
            // definitively over even though `/logout` could not be called.
            if mapped.isDefinitiveRefreshFailure {
                activeUserID = nil
                phase = .access
            }
        }
    }

    // MARK: Account deletion

    /// The user confirmed the destructive action.
    ///
    /// The attempt is recorded *before* the request, and the authenticated shell
    /// is replaced immediately — so a termination mid-request cannot bring back
    /// a screenful of data for an account the server may already have removed.
    func confirmAccountDeletion() async {
        guard let session = await sessions.currentSession() else { return }

        let attempt = AccountDeletionAttempt(
            operationId: UUID(),
            presentedAccessToken: session.accessToken,
            ownerUserID: session.userId,
            confirmedAt: now()
        )
        do {
            try credentials.saveDeletionAttempt(attempt)
        } catch {
            deletionError = .serviceUnavailable
            return
        }

        deletionError = nil
        phase = .deletingAccount
        await performDeletion(attempt)
    }

    /// "Continue" on the deletion gate, after a failure or a relaunch. Replays
    /// the exact confirmed operation.
    func retryAccountDeletion() async {
        guard deletionSecondsUntilRetry == nil else { return }
        guard let attempt = try? credentials.loadDeletionAttempt() else {
            // Nothing outstanding: fall back to a normal bootstrap rather than
            // leaving the user on a gate with nothing behind it.
            await bootstrap()
            return
        }
        await performDeletion(attempt)
    }

    /// Apple has freshly reauthenticated the owner of the already-confirmed
    /// deletion. The old bearer/key pair is replaced with a new operation only
    /// after the backend proves this is the same Kalorias user.
    func reauthenticateAccountDeletion(
        with credential: AppleAuthorizationCredential
    ) async {
        guard
            phase == .deletingAccount,
            deletionError == .reauthenticationRequired,
            !isAuthenticating,
            let previousAttempt = try? credentials.loadDeletionAttempt()
        else { return }

        isAuthenticating = true
        deletionAuthorizationNotice = nil
        defer { isAuthenticating = false }

        do {
            let response = try await auth.authenticate(with: credential)
            guard response.userId == previousAttempt.ownerUserID else {
                // Never turn "reauthenticate this deletion" into "delete the
                // different Apple account that happened to sign in".
                throw AuthError.invalidAppleCredential
            }

            let session = response.makeSession(
                appleUserIdentifier: credential.appleUserIdentifier
            )
            try await sessions.commit(session)

            let restarted = AccountDeletionAttempt(
                operationId: UUID(),
                presentedAccessToken: session.accessToken,
                ownerUserID: session.userId,
                confirmedAt: now()
            )
            try credentials.saveDeletionAttempt(restarted)
            deletionError = nil
            await performDeletion(restarted)
        } catch {
            let mapped = AuthError.from(error)
            AuthLog.failure(.accountDeletion, outcome: String(describing: mapped))
            deletionError = mapped
        }
    }

    /// The reauthentication sheet ended before a backend request was possible.
    func accountDeletionAuthorizationDidFail(_ error: AppleAuthorizationError) {
        deletionAuthorizationNotice = error
    }

    private func performDeletion(
        _ attempt: AccountDeletionAttempt,
        allowsRefresh: Bool = true
    ) async {
        guard !isDeleting else { return }
        isDeleting = true
        deletionError = nil
        deletionAuthorizationNotice = nil

        do {
            try await auth.deleteAccount(
                accessToken: attempt.presentedAccessToken,
                operationId: attempt.operationId
            )
        } catch {
            // Any non-`204` leaves every local record and credential in place.
            let mapped = AuthError.from(error)
            AuthLog.failure(.accountDeletion, outcome: String(describing: mapped))
            isDeleting = false

            if mapped == .refreshRejected {
                if allowsRefresh {
                    await restartDeletionAfterRefreshing(attempt)
                } else {
                    // A newly rotated bearer was also rejected. Apple is the
                    // only remaining way to establish fresh authority.
                    deletionError = .reauthenticationRequired
                }
                return
            }

            deletionError = mapped
            if case let .rateLimited(retryAfter) = mapped {
                beginDeletionCooldown(
                    seconds: retryAfter ?? RetryCooldown.defaultSeconds
                )
            }
            return
        }
        isDeleting = false
        AuthLog.success(.accountDeletion)

        await clearEverything(ownedBy: attempt.ownerUserID)
    }

    /// A deletion `401` is safe to retry once because the backend checks the
    /// exact deletion tombstone before ordinary authentication. A refreshed
    /// bearer starts a new stable operation; a second `401`, or a definitively
    /// dead refresh token, moves to native Apple reauthentication.
    private func restartDeletionAfterRefreshing(_ attempt: AccountDeletionAttempt) async {
        do {
            let accessToken = try await sessions.refreshedAccessToken(
                replacing: attempt.presentedAccessToken
            )
            guard
                let current = await sessions.currentSession(),
                current.userId == attempt.ownerUserID,
                current.accessToken == accessToken
            else {
                throw AuthError.refreshRejected
            }

            let restarted = AccountDeletionAttempt(
                operationId: UUID(),
                presentedAccessToken: accessToken,
                ownerUserID: attempt.ownerUserID,
                confirmedAt: now()
            )
            try credentials.saveDeletionAttempt(restarted)
            deletionError = nil
            await performDeletion(restarted, allowsRefresh: false)
        } catch {
            let mapped = AuthError.from(error)
            AuthLog.failure(.accountDeletion, outcome: String(describing: mapped))
            deletionError = mapped.isDefinitiveRefreshFailure
                ? .reauthenticationRequired
                : mapped
        }
    }

    private func beginDeletionCooldown(seconds: TimeInterval) {
        deletionCooldownTask?.cancel()
        let cooldown = RetryCooldown(seconds: seconds, now: now())
        deletionSecondsUntilRetry = cooldown.secondsRemaining(at: now())

        deletionCooldownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                let remaining = cooldown.secondsRemaining(at: self.now())
                self.deletionSecondsUntilRetry = remaining == 0 ? nil : remaining
                if remaining == 0 { return }
            }
        }
    }

    /// The cleanup order from the data model. Each step is idempotent, so an
    /// interrupted run resumes safely on the next Continue.
    private func clearEverything(ownedBy ownerUserID: String) async {
        await localData?.clearLocalData(ownedBy: ownerUserID)

        await pendingStorage.clear()
        await onboardingStorage.clearDraft()

        try? credentials.deleteSession()
        try? credentials.deleteKnownAccount()
        try? credentials.deleteDeletionAttempt()
        await sessions.endSession()

        pending = nil
        activeUserID = nil
        deletionError = nil
        deletionCooldownTask?.cancel()
        deletionCooldownTask = nil
        deletionSecondsUntilRetry = nil
        accessCooldownTask?.cancel()
        accessCooldownTask = nil
        accessSecondsUntilRetry = nil
        finalizationError = nil
        consentError = nil
        accessError = nil
        accessNotice = nil
        phase = .onboarding
    }

    // MARK: Apple credential lifecycle

    private func verifyAppleCredential(for session: AuthSession) async {
        let state = await credentialState.state(
            forAppleUserIdentifier: session.appleUserIdentifier
        )
        switch state {
        case .authorized, .temporarilyUnavailable:
            // A failed lookup changes nothing. That is the whole point of the
            // distinction (FR-034).
            needsAccountTransferHelp = false
        case .transferred:
            // Not a deletion: the account needs migrating, and support has to do
            // it. Nothing local is removed.
            needsAccountTransferHelp = true
        case .revoked, .notFound:
            AuthLog.credentialInvalidated(state)
            await endSessionAndGate()
        }
    }

    /// Drop the credential, keep the account marker and every local file, and
    /// gate authenticated content behind Apple again.
    private func endSessionAndGate() async {
        await sessions.endSession()
        activeUserID = nil
        phase = .access
    }

    // MARK: Cleanup

    /// Remove local onboarding files that a durable `complete` status has made
    /// redundant. Idempotent, so an interrupted cleanup resumes safely.
    private func discardRedundantLocalOnboarding() async {
        await pendingStorage.clear()
        await onboardingStorage.clearDraft()
        pending = nil
        finalizationError = nil
        finalizationAwaitsUser = false
    }
}

// MARK: - Local data

/// How the journey removes one account's on-device meals and photos, without
/// importing SwiftData or UIKit into the journey itself (Principle V).
protocol AccountLocalDataClearing: Sendable, AnyObject {
    /// Remove every meal and image owned by `ownerUserID`, and nothing else.
    /// Idempotent.
    @MainActor func clearLocalData(ownedBy ownerUserID: String) async
}

// MARK: - Authentication events

extension AppJourneyStore: AuthenticationEventReceiving {
    /// The authenticated client could not renew the session. One place decides
    /// what that means for the UI, and this is it.
    nonisolated func authenticationRequired() async {
        await MainActor.run { [weak self] in
            guard let self, phase != .deletingAccount else { return }
            activeUserID = nil
            phase = .access
        }
    }
}
