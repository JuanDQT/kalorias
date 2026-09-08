//
//  OnboardingSubmissionTests.swift
//  KaloriasTests
//
//  The wire format. It is written by hand rather than synthesised, so these
//  assertions are the only thing standing between a field rename and a silent
//  API change.
//

import XCTest
@testable import Kalorias

nonisolated final class OnboardingSubmissionTests: XCTestCase {

    private func encode(_ entry: OnboardingSubmission.Entry) throws -> [String: Any] {
        let data = try OnboardingSubmission.makeEncoder().encode(entry)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testSingleChoiceTravelsAsAnIdNotAsItsText() throws {
        let json = try encode(
            .init(questionId: "goal_primary", type: .singleChoice, answer: .single(optionId: "lose_weight"))
        )
        XCTAssertEqual(json["optionId"] as? String, "lose_weight")
        XCTAssertEqual(json["type"] as? String, "single_choice")
        XCTAssertNil(json["value"])
    }

    /// Ids and free text stay in separate fields: one is data the backend can
    /// reason about, the other is a string a human will have to read.
    func testMultiChoiceKeepsCustomValuesApartFromOptionIds() throws {
        let json = try encode(
            .init(
                questionId: "allergies",
                type: .multiChoice,
                answer: .multi(optionIds: ["lactose"], customValues: ["Sésamo"])
            )
        )
        XCTAssertEqual(json["optionIds"] as? [String], ["lactose"])
        XCTAssertEqual(json["customValues"] as? [String], ["Sésamo"])
    }

    func testMeasureIsSubmittedInTheCanonicalUnitWithTheDisplayUnitAlongside() throws {
        let json = try encode(
            .init(
                questionId: "weight_current",
                type: .measure,
                answer: .measure(
                    MeasureAnswer(canonical: 84.4, unit: "kg", displayUnit: "lb",
                                  displayComponents: ["lb": 186.0])
                )
            )
        )
        XCTAssertEqual(json["value"] as? Double, 84.4)
        XCTAssertEqual(json["unit"] as? String, "kg", "never unit-less on the wire")
        XCTAssertEqual(json["displayUnit"] as? String, "lb")
        XCTAssertEqual((json["displayComponents"] as? [String: Double])?["lb"], 186.0)
    }

    /// A birthday is a day on a calendar, not an instant. Encoding it as a
    /// `Date` makes the submitted day depend on the phone's time zone.
    func testDateIsSubmittedAsAPlainDay() throws {
        let json = try encode(
            .init(questionId: "birth_date", type: .date, answer: .date(year: 1993, month: 4, day: 18))
        )
        XCTAssertEqual(json["value"] as? String, "1993-04-18")
    }

    func testSingleDigitMonthsAndDaysArePadded() throws {
        let json = try encode(
            .init(questionId: "birth_date", type: .date, answer: .date(year: 2001, month: 2, day: 3))
        )
        XCTAssertEqual(json["value"] as? String, "2001-02-03")
    }

    func testSkippedIsDistinctFromAnyValue() throws {
        let json = try encode(.init(questionId: "extra_notes", type: .text, answer: .skipped))
        XCTAssertEqual(json["skipped"] as? Bool, true)
        XCTAssertNil(json["value"], "skipped is not an empty string")
    }

    func testAcknowledgedInfoBubblesAreRecorded() throws {
        let json = try encode(.init(questionId: "welcome", type: .info, answer: .acknowledged))
        XCTAssertEqual(json["acknowledged"] as? Bool, true)
    }

    func testTimestampsAreISO8601() throws {
        let submission = OnboardingSubmission(
            sessionId: UUID(),
            onboardingId: "plan_v1",
            schemaVersion: 1,
            contentVersion: 4,
            locale: "es",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            completedAt: Date(timeIntervalSince1970: 1_700_000_120),
            answers: []
        )
        let data = try OnboardingSubmission.makeEncoder().encode(submission)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["startedAt"] as? String, "2023-11-14T22:13:20Z")
        XCTAssertEqual(json["contentVersion"] as? Int, 4)
    }
}
