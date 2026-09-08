//
//  BundledQuestionnaireTests.swift
//  KaloriasTests
//
//  The copy that ships inside the app. It is the questionnaire a user gets on a
//  first launch with no signal — the moment nobody is watching — so the
//  properties CI checks on the server's content are checked here too, against
//  the bytes actually in the bundle.
//
//  This is also what catches the resource silently not being copied: without it,
//  the failure surfaces as an empty first-launch screen on a device with no
//  network, which is close to untestable by hand.
//

import XCTest
@testable import Kalorias

nonisolated final class BundledQuestionnaireTests: XCTestCase {

    private let storage = OnboardingStorage(bundle: Bundle(for: BundledQuestionnaireTests.self))

    /// The tests run against the test bundle, so resolve the app's resource by
    /// asking the storage type the way the app does — and fall back to the main
    /// bundle when the resource lives there.
    private func bundled(_ code: String) throws -> Questionnaire {
        if let questionnaire = storage.bundledQuestionnaire(languageCode: code) { return questionnaire }
        let main = OnboardingStorage(bundle: .main)
        return try XCTUnwrap(main.bundledQuestionnaire(languageCode: code),
                             "onboarding.\(code).json is not in the app bundle")
    }

    func testSpanishCopyIsPresentAndDecodes() throws {
        let questionnaire = try bundled("es")
        XCTAssertEqual(questionnaire.locale, "es")
        XCTAssertEqual(questionnaire.schemaVersion, Questionnaire.supportedSchemaVersion)
        XCTAssertFalse(questionnaire.questions.isEmpty)
    }

    func testEnglishCopyIsPresentAndMatchesTheSpanishStructure() throws {
        let es = try bundled("es")
        let en = try bundled("en")
        XCTAssertEqual(en.questions.map(\.id), es.questions.map(\.id))
        XCTAssertEqual(en.questions.map(\.type), es.questions.map(\.type))
        XCTAssertEqual(
            en.questions.map { $0.options.map(\.id) },
            es.questions.map { $0.options.map(\.id) }
        )
    }

    func testAnUnknownLanguageFallsBackToSpanish() throws {
        let main = OnboardingStorage(bundle: .main)
        XCTAssertEqual(main.bundledQuestionnaire(languageCode: "de")?.locale, "es")
    }

    func testQuestionIdsAreUniqueAcrossTheWholeQuestionnaire() throws {
        let ids = try bundled("es").questions.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    /// A condition pointing at a later question never comes true. Nothing fails,
    /// nothing logs — the question simply never appears.
    func testEveryConditionPointsAtAnEarlierQuestion() throws {
        let questions = try bundled("es").questions
        let position = Dictionary(uniqueKeysWithValues: questions.enumerated().map { ($1.id, $0) })

        for (index, question) in questions.enumerated() {
            for condition in question.visibleIf?.conditions ?? [] {
                let target = try XCTUnwrap(
                    position[condition.questionId],
                    "\(question.id) depends on \(condition.questionId), which does not exist"
                )
                XCTAssertLessThan(target, index,
                                  "\(question.id) depends on \(condition.questionId), declared after it")
            }
        }
    }

    /// A condition comparing against an option that is not on the referenced
    /// question's list is a typo that hides a question forever.
    func testEveryConditionNamesARealOption() throws {
        let questionnaire = try bundled("es")
        for question in questionnaire.questions {
            for condition in question.visibleIf?.conditions ?? [] {
                guard let value = condition.value else { continue }
                let target = try XCTUnwrap(questionnaire.question(id: condition.questionId))
                XCTAssertNotNil(target.option(id: value),
                                "\(question.id) expects \(value), not an option of \(target.id)")
            }
        }
    }

    /// The canonical unit must be a no-op conversion, or every submitted weight
    /// is wrong by a constant factor.
    func testCanonicalUnitsConvertByOne() throws {
        for question in try bundled("es").questions {
            guard let measure = question.measure else { continue }
            let canonical = try XCTUnwrap(measure.unit(id: measure.canonicalUnit),
                                          "\(question.id): canonicalUnit is not in `units`")
            XCTAssertEqual(canonical.components.count, 1)
            XCTAssertEqual(canonical.components[0].toCanonical, 1)
        }
    }

    func testOnlyOneOptionPerQuestionIsExclusive() throws {
        for question in try bundled("es").questions {
            XCTAssertLessThanOrEqual(question.options.filter(\.isExclusive).count, 1, question.id)
        }
    }
}
