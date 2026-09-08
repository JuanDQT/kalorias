//
//  QuestionnaireDecodingTests.swift
//  KaloriasTests
//
//  What the app accepts from the server and what it refuses.
//
//  The important assertion here is the refusal: an unrecognised `type` throws
//  rather than being skipped. Skipping is the tempting move and it is how a plan
//  gets calculated from a required question nobody was asked.
//

import XCTest
@testable import Kalorias

nonisolated final class QuestionnaireDecodingTests: XCTestCase {

    func testTheDataEnvelopeIsRequired() throws {
        let payload = OnboardingFixtures.wrap(
            sections: OnboardingFixtures.section(id: "s", questions: OnboardingFixtures.text("a"))
        )
        // Wrapped: fine.
        XCTAssertNoThrow(
            try JSONDecoder().decode(QuestionnaireEnvelope.self, from: Data("{\"data\": \(payload)}".utf8))
        )
        // Root-level: not a response this app ever gets.
        XCTAssertThrowsError(
            try JSONDecoder().decode(QuestionnaireEnvelope.self, from: Data(payload.utf8))
        )
    }

    func testAnUnknownQuestionTypeIsRefusedRatherThanSkipped() {
        let json = """
        { "id": "q", "type": "slider", "prompt": ["how much?"] }
        """
        XCTAssertThrowsError(try OnboardingFixtures.question(json))
    }

    func testAnEmptyPromptIsRefused() {
        let json = """
        { "id": "q", "type": "text", "prompt": [], "text": { "maxLength": 10 } }
        """
        XCTAssertThrowsError(try OnboardingFixtures.question(json))
    }

    func testDefaultsAreTheSafeOnes() throws {
        let question = try OnboardingFixtures.question(OnboardingFixtures.text("a"))
        XCTAssertTrue(question.isRequired, "a question is required unless it says otherwise")
        XCTAssertTrue(question.options.isEmpty)
        XCTAssertTrue(question.crossChecks.isEmpty)
        XCTAssertFalse(question.acceptsCustomValues)
    }

    func testAnOptionIsNotExclusiveUnlessItSaysSo() throws {
        let question = try OnboardingFixtures.question(OnboardingFixtures.gate("g"))
        XCTAssertEqual(question.options.map(\.isExclusive), [false, false])
    }

    func testConditionGroupReadsAllOrAny() throws {
        let all = try JSONDecoder().decode(
            ConditionGroup.self,
            from: Data(#"{"all":[{"questionId":"a","operator":"equals","value":"y"}]}"#.utf8)
        )
        XCTAssertEqual(all.kind, .all)

        let any = try JSONDecoder().decode(
            ConditionGroup.self,
            from: Data(#"{"any":[{"questionId":"a","operator":"answered"}]}"#.utf8)
        )
        XCTAssertEqual(any.kind, .any)
        XCTAssertNil(any.conditions[0].value)

        XCTAssertThrowsError(
            try JSONDecoder().decode(ConditionGroup.self, from: Data("{}".utf8))
        )
    }

    /// Ids are unique across the whole questionnaire, so `questions` can be a
    /// flat lookup — but an `optionId` is only unique inside its question.
    func testTheSameOptionIdInDifferentQuestionsIsNotAClash() throws {
        let json = OnboardingFixtures.wrap(
            sections: OnboardingFixtures.section(
                id: "s",
                questions: [OnboardingFixtures.gate("a"), OnboardingFixtures.gate("b")]
                    .joined(separator: ",")
            )
        )
        let questionnaire = try OnboardingFixtures.questionnaire(json)
        XCTAssertEqual(questionnaire.question(id: "a")?.option(id: "yes")?.title, "Yes")
        XCTAssertEqual(questionnaire.question(id: "b")?.option(id: "yes")?.title, "Yes")
    }
}
