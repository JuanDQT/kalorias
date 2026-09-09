//
//  OnboardingChatView.swift
//  Kalorias
//
//  The onboarding, as a conversation. Questions arrive as bubbles, the answer
//  appears under each one, and the input for whatever is being asked sits at the
//  bottom.
//
//  THE WHOLE THREAD IS REBUILT FROM THE ANSWERS on every change, never appended
//  to. That is what makes going back correct: when an edit invalidates three
//  questions further down, they leave the thread because they are no longer in
//  the projection, not because someone remembered to remove them.
//
//  PROGRESS IS COUNTED IN SECTIONS. With conditionals the number of questions
//  depends on the answers, and a bar that slides backwards — or "12 of 19"
//  becoming "12 of 17" — reads as a bug even when it is good news.
//
//  A CROSS-CHECK IS A CHOICE, NOT A WALL. "Review" jumps to the answer it
//  disagrees with; "Continue" takes the value as given. A user who insists
//  usually knows something the questionnaire does not.
//
//  FINISHING SENDS NOTHING (feature 010). The final action seals the answers
//  into protected local storage and hands them to the journey, which then shows
//  Sign in with Apple. The copy says so: the plan is not "on its way" until an
//  account exists and the user has separately agreed to their data being
//  processed.
//
//  A FAILED WRITE STOPS THE THREAD WHERE IT IS. An answer whose draft did not
//  land is not shown as accepted, and the message says "on this device" rather
//  than blaming the network — those call for completely different actions.
//

import SwiftUI

struct OnboardingChatView: View {
    @State private var store: OnboardingStore

    init(store: OnboardingStore = OnboardingStore()) {
        _store = State(initialValue: store)
    }

    /// The anchor the thread scrolls to. One id, so nothing has to guess which
    /// bubble is last.
    private let bottomAnchor = "onboarding.bottom"

    var body: some View {
        ZStack {
            AppColor.surfacePrimary.ignoresSafeArea()

            switch store.state {
            case .loading:
                ProgressView()
                    .controlSize(.large)
                    .tint(AppColor.brandPrimary)

            case .asking, .sealing:
                chat

            case .finished:
                finished

            case let .failed(error):
                failure(error)
            }
        }
        .animation(AppMotion.standard, value: store.state)
        .task { await store.load() }
        .task { await store.refreshCacheInBackground() }
        .alert(item: warningBinding) { pending in
            Alert(
                title: Text("onboarding.warning.title"),
                message: Text(verbatim: pending.check.message),
                primaryButton: .default(Text("onboarding.warning.review")) {
                    Task { await store.reviewWarning() }
                },
                secondaryButton: .cancel(Text("onboarding.warning.continue")) {
                    Task { await store.acceptWarning() }
                }
            )
        }
    }

    // MARK: The thread

