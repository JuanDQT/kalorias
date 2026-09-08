//
//  QuestionnaireFlowTests.swift
//  KaloriasTests
//
//  The state machine behind going back and editing. Everything here is pure
//  arithmetic over answers — no view, no simulator, no waiting (Principle II).
//
//  The cases that matter are the ones that look fine in a demo and break for a
//  real user: an edit that silently wipes seven later answers, a question that
//  appears before the question it depends on, and free text that vanishes
//  because a gate was toggled twice.
//

import XCTest
@testable import Kalorias

nonisolated final class QuestionnaireFlowTests: XCTestCase {

    // A gate, a question behind it, and a question after both.
    private func gatedFlow() throws -> QuestionnaireFlow {
        let json = OnboardingFixtures.wrap(
            sections: OnboardingFixtures.section(
                id: "s1",
                questions: [
                    OnboardingFixtures.gate("has_allergies"),
                    OnboardingFixtures.gated("allergies", on: "has_allergies", equals: "yes"),
                    OnboardingFixtures.text("diet"),
                ].joined(separator: ",")
            )
        )
        return QuestionnaireFlow(questionnaire: try OnboardingFixtures.questionnaire(json))
    }

    // MARK: Visibility

    func testGatedQuestionIsHiddenUntilItsGateIsAnswered() throws {
        let flow = try gatedFlow()
        XCTAssertEqual(flow.visibleQuestions.map(\.id), ["has_allergies", "diet"])
        XCTAssertEqual(flow.currentQuestion?.id, "has_allergies")
    }

    func testGatedQuestionAppearsWhenTheGateMatches() throws {
        var flow = try gatedFlow()
        flow.answer(.single(optionId: "yes"), for: "has_allergies")
        XCTAssertEqual(flow.visibleQuestions.map(\.id), ["has_allergies", "allergies", "diet"])
        XCTAssertEqual(flow.currentQuestion?.id, "allergies")
    }

    func testGatedQuestionStaysHiddenOnTheOtherBranch() throws {
        var flow = try gatedFlow()
        flow.answer(.single(optionId: "no"), for: "has_allergies")
        XCTAssertEqual(flow.currentQuestion?.id, "diet")
    }

    /// An unanswered gate satisfies nothing — including `notEquals`. Otherwise
    /// every question on a "no" branch shows up at the top of the chat before
    /// its gate has been asked.
    func testNotEqualsAgainstAnUnansweredGateIsNotSatisfied() throws {
        let json = OnboardingFixtures.wrap(
            sections: OnboardingFixtures.section(
                id: "s1",
                questions: [
                    OnboardingFixtures.gate("wants_plan"),
                    """
                    { "id": "meals", "type": "text", "prompt": ["meals"], "text": { "maxLength": 10 },
                      "visibleIf": { "all": [
                        { "questionId": "wants_plan", "operator": "notEquals", "value": "no" }] } }
                    """,
                ].joined(separator: ",")
            )
        )
        let flow = QuestionnaireFlow(questionnaire: try OnboardingFixtures.questionnaire(json))
        XCTAssertEqual(flow.visibleQuestions.map(\.id), ["wants_plan"])
    }

    // MARK: Editing

    /// The rule the whole design turns on: changing an early answer must not
    /// throw away later ones that are still valid.
    func testEditingAnAnswerKeepsLaterAnswersThatAreStillValid() throws {
        var flow = try gatedFlow()
        flow.answer(.single(optionId: "yes"), for: "has_allergies")
        flow.answer(.text("lactose"), for: "allergies")
        flow.answer(.text("balanced"), for: "diet")
        XCTAssertTrue(flow.isComplete)

        flow.reopen("has_allergies")
        flow.answer(.single(optionId: "yes"), for: "has_allergies")

        XCTAssertEqual(flow.answers["allergies"], .text("lactose"))
        XCTAssertEqual(flow.answers["diet"], .text("balanced"))
        XCTAssertTrue(flow.isComplete)
    }

    func testAnswersInvalidatedByAnEditArePruned() throws {
        var flow = try gatedFlow()
        flow.answer(.single(optionId: "yes"), for: "has_allergies")
        flow.answer(.text("lactose"), for: "allergies")
        flow.answer(.text("balanced"), for: "diet")

        flow.answer(.single(optionId: "no"), for: "has_allergies")

        XCTAssertNil(flow.answers["allergies"], "the gated answer no longer applies")
        XCTAssertEqual(flow.answers["diet"], .text("balanced"), "but the unrelated one survives")
    }

    func testPrunedAnswersComeBackWhenTheQuestionDoes() throws {
        var flow = try gatedFlow()
        flow.answer(.single(optionId: "yes"), for: "has_allergies")
        flow.answer(.text("lactose"), for: "allergies")

        flow.answer(.single(optionId: "no"), for: "has_allergies")
        flow.answer(.single(optionId: "yes"), for: "has_allergies")

        XCTAssertEqual(flow.answers["allergies"], .text("lactose"))
    }

    /// A gate that hides a question which itself gates a third one. Pruning has
    /// to run to a fixed point or the third answer survives with nothing above
    /// it to justify its presence.
    func testPruningCascadesThroughChainedConditions() throws {
        let json = OnboardingFixtures.wrap(
            sections: OnboardingFixtures.section(
                id: "s1",
                questions: [
                    OnboardingFixtures.gate("a"),
                    """
                    { "id": "b", "type": "single_choice", "prompt": ["b"],
                      "options": [{ "id": "yes", "title": "Y" }, { "id": "no", "title": "N" }],
                      "visibleIf": { "all": [
                        { "questionId": "a", "operator": "equals", "value": "yes" }] } }
                    """,
                    OnboardingFixtures.gated("c", on: "b", equals: "yes"),
                ].joined(separator: ",")
            )
        )
        var flow = QuestionnaireFlow(questionnaire: try OnboardingFixtures.questionnaire(json))
        flow.answer(.single(optionId: "yes"), for: "a")
        flow.answer(.single(optionId: "yes"), for: "b")
        flow.answer(.text("deep"), for: "c")
        XCTAssertEqual(flow.answers.count, 3)

        flow.answer(.single(optionId: "no"), for: "a")

        XCTAssertNil(flow.answers["b"])
        XCTAssertNil(flow.answers["c"], "the second-level answer must go too")
        XCTAssertEqual(flow.answers.count, 1)
    }

    func testReopeningOnlyClearsThatQuestion() throws {
        var flow = try gatedFlow()
        flow.answer(.single(optionId: "no"), for: "has_allergies")
        flow.answer(.text("balanced"), for: "diet")

        flow.reopen("has_allergies")

        XCTAssertEqual(flow.currentQuestion?.id, "has_allergies")
        XCTAssertEqual(flow.answers["diet"], .text("balanced"))
    }

    // MARK: Submission

    func testHiddenQuestionsAreAbsentFromTheSubmission() throws {
        var flow = try gatedFlow()
        flow.answer(.single(optionId: "no"), for: "has_allergies")
        flow.answer(.text("balanced"), for: "diet")

        let ids = flow.submissionEntries().map(\.questionId)
        XCTAssertEqual(ids, ["has_allergies", "diet"])
        XCTAssertFalse(ids.contains("allergies"), "not null, not skipped — absent")
    }

    func testShadowedAnswersAreNotSubmitted() throws {
        var flow = try gatedFlow()
        flow.answer(.single(optionId: "yes"), for: "has_allergies")
        flow.answer(.text("lactose"), for: "allergies")
        flow.answer(.single(optionId: "no"), for: "has_allergies")
        flow.answer(.text("balanced"), for: "diet")

        XCTAssertEqual(flow.shadowed["allergies"], .text("lactose"))
        XCTAssertFalse(flow.submissionEntries().map(\.questionId).contains("allergies"))
    }

    // MARK: Progress

    func testProgressCountsSectionsAndIgnoresUncountedOnes() throws {
        let json = OnboardingFixtures.wrap(
            sections: [
                OnboardingFixtures.section(
                    id: "intro",
                    questions: """
                    { "id": "welcome", "type": "info", "prompt": ["hi"], "continueLabel": "Go" }
                    """,
                    countsTowardProgress: false
                ),
                OnboardingFixtures.section(id: "s1", questions: OnboardingFixtures.text("a")),
                OnboardingFixtures.section(id: "s2", questions: OnboardingFixtures.text("b")),
            ].joined(separator: ",")
        )
        var flow = QuestionnaireFlow(questionnaire: try OnboardingFixtures.questionnaire(json))

        XCTAssertEqual(flow.progress?.total, 2)
        flow.answer(.acknowledged, for: "welcome")
        XCTAssertEqual(flow.progress?.section, 1)
        flow.answer(.text("x"), for: "a")
        XCTAssertEqual(flow.progress?.section, 2)
    }

    /// The heading belongs to the first question of the section that is actually
    /// showing, which a conditional can move.
    func testSectionHeaderFollowsTheFirstVisibleQuestion() throws {
        let json = OnboardingFixtures.wrap(
            sections: OnboardingFixtures.section(
                id: "s1",
                questions: [
                    """
                    { "id": "hidden", "type": "text", "prompt": ["h"], "text": { "maxLength": 5 },
                      "visibleIf": { "all": [
                        { "questionId": "hidden", "operator": "answered" }] } }
                    """,
                    OnboardingFixtures.text("shown"),
                ].joined(separator: ",")
            )
        )
        let flow = QuestionnaireFlow(questionnaire: try OnboardingFixtures.questionnaire(json))
        let shown = try XCTUnwrap(flow.questionnaire.question(id: "shown"))
        XCTAssertEqual(flow.sectionHeader(startingAt: shown)?.id, "s1")
    }

    // MARK: Cross-checks

    func testCrossCheckFiresOnlyWhenItsConditionHolds() throws {
        let json = OnboardingFixtures.wrap(
            sections: OnboardingFixtures.section(
                id: "s1",
                questions: [
                    """
                    { "id": "goal", "type": "single_choice", "prompt": ["goal"],
                      "options": [{ "id": "lose", "title": "Lose" }, { "id": "gain", "title": "Gain" }] }
                    """,
                    OnboardingFixtures.weightMeasure,
                    """
                    { "id": "target", "type": "measure", "prompt": ["target"],
                      "measure": { "widget": "wheel", "canonicalUnit": "kg", "defaultUnit": "kg",
                        "units": [{ "id": "kg", "label": "kg", "components": [
                          { "id": "kg", "min": 30, "max": 250, "step": 0.1, "default": 70,
                            "decimals": 1, "toCanonical": 1 }] }] },
                      "crossChecks": [{ "severity": "warning", "rule": "lessThan", "compareTo": "weight",
                        "when": { "all": [{ "questionId": "goal", "operator": "equals", "value": "lose" }] },
                        "message": "Higher than your current weight." }] }
                    """,
                ].joined(separator: ",")
            )
        )
        var flow = QuestionnaireFlow(questionnaire: try OnboardingFixtures.questionnaire(json))
        let target = try XCTUnwrap(flow.questionnaire.question(id: "target"))

        flow.answer(.single(optionId: "lose"), for: "goal")
        flow.answer(
            .measure(MeasureAnswer(canonical: 80, unit: "kg", displayUnit: "kg", displayComponents: ["kg": 80])),
            for: "weight"
        )

        XCTAssertNotNil(flow.crossCheck(for: target, value: 90), "90 kg is not less than 80 kg")
        XCTAssertNil(flow.crossCheck(for: target, value: 70))

        // The same 90 raises nothing once the goal is to gain.
        flow.answer(.single(optionId: "gain"), for: "goal")
        XCTAssertNil(flow.crossCheck(for: target, value: 90), "the `when` no longer holds")
    }
}
