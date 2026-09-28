//
//  Questionnaire.swift
//  Kalorias
//
//  The onboarding questionnaire exactly as the backend serves it. The app knows
//  **seven question types**, never a question: adding, removing or rewording a
//  question is a deploy on the server, not an App Store release (see
//  kalorias-backend/specs/016-kalorias-onboarding/client-behavior.md).
//
//  DECODING IS STRICT ON PURPOSE. An unrecognised question type or structural
//  field requires an app update before the chat opens. Skipping a required
//  question could produce a plan from data that was never collected.
//
//  `prompt` IS ALWAYS AN ARRAY, one chat bubble per element, even when there is
//  one. A field that is sometimes a string and sometimes an array is the
//  cheapest way to grow an `if` in every layer of the stack.
//
//  THE PAYLOAD CARRIES NO URL. Where the app talks is `BackendEnvironment`'s
//  business; a destination that arrives inside a response is an open redirect
//  wearing a different hat.
//

import Foundation

// MARK: - Envelope

/// The `{ "data": … }` wrapper every Kalorias endpoint answers with. Decoding
/// straight into `Questionnaire` fails on every single response.
nonisolated struct QuestionnaireEnvelope: Decodable, Sendable {
    let data: Questionnaire
}

// MARK: - Questionnaire

nonisolated struct Questionnaire: Decodable, Equatable, Sendable {

    /// The structure this build understands. A payload declaring more than this
    /// is refused whole — see `OnboardingStore`.
    static let supportedSchemaVersion = 1

    /// Which questionnaire this is; allows more than one (`plan_v1`, …).
    let onboardingId: String
    /// The *structure* version. Rises only when a new type or field appears,
    /// which is the case that needs a new app.
    let schemaVersion: Int
    /// The *wording* version. Rises with every copy change, travels with the
    /// answers, and is what lets the backend read an `optionId` from months ago.
    let contentVersion: Int
    /// The language the server actually applied, which may not be the one asked
    /// for.
    let locale: String
    let sections: [QuestionnaireSection]

    /// Every question, in declaration order, with its section forgotten.
    ///
    /// The chat is one continuous thread: sections are a heading and a progress
    /// unit, not a screen the user moves between.
    var questions: [Question] { sections.flatMap(\.questions) }

    func question(id: String) -> Question? {
        questions.first { $0.id == id }
    }
}

nonisolated struct QuestionnaireSection: Decodable, Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    /// Sections that frame the flow rather than advance it — the welcome, the
    /// closing bubble — sit outside the progress count.
    let countsTowardProgress: Bool
    let questions: [Question]

    private enum CodingKeys: String, CodingKey {
        case id, title, subtitle, countsTowardProgress, questions
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        countsTowardProgress = try c.decodeIfPresent(Bool.self, forKey: .countsTowardProgress) ?? true
        questions = try c.decode([Question].self, forKey: .questions)
    }
}

// MARK: - Question

nonisolated enum QuestionType: String, Decodable, Sendable {
    /// Not a question: bubbles and a button. It still records an answer, or
    /// stepping back through an informational bubble cannot tell whether it was
    /// already shown.
    case info
    /// Advances on tap, with no confirm button.
    case singleChoice = "single_choice"
    /// Advances on `confirmLabel`.
    case multiChoice = "multi_choice"
    case text
    case number
    case date
    /// The wheel, with a unit switch.
    case measure
}