    @ViewBuilder
    private var chat: some View {
        if let flow = store.flow {
            VStack(spacing: 0) {
                header(flow)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: AppSpacing.md) {
                            ForEach(flow.answeredQuestions, id: \.question.id) { entry in
                                thread(for: entry.question, in: flow) {
                                    AnswerBubble(text: entry.answer.summary(for: entry.question)) {
                                        Task { await store.reopen(entry.question.id) }
                                    }
                                }
                            }

                            if let current = flow.currentQuestion {
                                thread(for: current, in: flow) {
                                    QuestionInputView(
                                        question: current,
                                        initial: nil,
                                        followedUnit: followedUnit(for: current, in: flow),
                                        followedValue: followedValue(for: current, in: flow),
                                        onAnswer: { answer in
                                            Task { await store.answer(answer, for: current.id) }
                                        }
                                    )
                                    // Identity by question id: reusing one
                                    // input's `@State` for the next question is
                                    // how a wheel shows the previous answer.
                                    .id(current.id)
                                    .transition(AppMotion.standardTransition)
                                }
                            }

                            if flow.isComplete {
                                finishButton
                            }

                            if let failure = store.storageFailure {
                                storageFailureNotice(failure)
                            }

                            Color.clear.frame(height: 1).id(bottomAnchor)
                        }
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.bottom, AppSpacing.xl)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: flow.answers.count) { _, _ in scroll(proxy) }
                    .onChange(of: flow.currentQuestion?.id) { _, _ in scroll(proxy) }
                    .onAppear { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
                }
            }
            .animation(AppMotion.standard, value: flow.answers.count)
            .overlay {
                if case .sealing = store.state {
                    ZStack {
                        AppColor.surfacePrimary.opacity(0.9).ignoresSafeArea()
                        ProgressView().controlSize(.large).tint(AppColor.brandPrimary)
                    }
                }
            }
        }
    }

    /// One turn of the conversation: its section heading if it opens one, the
    /// question's bubbles, then whatever `content` is — an answer or an input.
    @ViewBuilder
    private func thread(
        for question: Question,
        in flow: QuestionnaireFlow,
        @ViewBuilder content: () -> some View
    ) -> some View {
        if let section = flow.sectionHeader(startingAt: question) {
            SectionDivider(title: section.title, subtitle: section.subtitle)
        }
        // Keyed by question AND position. Keying by position alone gives every
        // question's first bubble the id 0, and a `LazyVStack` holding two of
        // them renders undefined results — which is precisely what the runtime
        // said out loud the first time this ran.
        ForEach(question.promptBubbles) { bubble in
            QuestionBubble(text: bubble.text)
        }
        content()
    }

    private func header(_ flow: QuestionnaireFlow) -> some View {
        VStack(spacing: AppSpacing.sm) {
            if let progress = flow.progress {
                ProgressView(value: Double(progress.section), total: Double(progress.total))
                    .tint(AppColor.brandPrimaryFill)
                    .accessibilityLabel(Text("onboarding.progress"))
                    .accessibilityValue(Text(verbatim: "\(progress.section)/\(progress.total)"))
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
    }

    private var finishButton: some View {
        Button {
            Task { await store.finish() }
        } label: {
            Text("onboarding.createPlan").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppColor.brandPrimaryFill)
        .controlSize(.large)
        .padding(.top, AppSpacing.lg)
    }

    // MARK: Terminal states

    /// A brief acknowledgement while the journey swaps the root to Access. The
    /// handoff already happened — the payload was on disk before this appeared —
    /// so there is nothing here to tap and nothing to wait for.
    private var finished: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(AppColor.success)
                .accessibilityHidden(true)
            Text("onboarding.done.title")
                .rowTitleRole()
                .multilineTextAlignment(.center)
        }
        .padding(AppSpacing.xxl)
    }

    /// A write that did not land. The thread does not advance, and the copy says
    /// "on this device" so nobody spends five minutes toggling airplane mode.
    private func storageFailureNotice(_ failure: OnboardingStore.StorageFailure) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("onboarding.storageError")
                .supportingTextRole()
                .foregroundStyle(AppColor.danger)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                store.dismissStorageFailure()
            } label: {
                Text("common.tryAgain")
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, AppSpacing.md)
        .accessibilityIdentifier("onboarding.storageError")
        .transition(AppMotion.subtleTransition)
    }

    private func failure(_ error: OnboardingError) -> some View {
        VStack(spacing: AppSpacing.lg) {
            Text(String(localized: error.messageKey))
                .supportingTextRole()
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)

            // Only offered when there is a thread to go back to. With no
            // questionnaire at all there is nothing to retry into.
            if store.flow != nil {
                Button {
                    store.dismissFailure()
                } label: {
                    Text("onboarding.retry").padding(.horizontal, AppSpacing.xl)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColor.brandPrimaryFill)
                .controlSize(.large)
            }
        }
        .padding(AppSpacing.xxl)
    }

    // MARK: Following another answer

    /// The display unit of the question this one follows, so a goal weight opens
    /// in pounds for someone who weighed themselves in pounds.
    private func followedUnit(for question: Question, in flow: QuestionnaireFlow) -> String? {
        guard let id = question.measure?.unitFollows,
              case let .measure(answer) = flow.answers[id] else { return nil }
        return answer.displayUnit
    }

    private func followedValue(for question: Question, in flow: QuestionnaireFlow) -> Double? {
        guard let id = question.measure?.defaultFollows,
              case let .measure(answer) = flow.answers[id] else { return nil }
        return answer.canonical
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        withAnimation(AppMotion.standard) {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }

    /// `alert(item:)` needs an `Identifiable` binding; the warning is value
    /// state on the store, so it is adapted here rather than given an id it does
    /// not otherwise need.
    private var warningBinding: Binding<IdentifiedWarning?> {
        Binding(
            get: { store.warning.map(IdentifiedWarning.init) },
            set: { if $0 == nil, store.warning != nil { Task { await store.acceptWarning() } } }
        )
    }

    private struct IdentifiedWarning: Identifiable {
        let warning: OnboardingStore.PendingWarning
        var id: String { warning.questionId }
        var check: CrossCheck { warning.check }

        init(_ warning: OnboardingStore.PendingWarning) { self.warning = warning }
    }
}

#Preview {
    OnboardingChatView()
}
