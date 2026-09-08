//
//  OnboardingFixtures.swift
//  KaloriasTests
//
//  Test questionnaires, built the only way the app can build one: by decoding
//  JSON. The model types have no memberwise initialiser on purpose — every
//  fixture therefore exercises the real decoder, so a test cannot pass against a
//  shape the app could never actually receive.
//

import Foundation
@testable import Kalorias

nonisolated enum OnboardingFixtures {

    static func questionnaire(_ json: String) throws -> Questionnaire {
        try JSONDecoder().decode(Questionnaire.self, from: Data(json.utf8))
    }

    static func question(_ json: String) throws -> Question {
        try JSONDecoder().decode(Question.self, from: Data(json.utf8))
    }

    /// Wraps sections in the minimum a questionnaire needs.
    static func wrap(sections: String) -> String {
        """
        {
          "onboardingId": "test_v1", "schemaVersion": 1, "contentVersion": 1,
          "locale": "es", "sections": [\(sections)]
        }
        """
    }

    static func section(id: String, questions: String, countsTowardProgress: Bool = true) -> String {
        """
        { "id": "\(id)", "title": "\(id)", "countsTowardProgress": \(countsTowardProgress),
          "questions": [\(questions)] }
        """
    }

    /// A yes/no gate.
    static func gate(_ id: String) -> String {
        """
        { "id": "\(id)", "type": "single_choice", "prompt": ["\(id)?"],
          "options": [{ "id": "yes", "title": "Yes" }, { "id": "no", "title": "No" }] }
        """
    }

    /// A question shown only when `gate` was answered `value`.
    static func gated(_ id: String, on gate: String, equals value: String) -> String {
        """
        { "id": "\(id)", "type": "text", "prompt": ["\(id)"], "text": { "maxLength": 40 },
          "visibleIf": { "all": [{ "questionId": "\(gate)", "operator": "equals", "value": "\(value)" }] } }
        """
    }

    static func text(_ id: String) -> String {
        """
        { "id": "\(id)", "type": "text", "prompt": ["\(id)"], "text": { "maxLength": 40 } }
        """
    }

    /// The weight wheel, kg canonical with a pounds alternative — the shape the
    /// conversion rules are argued about on.
    static let weightMeasure = """
    { "id": "weight", "type": "measure", "prompt": ["Weight?"],
      "measure": {
        "widget": "wheel", "canonicalUnit": "kg", "defaultUnit": "kg",
        "units": [
          { "id": "kg", "label": "kg", "components": [
            { "id": "kg", "label": "kg", "min": 30, "max": 250, "step": 0.1, "default": 70,
              "decimals": 1, "toCanonical": 1 }] },
          { "id": "lb", "label": "lb", "components": [
            { "id": "lb", "label": "lb", "min": 66, "max": 550, "step": 0.2, "default": 154,
              "decimals": 1, "toCanonical": 0.45359237 }] }
        ] } }
    """

    /// Height, whose `ft/in` unit is the reason units carry an array of
    /// components rather than one scale factor.
    static let heightMeasure = """
    { "id": "height", "type": "measure", "prompt": ["Height?"],
      "measure": {
        "widget": "wheel", "canonicalUnit": "cm", "defaultUnit": "cm",
        "units": [
          { "id": "cm", "label": "cm", "components": [
            { "id": "cm", "label": "cm", "min": 120, "max": 240, "step": 1, "default": 170,
              "decimals": 0, "toCanonical": 1 }] },
          { "id": "ft_in", "label": "ft/in", "components": [
            { "id": "ft", "label": "ft", "min": 4, "max": 7, "step": 1, "default": 5,
              "decimals": 0, "toCanonical": 30.48 },
            { "id": "in", "label": "in", "min": 0, "max": 11, "step": 1, "default": 7,
              "decimals": 0, "toCanonical": 2.54 }] }
        ] } }
    """
}