nonisolated struct Question: Decodable, Equatable, Sendable, Identifiable {
    /// **Unique across the whole questionnaire**, not just within its section.
    /// It is the key the answer is filed under, here and on the server.
    let id: String
    let type: QuestionType
    /// One chat bubble per element, in order.
    let prompt: [String]
    let isRequired: Bool
    let skipLabel: String?
    let continueLabel: String?
    let confirmLabel: String?
    let visibleIf: ConditionGroup?
    let options: [QuestionOption]
    let allowsCustom: AllowsCustom?
    let validation: Validation?
    let crossChecks: [CrossCheck]
    let text: TextConfig?
    let number: NumberConfig?
    let date: DateConfig?
    let measure: MeasureConfig?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, type, prompt, skipLabel, continueLabel, confirmLabel
        case visibleIf, options, allowsCustom, validation, crossChecks
        case text, number, date, measure
        case isRequired = "required"
    }

    private struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        init?(intValue: Int) {
            stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    init(from decoder: any Decoder) throws {
        let receivedKeys = try decoder.container(keyedBy: AnyCodingKey.self).allKeys
        let knownKeys = Set(CodingKeys.allCases.map(\.stringValue))
        guard receivedKeys.allSatisfy({ knownKeys.contains($0.stringValue) }) else {
            throw OnboardingError.updateRequired
        }

        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        let rawType = try c.decode(String.self, forKey: .type)
        guard let decodedType = QuestionType(rawValue: rawType) else {
            throw OnboardingError.updateRequired
        }
        type = decodedType
        prompt = try c.decode([String].self, forKey: .prompt)
        isRequired = try c.decodeIfPresent(Bool.self, forKey: .isRequired) ?? true
        skipLabel = try c.decodeIfPresent(String.self, forKey: .skipLabel)
        continueLabel = try c.decodeIfPresent(String.self, forKey: .continueLabel)
        confirmLabel = try c.decodeIfPresent(String.self, forKey: .confirmLabel)
        visibleIf = try c.decodeIfPresent(ConditionGroup.self, forKey: .visibleIf)
        options = try c.decodeIfPresent([QuestionOption].self, forKey: .options) ?? []
        allowsCustom = try c.decodeIfPresent(AllowsCustom.self, forKey: .allowsCustom)
        validation = try c.decodeIfPresent(Validation.self, forKey: .validation)
        crossChecks = try c.decodeIfPresent([CrossCheck].self, forKey: .crossChecks) ?? []
        text = try c.decodeIfPresent(TextConfig.self, forKey: .text)
        number = try c.decodeIfPresent(NumberConfig.self, forKey: .number)
        date = try c.decodeIfPresent(DateConfig.self, forKey: .date)
        measure = try c.decodeIfPresent(MeasureConfig.self, forKey: .measure)

        guard prompt.isEmpty == false else {
            throw DecodingError.dataCorruptedError(
                forKey: .prompt, in: c, debugDescription: "`prompt` must carry at least one bubble"
            )
        }
    }

    func option(id: String) -> QuestionOption? {
        options.first { $0.id == id }
    }

    /// The prompt as identifiable bubbles, keyed by question **and** position.
    ///
    /// Position alone is not an identity here: the thread puts several
    /// questions in one lazy container, every question has a bubble at index 0,
    /// and SwiftUI renders duplicate ids in a `LazyVStack` as undefined
    /// behaviour rather than as an error.
    var promptBubbles: [PromptBubble] {
        prompt.enumerated().map { PromptBubble(id: "\(id).\(($0.offset))", text: $0.element) }
    }

    /// Whether the option list can be typed into as well as tapped.
    var acceptsCustomValues: Bool { allowsCustom?.enabled == true }
}

/// One chat bubble of a question's prompt, with an id unique across the thread.
nonisolated struct PromptBubble: Identifiable, Equatable, Sendable {
    let id: String
    let text: String
}

nonisolated struct QuestionOption: Decodable, Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let description: String?
    /// A Unicode emoji, never an asset name or a URL: it renders at any Dynamic
    /// Type size, downloads nothing, and cannot break and leave the option
    /// unidentifiable.
    let emoji: String?
    /// The option that cancels the others — "I eat everything", "None". Without
    /// handling it you store "None + Broccoli".
    let isExclusive: Bool

    private enum CodingKeys: String, CodingKey {
        case id, title, description, emoji
        case isExclusive = "exclusive"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji)
        isExclusive = try c.decodeIfPresent(Bool.self, forKey: .isExclusive) ?? false
    }
}

