//
//  MeasureConfig.swift
//  Kalorias
//
//  The wheel that takes a height or a weight, and the arithmetic that moves
//  between the units it offers.
//
//  EVERY UNIT IS AN ARRAY OF COMPONENTS, whether it has one or two. Feet and
//  inches are two wheels; kilos are one. That gives a single conversion rule —
//
//      canonical = Σ (component value × toCanonical)
//
//  — where a single scale factor per unit cannot express `ft/in` at all, and
//  `ft/in` is exactly the case that shows up the moment the app leaves Spain.
//
//  SWITCHING UNITS DOES NOT REWRITE THE CANONICAL VALUE. It converts it for
//  display and snaps that to the new unit's step; the canonical value is only
//  rewritten when the user actually moves the wheel. Rewriting on every switch
//  drifts the user's weight one rounding at a time — kg → lb → kg ten times is
//  a different person by the end.
//
//  THE FILE'S `defaultUnit` IS A SUGGESTION. `preferredUnitId(matching:)` lets
//  the device's measurement system win, because language does not imply units —
//  there are Spanish speakers in the United States and English speakers in
//  Spain — while the phone's setting is a choice the user actually made.
//

import Foundation

nonisolated struct MeasureConfig: Decodable, Equatable, Sendable {
    enum Widget: String, Decodable, Sendable { case wheel }

    let widget: Widget
    /// The unit answers are submitted in. Its single component has
    /// `toCanonical == 1`; the backend questionnaire validator enforces that in CI.
    let canonicalUnit: String
    let defaultUnit: String
    /// Open in the unit the named question was answered in — a goal weight
    /// should not ask someone who weighs in pounds to pick pounds twice.
    let unitFollows: String?
    /// Open near the value the named question was answered with.
    let defaultFollows: String?
    let units: [MeasureUnit]

    func unit(id: String) -> MeasureUnit? { units.first { $0.id == id } }

    /// The unit to open in, given the device's measurement system.
    ///
    /// The file's `defaultUnit` is the fallback: it is the best guess available
    /// before the device has an opinion, not an instruction.
    func preferredUnitId(matching system: Locale.MeasurementSystem?) -> String {
        guard let system else { return defaultUnit }
        let wantsMetric = system == .metric
        // A unit is "metric" when its canonical factor is 1 — kg for a weight,
        // cm for a height. Anything else is a conversion away from the canon.
        let match = units.first { unit in
            let isMetric = unit.components.count == 1 && unit.components[0].toCanonical == 1
            return isMetric == wantsMetric
        }
        return match?.id ?? defaultUnit
    }

    /// The canonical value the wheel currently shows.
    func canonicalValue(components: [String: Double], unitId: String) -> Double? {
        guard let unit = unit(id: unitId) else { return nil }
        return unit.components.reduce(into: 0.0) { total, component in
            total += (components[component.id] ?? component.default) * component.toCanonical
        }
    }

    /// Split a canonical value into the components of `unitId`, snapped to each
    /// component's step and clamped to its range.
    ///
    /// THE CARRY IS THE WHOLE JOB. With two components, rounding the fine one
    /// can push it past its maximum — 5 ft 11.6 in rounds to 5 ft 12 in, which
    /// is not a height anyone writes. It has to become 6 ft 0 in.
    func components(fromCanonical canonical: Double, unitId: String) -> [String: Double] {
        guard let unit = unit(id: unitId), unit.components.isEmpty == false else { return [:] }

        guard unit.components.count > 1 else {
            let only = unit.components[0]
            return [only.id: only.snap(canonical / only.toCanonical)]
        }

        let coarse = unit.components[0]
        let fine = unit.components[1]

        var coarseValue = (canonical / coarse.toCanonical).rounded(.down)
        // Rounded to the step but NOT clamped: clamping here would turn the 12
        // inches that need to carry into a legal 11, and the carry below would
        // never fire. That is the whole bug this shape avoids.
        var fineValue = fine.roundedToStep((canonical - coarseValue * coarse.toCanonical) / fine.toCanonical)

        if fineValue > fine.max {
            coarseValue += 1
            fineValue = fine.min
        }

        return [coarse.id: coarse.clamp(coarseValue), fine.id: fine.clamp(fineValue)]
    }
}

nonisolated struct MeasureUnit: Decodable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let components: [UnitComponent]
}

nonisolated struct UnitComponent: Decodable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String?
    let min: Double
    let max: Double
    let step: Double
    let `default`: Double
    /// How many decimals to show. Never fewer than `step` needs — CI checks it.
    let decimals: Int
    /// Multiply by this to reach the canonical unit.
    let toCanonical: Double

    /// Every value the wheel can stop on, low to high.
    var ticks: [Double] {
        guard step > 0, max > min else { return [min] }
        let count = Int(((max - min) / step).rounded())
        return (0...count).map { min + Double($0) * step }
    }

    func clamp(_ value: Double) -> Double { Swift.min(Swift.max(value, min), max) }

    /// Round to the nearest step, leaving the range alone.
    ///
    /// Kept apart from `snap` because a two-component unit needs to *see* the
    /// out-of-range result: 11.97 inches rounding to 12 is the signal to carry a
    /// foot, and clamping it to 11 first destroys that signal silently.
    func roundedToStep(_ value: Double) -> Double {
        guard step > 0 else { return value }
        return min + ((value - min) / step).rounded() * step
    }

    /// Round to the nearest step *and* clamp. A value that is in range but
    /// between two ticks has no wheel position to sit at.
    func snap(_ value: Double) -> Double { clamp(roundedToStep(value)) }

    /// The value as the wheel writes it, at this component's precision.
    func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(decimals)))
    }
}
