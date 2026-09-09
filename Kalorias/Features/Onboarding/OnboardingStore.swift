//
//  OnboardingStore.swift
//  Kalorias
//
//  Owns the onboarding chat: loads the questionnaire, holds the flow, saves a
//  draft after every answer, and seals the finished result **on this device**
//  (Principle V — no view touches the network).
//
//  IT NO LONGER SUBMITS ANYTHING. Feature 010 moved that boundary: the last
//  answer produces a sealed `PendingOnboarding` on disk and nothing else. The
//  upload happens later, once Sign in with Apple has committed an account and
//  the user has separately agreed to their health data being processed. Until
//  both of those are true, not one answer leaves the phone (FR-003).
//
//  THE QUESTIONNAIRE IS LOADED ONCE AND DOES NOT CHANGE MID-SESSION. Someone who
//  started on `contentVersion` 3 finishes on 3, even if the server is already
//  serving 4. Swapping the questions under a user's feet invalidates answers
//  already given, and there is no correct way to resolve that while they are
//  still typing.
//
//  A FAILED FETCH IS NOT A FAILED ONBOARDING. The cached copy is tried, then the
//  bundled one; `state` only becomes `.failed` when all three are gone, which in
//  practice means the app shipped without its resource.
//
//  THE FIRST PAINT DOES NOT WAIT OUT THE NETWORK. `load()` gives the server a
//  short deadline; past it the cached or bundled copy opens the chat, and the
//  request carries on in the background purely to refresh the cache for next
//  launch. It is never swapped in mid-session — that is the same rule as above,
//  and it is why the deadline is safe. Without it, a build pointing at a LAN
//  address that is not up sits on a blank spinner for the full request timeout,
//  which is the app's whole first impression.
//
//  THE NEXT QUESTION WAITS FOR THE DISK. An answer is shown as accepted only
//  after its draft write returns (FR-002). Advancing first and saving after
//  makes the most recent answer — the one the user is thinking about — the one
//  always at risk, and a storage failure would then be invisible.
//
//  A STORAGE FAILURE IS NOT A NETWORK FAILURE, and the user is told which. "We
//  couldn't save that on this device" and "we couldn't reach Kalorias" call for
//  completely different actions, and merging them into one message is how
//  someone spends five minutes toggling airplane mode at a full disk.
//
//  THE SESSION ID IS CREATED ONCE, when the flow starts, and survives resume,
//  review edits and every later retry — it is the idempotency key the server
//  uses to tell a resend from a second person (FR-031).
//

import Observation
import SwiftUI

@MainActor
@Observable
final class OnboardingStore {

    nonisolated enum State: Equatable {
        case loading
        /// The chat is running.
        case asking
        /// The finished answers are being written to protected storage.
        case sealing
        /// Sealed locally. The journey moves on to access from here.
        case finished
        /// Nothing could be loaded.
        case failed(OnboardingError)
    }

    /// A write that did not land. Shown in place, without advancing.
    nonisolated enum StorageFailure: Equatable, Sendable {
        /// The answer could not be saved. The question stays open.
        case answer
        /// The finished payload could not be sealed. Access is not shown.
        case seal
    }

    private(set) var state: State = .loading
    private(set) var flow: QuestionnaireFlow?

    /// The last write that failed, if any. Cleared by the next successful one.
    private(set) var storageFailure: StorageFailure?

    /// The question whose answer the user tapped to change. While set, its input
    /// is reopened in place with the current value loaded.
    var editingQuestionId: String?

    /// A cross-check the pending answer contradicts. Shown as a choice, never as
    /// a wall: "Review" goes back to the question it disagrees with, "Continue"
    /// takes the answer as given.
    private(set) var warning: PendingWarning?

    nonisolated struct PendingWarning: Equatable, Sendable {
        let check: CrossCheck
        let questionId: String
        let answer: OnboardingAnswer
    }

    private let service: any OnboardingFetching
    private let storage: OnboardingStorage
    private let pendingStorage: PendingOnboardingStorage
    private let languageCode: String
    private let firstPaintDeadline: Duration
    private let now: () -> Date

    /// Called once, with the sealed payload, after it is durably on disk. The
    /// journey store uses this to leave onboarding for access.
    private let onSealed: (PendingOnboarding) -> Void

    /// How long the first paint waits for the server before opening on the
    /// copy already on the device.
    static let defaultFirstPaintDeadline: Duration = .milliseconds(2500)

    private var sessionId = UUID()
    private var startedAt: Date

    init(
        service: any OnboardingFetching = RemoteOnboardingService(),
        storage: OnboardingStorage = OnboardingStorage(),
        pendingStorage: PendingOnboardingStorage = PendingOnboardingStorage(),
        languageCode: String = Locale.current.language.languageCode?.identifier ?? "es",
        firstPaintDeadline: Duration = OnboardingStore.defaultFirstPaintDeadline,
        now: @escaping () -> Date = Date.init,
        onSealed: @escaping (PendingOnboarding) -> Void = { _ in }
    ) {
        self.service = service
        self.storage = storage
        self.pendingStorage = pendingStorage
        self.languageCode = languageCode
        self.firstPaintDeadline = firstPaintDeadline
        self.now = now
        self.onSealed = onSealed
        self.startedAt = now()
    }

    // MARK: Loading

