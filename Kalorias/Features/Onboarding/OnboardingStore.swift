//
//  OnboardingStore.swift
//  Kalorias
//
//  Owns the onboarding chat: loads the questionnaire, holds the flow, saves a
//  draft after every answer and submits once at the end (Principle V — no view
//  touches the network).
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
//  SUBMITTING IS THE ONLY STEP THAT CAN BE RETRIED, and it retries under the
//  same `sessionId` — created once, when the flow starts — so the server sees a
//  repeat rather than a second person.
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
        case submitting
        case finished
        /// Nothing could be loaded, or the submission gave up.
        case failed(OnboardingError)
    }

    private(set) var state: State = .loading
    private(set) var flow: QuestionnaireFlow?

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

    private let service: any OnboardingProviding
    private let storage: OnboardingStorage
    private let languageCode: String
    private let firstPaintDeadline: Duration
    private let now: () -> Date

    /// How long the first paint waits for the server before opening on the
    /// copy already on the device.
    static let defaultFirstPaintDeadline: Duration = .milliseconds(2500)

    private var sessionId = UUID()
    private var startedAt: Date

    init(
        service: any OnboardingProviding = RemoteOnboardingService(),
        storage: OnboardingStorage = OnboardingStorage(),
        languageCode: String = Locale.current.language.languageCode?.identifier ?? "es",
        firstPaintDeadline: Duration = OnboardingStore.defaultFirstPaintDeadline,
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.storage = storage
        self.languageCode = languageCode
        self.firstPaintDeadline = firstPaintDeadline
        self.now = now
        self.startedAt = now()
    }

    // MARK: Loading

    func load() async {
        guard case .loading = state else { return }

        if let fetched = await fetchWithinDeadline() {
            storage.cacheQuestionnaire(fetched.payload)
            begin(with: fetched.questionnaire)
            return
        }
        if let cached = storage.cachedQuestionnaire() {
            begin(with: cached)
            return
        }
        if let bundled = storage.bundledQuestionnaire(languageCode: languageCode) {
            begin(with: bundled)
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
    private func begin(with questionnaire: Questionnaire) {
        if let draft = storage.draft(matching: questionnaire) {
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

    // MARK: Answering

    /// Record an answer, unless a cross-check disagrees with it first.
    func answer(_ answer: OnboardingAnswer, for questionId: String) {
        guard var flow, let question = flow.questionnaire.question(id: questionId) else { return }

        if let value = answer.comparableValue,
           let check = flow.crossCheck(for: question, value: value) {
            warning = PendingWarning(check: check, questionId: questionId, answer: answer)
            return
        }

        flow.answer(answer, for: questionId)
        self.flow = flow
        editingQuestionId = nil
        persist()
    }

    /// Take the pending answer as given, warning and all.
    func acceptWarning() {
        guard let warning, var flow else { return }
        flow.answer(warning.answer, for: warning.questionId)
        self.flow = flow
        self.warning = nil
        editingQuestionId = nil
        persist()
    }

    /// Go back to the question the warning says the answer contradicts.
    func reviewWarning() {
        guard let warning else { return }
        self.warning = nil
        reopen(warning.check.compareTo)
    }

    /// Reopen an earlier question for editing.
    ///
    /// Only that question's answer is dropped. What comes after survives until
    /// the *new* answer arrives, and then only what it invalidates is pruned —
    /// see `QuestionnaireFlow`.
    func reopen(_ questionId: String) {
        guard var flow else { return }
        flow.reopen(questionId)
        self.flow = flow
        editingQuestionId = questionId
        persist()
    }

    private func persist() {
        guard let flow else { return }
        storage.save(
            OnboardingDraft(
                sessionId: sessionId,
                onboardingId: flow.questionnaire.onboardingId,
                contentVersion: flow.questionnaire.contentVersion,
                startedAt: startedAt,
                answers: flow.answers,
                shadowed: flow.shadowed
            )
        )
    }

    // MARK: Submitting

    var canSubmit: Bool { flow?.isComplete == true }

    func submit() async {
        guard let flow, flow.isComplete else { return }
        state = .submitting

        let submission = OnboardingSubmission(
            sessionId: sessionId,
            onboardingId: flow.questionnaire.onboardingId,
            schemaVersion: flow.questionnaire.schemaVersion,
            contentVersion: flow.questionnaire.contentVersion,
            locale: flow.questionnaire.locale,
            startedAt: startedAt,
            completedAt: now(),
            answers: flow.submissionEntries()
        )

        do {
            try await service.submit(submission)
            // The draft has served its purpose; the shadow store goes with it.
            storage.clearDraft()
            state = .finished
        } catch {
            state = .failed(.from(error))
        }
    }

    /// Return to the chat after a failed submission, with every answer intact.
    func dismissFailure() {
        guard case .failed = state, flow != nil else { return }
        state = .asking
    }
}
