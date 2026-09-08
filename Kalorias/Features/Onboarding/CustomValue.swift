//
//  CustomValue.swift
//  Kalorias
//
//  What happens to the text someone types into a `multi_choice` that accepts
//  free entries — "other allergy", "another food I don't like".
//
//  IT IS THE ONLY FREE TEXT IN THE WHOLE QUESTIONNAIRE, so it is the only place
//  where what reaches the server is not an id from a list the server wrote. That
//  makes it the one input worth being fussy about.
//
//  TYPING SOMETHING ALREADY IN THE LIST SELECTS IT INSTEAD. Someone who types
//  "brocoli" while "Brócoli" sits unticked two rows up should end up with the
//  option, not with a near-duplicate string the backend cannot match to
//  anything. Matching folds case *and* diacritics, because the accent is exactly
//  what a person in a hurry drops.
//
//  Pure and synchronous, so the rules are asserted in `CustomValueTests` rather
//  than typed into a simulator.
//

import Foundation

nonisolated enum CustomValue {

    nonisolated enum Outcome: Equatable, Sendable {
        /// Nothing usable was typed — empty, or whitespace only.
        case rejected
        /// It names an option that already exists; select that instead.
        case matchesOption(id: String)
        /// Already in this question's custom values; nothing to add.
        case duplicate
        /// No more entries are allowed here.
        case full
        case accepted(String)
    }

    /// Normalise and classify a typed value.
    static func evaluate(
        _ raw: String,
        for question: Question,
        existing: [String]
    ) -> Outcome {
        guard let config = question.allowsCustom, config.enabled else { return .rejected }

        // Newlines collapse to spaces rather than being rejected: a value pasted
        // from somewhere else arrives with them, and the user's intent is
        // obvious.
        let collapsed = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")

        guard collapsed.isEmpty == false else { return .rejected }
        let value = String(collapsed.prefix(config.maxLength))

        if let option = question.options.first(where: { matches($0.title, value) }) {
            return .matchesOption(id: option.id)
        }
        if existing.contains(where: { matches($0, value) }) {
            return .duplicate
        }
        guard existing.count < config.maxItems else { return .full }

        return .accepted(value)
    }

    /// Equal ignoring case, accents and surrounding space — "BROCOLI", "brócoli"
    /// and " Brócoli " are one food.
    private static func matches(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive], range: nil, locale: nil) == .orderedSame
    }
}
