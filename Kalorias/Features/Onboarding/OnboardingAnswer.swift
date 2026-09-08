//
//  OnboardingAnswer.swift
//  Kalorias
//
//  What the user said, and how it reaches the server.
//
//  ANSWERS TRAVEL AS IDS, NEVER AS THE OPTION'S TEXT. The text changes with
//  every copy tweak and with the language; the id is a stable fact the backend
//  can reason about. The same rule is why free text lives in `customValues`,
//  apart from `optionIds`, instead of being mixed in with them: one is data, the
//  other is a string a human will have to read.
//
//  AN `optionId` IS ONLY UNIQUE INSIDE ITS QUESTION. `yes` belongs to three
//  different questions here. The key is always the pair.
//
//  A DATE IS STORED AS YEAR/MONTH/DAY, not as an instant. A birthday is a day on
//  a calendar, not a moment on a timeline: keeping a `Date` means the submitted
//  day depends on the time zone the phone happens to be in when the payload is
//  encoded, and a user who flies east becomes a day younger.
//
//  TWO ENCODINGS, DELIBERATELY. `Codable` here is Swift's synthesised one, used
//  only to save a half-finished onboarding to disk, where both writer and reader
//  are this app. What goes over the wire is `OnboardingSubmission.Entry`, which
//  is written out by hand — the server's shape is a contract, and letting a
//  compiler-generated format become it means a field rename silently changes the
//  API.
//
//  A MEASURE IS SUBMITTED IN THE CANONICAL UNIT, with `displayUnit` alongside so
//  the value can be shown back the way the user chose it. A number without a
//  fixed unit is a time bomb; a number with two possible units is the same bomb
//  with a longer fuse.
//

import Foundation

nonisolated enum OnboardingAnswer: Codable, Equatable, Sendable {
    /// An informational bubble the user has moved past. It is recorded, because
    /// otherwise stepping back cannot tell "not shown yet" from "already read".
    case acknowledged
    case single(optionId: String)
    case multi(optionIds: [String], customValues: [String])
    case text(String)
    case number(Double)
    case date(year: Int, month: Int, day: Int)
    case measure(MeasureAnswer)
    /// An optional question the user chose to pass on. Different from a question
    /// that was never asked, which is simply absent.
    case skipped

    /// What the transcript shows in place of the input once it is answered.
    func summary(for question: Question) -> String {
        switch self {
        case .acknowledged:
            question.continueLabel ?? ""
        case let .single(optionId):
            question.option(id: optionId)?.title ?? optionId
        case let .multi(optionIds, customValues):
            (optionIds.map { question.option(id: $0)?.title ?? $0 } + customValues)
                .formatted(.list(type: .and))
        case let .text(value):
            value
        case let .number(value):
            value.formatted()
        case let .date(year, month, day):
            Self.dayFormatted(year: year, month: month, day: day)
        case let .measure(measure):
            measure.summary(for: question)
        case .skipped:
            String(localized: "onboarding.answer.skipped", defaultValue: "Skipped")
        }
    }

    private static func dayFormatted(year: Int, month: Int, day: Int) -> String {
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = Calendar.current.date(from: components) else { return "" }
        return date.formatted(.dateTime.day().month(.wide).year())
    }

    /// The number a `crossChecks` rule compares. Only measures and numbers have
    /// one; everything else is not comparable and is skipped.
    var comparableValue: Double? {
        switch self {
        case let .measure(measure): measure.canonical
        case let .number(value): value
        default: nil
        }
    }
}

// MARK: - Measure

nonisolated struct MeasureAnswer: Codable, Equatable, Sendable {
    /// In the question's `canonicalUnit`. This is the value the backend reads.
    let canonical: Double
    /// The canonical unit's id, sent so the number is never unit-less on the wire.
    let unit: String
    /// The unit the user was looking at. Presentation only.
    let displayUnit: String
    /// The wheel positions in `displayUnit`, so the same wheel comes back
    /// exactly where it was left rather than re-derived and re-rounded.
    let displayComponents: [String: Double]

    func summary(for question: Question) -> String {
        guard let measure = question.measure, let unit = measure.unit(id: displayUnit) else {
            return canonical.formatted()
        }
        return unit.components
            .map { component in
                let value = displayComponents[component.id] ?? component.default
                return "\(component.formatted(value)) \(component.label ?? unit.label)"
            }
            .joined(separator: " ")
    }
}

// MARK: - Submission

/// The body of `POST /api/v1/kalorias/onboarding`. One request at the end, not
/// one per answer.
nonisolated struct OnboardingSubmission: Encodable, Sendable {
    /// Client-generated, reused across retries so a resend after a timeout does
    /// not create a second plan. Also travels as `Idempotency-Key`.
    let sessionId: UUID
    let onboardingId: String
    let schemaVersion: Int
    let contentVersion: Int
    let locale: String
    let startedAt: Date
    let completedAt: Date
    let answers: [Entry]

    /// One answer, flattened into the shape the contract documents. The `type`
    /// rides along so the server can read an entry without looking the question
    /// up first.
    nonisolated struct Entry: Encodable, Sendable {
        let questionId: String
        let type: QuestionType
        let answer: OnboardingAnswer

        private enum CodingKeys: String, CodingKey {
            case questionId, type, optionId, optionIds, customValues
            case value, unit, displayUnit, displayComponents
            case acknowledged, skipped
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(questionId, forKey: .questionId)
            try c.encode(type.rawValue, forKey: .type)

            switch answer {
            case .acknowledged:
                try c.encode(true, forKey: .acknowledged)
            case let .single(optionId):
                try c.encode(optionId, forKey: .optionId)
            case let .multi(optionIds, customValues):
                try c.encode(optionIds, forKey: .optionIds)
                try c.encode(customValues, forKey: .customValues)
            case let .text(value):
                try c.encode(value, forKey: .value)
            case let .number(value):
                try c.encode(value, forKey: .value)
            case let .date(year, month, day):
                try c.encode(String(format: "%04d-%02d-%02d", year, month, day), forKey: .value)
            case let .measure(measure):
                try c.encode(measure.canonical, forKey: .value)
                try c.encode(measure.unit, forKey: .unit)
                try c.encode(measure.displayUnit, forKey: .displayUnit)
                try c.encode(measure.displayComponents, forKey: .displayComponents)
            case .skipped:
                try c.encode(true, forKey: .skipped)
            }
        }
    }

    /// The encoder the submission is sent with. ISO-8601 timestamps, because
    /// `Date`'s default encoding is seconds since 2001 and nothing on the other
    /// side would guess that.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