    func load() async {
        guard case .loading = state else { return }

        if let fetched = await fetchWithinDeadline() {
            storage.cacheQuestionnaire(fetched.payload)
            await begin(with: fetched.questionnaire)
            return
        }
        if let cached = storage.cachedQuestionnaire() {
            await begin(with: cached)
            return
        }
        if let bundled = storage.bundledQuestionnaire(languageCode: languageCode) {
            await begin(with: bundled)
            return
        }
        state = .failed(.serviceError)
    }

    /// The server's copy, but only if it arrives before the deadline.
    private func fetchWithinDeadline() async -> FetchedQuestionnaire? {
        await withTaskGroup(of: FetchedQuestionnaire?.self) { group in
            group.addTask { [service, languageCode] in
                try? await service.fetchQuestionnaire(languageCode: languageCode)
            }
            group.addTask { [firstPaintDeadline] in
                try? await Task.sleep(for: firstPaintDeadline)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Fetch the questionnaire purely to refresh the cache for the next launch.
    ///
    /// **It never touches the running flow.** Swapping the questions under
    /// someone mid-answer invalidates what they have already said, and there is
    /// no correct way to resolve that while they are still typing.
    func refreshCacheInBackground() async {
        guard let fetched = try? await service.fetchQuestionnaire(languageCode: languageCode) else { return }
        storage.cacheQuestionnaire(fetched.payload)
    }

    /// Start the flow, resuming a draft when one belongs to this questionnaire.
    ///
    /// A draft that cannot be read — a locked device, damaged bytes — starts a
    /// fresh flow rather than throwing the user out: they can still answer, and
    /// the alternative is a first launch that shows an error and nothing else.
    private func begin(with questionnaire: Questionnaire) async {
        if let draft = try? await storage.draft(matching: questionnaire) {
            sessionId = draft.sessionId
            startedAt = draft.startedAt
            flow = QuestionnaireFlow(
                questionnaire: questionnaire,
                answers: draft.answers,
                shadowed: draft.shadowed
            )
        } else {
            flow = QuestionnaireFlow(questionnaire: questionnaire)
        }
        state = .asking
    }

    /// Resume the questionnaire that produced an existing sealed payload, so
    /// "Review answers" on the access screen reopens the same session rather
    /// than starting a second one (FR-007).
    func resume(sessionId: UUID, startedAt: Date) {
        self.sessionId = sessionId
        self.startedAt = startedAt
    }

    // MARK: Answering

    /// Record an answer, unless a cross-check disagrees with it first.
    ///
    /// The draft is written before the new flow is published, so the thread
    /// never shows a question the disk does not know was answered.
    func answer(_ answer: OnboardingAnswer, for questionId: String) async {
        guard var flow, let question = flow.questionnaire.question(id: questionId) else { return }

        if let value = answer.comparableValue,
           let check = flow.crossCheck(for: question, value: value) {
            warning = PendingWarning(check: check, questionId: questionId, answer: answer)
            return
        }

        flow.answer(answer, for: questionId)
        await commit(flow)
    }

    /// Take the pending answer as given, warning and all.
    func acceptWarning() async {
        guard let warning, var flow else { return }
        flow.answer(warning.answer, for: warning.questionId)
        self.warning = nil
        await commit(flow)
    }

    /// Go back to the question the warning says the answer contradicts.
    func reviewWarning() async {
        guard let warning else { return }
        self.warning = nil
        await reopen(warning.check.compareTo)
    }

    /// Reopen an earlier question for editing.
    ///
    /// Only that question's answer is dropped. What comes after survives until
    /// the *new* answer arrives, and then only what it invalidates is pruned —
    /// see `QuestionnaireFlow`.
    func reopen(_ questionId: String) async {
        guard var flow else { return }
        flow.reopen(questionId)
        await commit(flow, editing: questionId)
    }

    /// Persist `flow`, and publish it only if that succeeded.
    private func commit(_ flow: QuestionnaireFlow, editing questionId: String? = nil) async {
        do {
            try await storage.save(
                OnboardingDraft(
                    sessionId: sessionId,
                    onboardingId: flow.questionnaire.onboardingId,
                    contentVersion: flow.questionnaire.contentVersion,
                    locale: flow.questionnaire.locale,
                    startedAt: startedAt,
                    updatedAt: now(),
                    answers: flow.answers,
                    shadowed: flow.shadowed
                )
            )
        } catch {
            // The question stays exactly where it was. Publishing the new flow
            // here would show an answer as accepted that nothing has recorded.
            storageFailure = .answer
            return
        }

        storageFailure = nil
        self.flow = flow
        editingQuestionId = questionId
    }

    /// Dismiss the inline storage message so the user can try the same answer
    /// again — for instance after freeing space.
    func dismissStorageFailure() {
        storageFailure = nil
    }

    // MARK: Sealing

    var canFinish: Bool { flow?.isComplete == true }

    /// Seal the finished answers into protected local storage.
    ///
    /// This is the end of the onboarding's responsibility. It makes no request,
    /// and `onSealed` runs only after the write returns — so the access screen
    /// can never appear with nothing behind it.
    func finish() async {
        guard let flow, flow.isComplete, state != .sealing else { return }
        state = .sealing

        do {
            let pending = try PendingOnboarding.seal(
                flow: flow,
                sessionId: sessionId,
                startedAt: startedAt,
                completedAt: now()
            )
            try await pendingStorage.save(pending)
            storageFailure = nil
            state = .finished
            onSealed(pending)
        } catch {
            storageFailure = .seal
            state = .asking
        }
    }

    /// Return to the chat after a load failure, with every answer intact.
    func dismissFailure() {
        guard case .failed = state, flow != nil else { return }
        state = .asking
    }
}
