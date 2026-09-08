//
//  MeasureWheelInput.swift
//  Kalorias
//
//  The wheel that takes a height or a weight, with the unit switch beside it.
//
//  THE CANONICAL VALUE SURVIVES A UNIT SWITCH UNTOUCHED. Switching converts it
//  for display and snaps that to the new unit's step; only moving a wheel
//  rewrites it. This is the one rule in the whole feature that is invisible when
//  broken: rewriting on every switch loses half a step each time, and kg → lb →
//  kg ten times quietly turns 84.4 kg into someone else. `MeasureConversionTests`
//  pins it.
//
//  IT OPENS IN THE UNIT THE PHONE USES, not the one the questionnaire suggests.
//  `defaultUnit` is a guess made by whoever wrote the content; the device's
//  measurement system is a setting the user actually chose.
//
//  AND IT OPENS WHERE THE LAST ANSWER LEFT IT, when the content says to
//  (`unitFollows` / `defaultFollows`): a goal weight should not make someone who
//  weighs in pounds pick pounds a second time.
//

import SwiftUI

struct MeasureWheelInput: View {
    let question: Question
    let initial: OnboardingAnswer?
    /// The display unit of the question named by `unitFollows`, if answered.
    let followedUnit: String?
    /// The canonical value of the question named by `defaultFollows`, if answered.
    let followedValue: Double?
    let onConfirm: (MeasureAnswer) -> Void

    /// The value of record, always in the question's canonical unit.
    @State private var canonical: Double = 0
    /// Where each wheel is sitting, in `unitId`.
    @State private var components: [String: Double] = [:]
    @State private var unitId: String = ""
    @State private var hasLoaded = false

    private var config: MeasureConfig? { question.measure }

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            if let config {
                if config.units.count > 1 {
                    Picker("", selection: unitBinding) {
                        ForEach(config.units) { unit in
                            Text(verbatim: unit.label).tag(unit.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel(Text("onboarding.measure.unit"))
                }

                if let unit = config.unit(id: unitId) {
                    HStack(spacing: 0) {
                        ForEach(unit.components) { component in
                            Picker("", selection: componentBinding(component)) {
                                ForEach(component.ticks, id: \.self) { tick in
                                    Text(verbatim: "\(component.formatted(tick)) \(component.label ?? unit.label)")
                                        .tag(tick)
                                }
                            }
                            .pickerStyle(.wheel)
                            .accessibilityLabel(Text(verbatim: component.label ?? unit.label))
                        }
                    }
                    .frame(height: 150)
                }

                Button {
                    onConfirm(
                        MeasureAnswer(
                            canonical: canonical,
                            unit: config.canonicalUnit,
                            displayUnit: unitId,
                            displayComponents: components
                        )
                    )
                } label: {
                    Text("onboarding.confirm").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColor.brandPrimaryFill)
                .controlSize(.large)
            }
        }
        .onAppear(perform: load)
    }

    // MARK: Bindings

    /// Switching units converts what is shown. It does **not** touch `canonical`
    /// — see the file comment.
    private var unitBinding: Binding<String> {
        Binding(
            get: { unitId },
            set: { newValue in
                guard let config, newValue != unitId else { return }
                unitId = newValue
                components = config.components(fromCanonical: canonical, unitId: newValue)
            }
        )
    }

    /// Moving a wheel is the only thing that rewrites `canonical`.
    private func componentBinding(_ component: UnitComponent) -> Binding<Double> {
        Binding(
            get: { components[component.id] ?? component.default },
            set: { newValue in
                guard let config else { return }
                components[component.id] = newValue
                canonical = config.canonicalValue(components: components, unitId: unitId) ?? canonical
            }
        )
    }

    // MARK: Loading

    private func load() {
        guard hasLoaded == false, let config else { return }
        hasLoaded = true

        // The unit: what the user already chose here, then what a followed
        // question was answered in, then the device, then the file.
        if case let .measure(existing) = initial {
            unitId = existing.displayUnit
            canonical = existing.canonical
            components = existing.displayComponents
            return
        }

        unitId = followedUnit
            ?? config.preferredUnitId(matching: Locale.current.measurementSystem)

        // The value: a followed question's answer, else the wheel's own default.
        if let followedValue {
            canonical = followedValue
        } else {
            canonical = config.canonicalValue(components: [:], unitId: config.canonicalUnit) ?? 0
        }
        components = config.components(fromCanonical: canonical, unitId: unitId)
    }
}
