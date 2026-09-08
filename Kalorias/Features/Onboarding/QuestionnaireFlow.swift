//
//  QuestionnaireFlow.swift
//  Kalorias
//
//  Which question is being asked, which have been answered, and what happens
//  when the user goes back and changes one.
//
//  THE ANSWERS ARE THE ONLY STATE. The chat transcript is a projection of them
//  over the question list, recomputed whole. The tempting alternative — an array
//  of bubbles that gets appended to — stops being correct the moment the first
//  conditional appears, because a bubble already on screen may no longer belong
//  there.
//
//  EDITING DOES NOT TRUNCATE THE THREAD. When an answer changes, only the
//  questions the new answer actually invalidated lose theirs; everything still
//  visible keeps what it had. Truncating is an afternoon's work and punishes the
//  user who steps back eight questions to fix their height by making them redo
//  the other seven.
//
//  WHAT IS PRUNED GOES TO THE SHADOW STORE, not to the bin. The real case: the
//  user says yes to allergies, types four, changes their mind, says no, then
//  says yes again — and their four allergies are still there. The shadow store
//  is never submitted.
//
//  AN UNANSWERED QUESTION SATISFIES NOTHING. `notEquals` against a gate that has
//  not been reached yet is **false**, not true: otherwise every question hanging
//  off a "no" branch appears at the top of the chat, before its gate is asked.
//
//  Pure, synchronous and free of SwiftUI, so all of the above is asserted in
//  `QuestionnaireFlowTests` rather than tapped through a simulator.
//

import Foundation

