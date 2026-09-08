//
//  CustomValueTests.swift
//  KaloriasTests
//
//  The only free text in the questionnaire, and therefore the only input where
//  what reaches the server is not an id from a list the server wrote.
//

import XCTest
@testable import Kalorias

nonisolated final class CustomValueTests: XCTestCase {

    private let question = try! OnboardingFixtures.question(
        """
        { "id": "dislikes", "type": "multi_choice", "prompt": ["dislikes"], "confirmLabel": "OK",
          "options": [
            { "id": "broccoli", "title": "Brócoli" },
            { "id": "olives", "title": "Aceitunas" }],
          "allowsCustom": { "enabled": true, "label": "Add", "maxItems": 2, "maxLength": 10 } }
        """
    )

    private func evaluate(_ raw: String, existing: [String] = []) -> CustomValue.Outcome {
        CustomValue.evaluate(raw, for: question, existing: existing)
    }

    func testPlainValueIsAccepted() {
        XCTAssertEqual(evaluate("Berenjena"), .accepted("Berenjena"))
    }

    func testWhitespaceIsTrimmedAndCollapsed() {
        XCTAssertEqual(evaluate("  queso   azul "), .accepted("queso azul"))
    }

    func testNewlinesBecomeSpaces() {
        XCTAssertEqual(evaluate("queso\nazul"), .accepted("queso azul"))
    }

    func testEmptyOrBlankIsRejected() {
        XCTAssertEqual(evaluate(""), .rejected)
        XCTAssertEqual(evaluate("   \n  "), .rejected)
    }

    func testValueIsCutToMaxLength() {
        XCTAssertEqual(evaluate("abcdefghijklmnop"), .accepted("abcdefghij"))
    }

    /// The case that motivates the whole type: someone types a food that is
    /// already an option, without the accent.
    func testTypingAnExistingOptionSelectsItInstead() {
        XCTAssertEqual(evaluate("brocoli"), .matchesOption(id: "broccoli"))
        XCTAssertEqual(evaluate("BRÓCOLI"), .matchesOption(id: "broccoli"))
        XCTAssertEqual(evaluate(" Aceitunas "), .matchesOption(id: "olives"))
    }

    func testADuplicateOfAnExistingCustomValueIsNotAddedTwice() {
        XCTAssertEqual(evaluate("Berenjena", existing: ["berenjena"]), .duplicate)
    }

    func testTheItemLimitIsEnforced() {
        XCTAssertEqual(evaluate("Tercero", existing: ["Uno", "Dos"]), .full)
    }

    func testAQuestionThatDoesNotAcceptFreeTextRejectsEverything() throws {
        let plain = try OnboardingFixtures.question(OnboardingFixtures.gate("g"))
        XCTAssertEqual(CustomValue.evaluate("anything", for: plain, existing: []), .rejected)
    }
}