// MARK: - Conditions

nonisolated enum ConditionOperator: String, Decodable, Sendable {
    case equals, notEquals, contains, notContains, answered, notAnswered
}

nonisolated struct Condition: Decodable, Equatable, Sendable {
    let questionId: String
    let op: ConditionOperator
    let value: String?

    private enum CodingKeys: String, CodingKey {
        case questionId, value
        case op = "operator"
    }
}

/// `all` or `any`, never nested. A case that needs nesting is clearer as an
/// intermediate question, which also reads better to whoever edits the content.
nonisolated struct ConditionGroup: Decodable, Equatable, Sendable {
    enum Kind: String, Sendable { case all, any }

    let kind: Kind
    let conditions: [Condition]

    private enum CodingKeys: String, CodingKey { case all, any }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let all = try c.decodeIfPresent([Condition].self, forKey: .all) {
            kind = .all
            conditions = all
        } else if let any = try c.decodeIfPresent([Condition].self, forKey: .any) {
            kind = .any
            conditions = any
        } else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Expected `all` or `any`")
            )
        }
    }

    init(kind: Kind, conditions: [Condition]) {
        self.kind = kind
        self.conditions = conditions
    }
}

// MARK: - Per-type configuration

nonisolated struct Validation: Decodable, Equatable, Sendable {
    let minSelections: Int?
    let maxSelections: Int?
    let minLength: Int?
    let maxLength: Int?
}

nonisolated struct AllowsCustom: Decodable, Equatable, Sendable {
    let enabled: Bool
    let label: String
    let placeholder: String?
    let maxItems: Int
    let maxLength: Int
}

nonisolated struct TextConfig: Decodable, Equatable, Sendable {
    let placeholder: String?
    let multiline: Bool
    let maxLength: Int

    private enum CodingKeys: String, CodingKey { case placeholder, multiline, maxLength }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        placeholder = try c.decodeIfPresent(String.self, forKey: .placeholder)
        multiline = try c.decodeIfPresent(Bool.self, forKey: .multiline) ?? false
        maxLength = try c.decode(Int.self, forKey: .maxLength)
    }
}

nonisolated struct NumberConfig: Decodable, Equatable, Sendable {
    let min: Double
    let max: Double
    let step: Double
    let `default`: Double?
    let decimals: Int
    let unit: String?
}

nonisolated struct DateConfig: Decodable, Equatable, Sendable {
    enum Mode: String, Decodable, Sendable { case date, dateTime }
    enum DisplayFormat: String, Decodable, Sendable { case short, long }

    let mode: Mode
    let minDate: DateToken
    let maxDate: DateToken
    let `default`: DateToken?
    let displayFormat: DisplayFormat?
}

// MARK: - Cross-question checks

/// A warning that depends on another answer: a goal weight above the current
/// one when the goal is to lose weight.
nonisolated struct CrossCheck: Decodable, Equatable, Sendable {
    enum Severity: String, Decodable, Sendable { case warning, error }
    enum Rule: String, Decodable, Sendable {
        case lessThan, greaterThan, lessThanOrEqual, greaterThanOrEqual, notEqual
    }

    let severity: Severity
    let rule: Rule
    /// The question whose value this one is compared against.
    let compareTo: String
    /// Only checked when this holds; absent means always.
    let when: ConditionGroup?
    let message: String

    /// Whether `value` satisfies the rule against `other` — i.e. whether the
    /// check *passes* and no message is shown.
    func passes(value: Double, other: Double) -> Bool {
        switch rule {
        case .lessThan: value < other
        case .greaterThan: value > other
        case .lessThanOrEqual: value <= other
        case .greaterThanOrEqual: value >= other
        case .notEqual: value != other
        }
    }
}