nonisolated struct QuestionnaireFlow: Equatable, Sendable {

    let questionnaire: Questionnaire

    /// What the user has said. The source of truth.
    private(set) var answers: [String: OnboardingAnswer]

    /// Answers pruned because their question stopped being visible, kept in case
    /// it becomes visible again. Never submitted, discarded on completion.
    private(set) var shadowed: [String: OnboardingAnswer]

    init(
        questionnaire: Questionnaire,
        answers: [String: OnboardingAnswer] = [:],
        shadowed: [String: OnboardingAnswer] = [:]
    ) {
        self.questionnaire = questionnaire
        self.answers = answers
        self.shadowed = shadowed
        reconcile()
    }

    // MARK: Visibility

    /// Whether `question` belongs in the thread given the current answers.
    func isVisible(_ question: Question) -> Bool {
        guard let group = question.visibleIf else { return true }
        let results = group.conditions.map(satisfies)
        return group.kind == .all ? results.allSatisfy(\.self) : results.contains(true)
    }

    private func satisfies(_ condition: Condition) -> Bool {
        let answer = answers[condition.questionId]

        switch condition.op {
        case .answered:
            return answer != nil
        case .notAnswered:
            return answer == nil
        case .equals, .notEquals, .contains, .notContains:
            // Everything below needs an answer to compare against. Without one
            // the condition is simply not met — see the file comment.
            guard let answer, let value = condition.value else { return false }
            switch (condition.op, answer) {
            case let (.equals, .single(optionId)):
                return optionId == value
            case let (.notEquals, .single(optionId)):
                return optionId != value
            case let (.contains, .multi(optionIds, _)):
                return optionIds.contains(value)
            case let (.notContains, .multi(optionIds, _)):
                return optionIds.contains(value) == false
            default:
                // An operator aimed at the wrong answer shape. CI rejects this
                // in the content; at runtime the safe reading is "not met",
                // which hides the dependent question rather than showing one
                // whose premise never held.
                return false
            }
        }
    }

    /// The questions that belong in the thread right now, in order.
    var visibleQuestions: [Question] {
        questionnaire.questions.filter(isVisible)
    }

    /// The question being asked: the first visible one with no answer.
    /// `nil` once every visible question is answered.
    var currentQuestion: Question? {
        visibleQuestions.first { answers[$0.id] == nil }
    }

    /// The visible questions that already have an answer, in order — what the
    /// thread shows above the current input.
    var answeredQuestions: [(question: Question, answer: OnboardingAnswer)] {
        visibleQuestions.compactMap { question in
            answers[question.id].map { (question, $0) }
        }
    }

    var isComplete: Bool { currentQuestion == nil }

    // MARK: Answering

    /// Record an answer and reconcile everything that depends on it.
    mutating func answer(_ answer: OnboardingAnswer, for questionId: String) {
        answers[questionId] = answer
        // A fresh answer supersedes anything remembered for this question.
        shadowed[questionId] = nil
        reconcile()
    }

    /// Reopen a question for editing: its answer, and only its answer, is
    /// dropped so it becomes current again. Later answers survive — the pruning
    /// happens when the *new* answer arrives, and only for what it invalidates.
    mutating func reopen(_ questionId: String) {
        answers[questionId] = nil
        reconcile()
    }

    /// Drop answers whose questions are no longer visible, and restore any that
    /// became visible again.
    ///
    /// Iterated to a fixed point because visibility depends on answers, which
    /// this changes: a gate that hides a question can hide the question *that*
    /// one gated. The bound is the question count — each pass either changes
    /// something or is the last.
    private mutating func reconcile() {
        for _ in 0...questionnaire.questions.count {
            var changed = false

            for question in questionnaire.questions {
                let visible = isVisible(question)

                if visible == false, let existing = answers[question.id] {
                    shadowed[question.id] = existing
                    answers[question.id] = nil
                    changed = true
                } else if visible, answers[question.id] == nil, let remembered = shadowed[question.id] {
                    answers[question.id] = remembered
                    shadowed[question.id] = nil
                    changed = true
                }
            }

            if changed == false { return }
        }
    }

    // MARK: Progress

    /// Progress is counted **by section**, never by question.
    ///
    /// With conditionals the number of questions depends on the answers, and a
    /// bar that goes backwards — or a "12 of 19" that becomes "12 of 17" — reads
    /// as a bug rather than as good news.
    var progress: (section: Int, total: Int)? {
        let counted = questionnaire.sections.filter(\.countsTowardProgress)
        guard counted.isEmpty == false else { return nil }

        let currentSection = currentQuestion.flatMap { question in
            questionnaire.sections.first { $0.questions.contains { $0.id == question.id } }
        }
        guard let currentSection else { return (counted.count, counted.count) }

        if let index = counted.firstIndex(where: { $0.id == currentSection.id }) {
            return (index + 1, counted.count)
        }

        // The current question is in a section that does not count — the welcome
        // or the closing bubble. Report how many counted sections lie behind it,
        // so the bar starts empty on the welcome and is full on the closer
        // instead of vanishing at both ends.
        guard let position = questionnaire.sections.firstIndex(where: { $0.id == currentSection.id })
        else { return nil }
        let behind = questionnaire.sections[..<position].filter(\.countsTowardProgress).count
        return (behind, counted.count)
    }

    /// The section heading to show above `question`, or `nil` when the question
    /// is not the first of its section and therefore introduces nothing.
    func sectionHeader(startingAt question: Question) -> QuestionnaireSection? {
        guard let section = questionnaire.sections.first(where: {
            $0.questions.contains { $0.id == question.id }
        }) else { return nil }

        // The first *visible* question of the section, which is not necessarily
        // the first declared one — a conditional may have hidden that.
        let firstVisible = section.questions.first(where: isVisible)
        return firstVisible?.id == question.id ? section : nil
    }

    // MARK: Cross-checks

    /// The warning a pending value would raise, if any.
    ///
    /// A `warning` never blocks: it is shown with a way back to the question it
    /// contradicts and a way to carry on. A user who insists usually knows
    /// something the questionnaire does not.
    func crossCheck(for question: Question, value: Double) -> CrossCheck? {
        question.crossChecks.first { check in
            if let when = check.when {
                let results = when.conditions.map(satisfies)
                let holds = when.kind == .all ? results.allSatisfy(\.self) : results.contains(true)
                guard holds else { return false }
            }
            guard let other = answers[check.compareTo]?.comparableValue else { return false }
            return check.passes(value: value, other: other) == false
        }
    }

    // MARK: Submission

    /// The answers, in question order, ready to encode. Questions that were
    /// never asked are simply absent — not `null`, not `skipped`.
    func submissionEntries() -> [OnboardingSubmission.Entry] {
        visibleQuestions.compactMap { question in
            answers[question.id].map {
                OnboardingSubmission.Entry(questionId: question.id, type: question.type, answer: $0)
            }
        }
    }
}
