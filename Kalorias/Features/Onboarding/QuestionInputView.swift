//
//  QuestionInputView.swift
//  Kalorias
//
//  Picks the control for a question's `type`. This switch is the entire reason
//  the questionnaire can live on the server: the app knows seven ways to answer,
//  never a question, so new questions are a deploy rather than a release.
//
//  THERE IS NO `default:` BRANCH. A new type has to be handled here, and the
//  compiler is the one that says so. A `default` that quietly renders nothing is
//  how a required question turns into a plan calculated from data nobody
//  collected — the payload is refused at decoding time instead, and the app
//  falls back to its bundled copy.
//

import SwiftUI

struct QuestionInputView: View {
    let question: Question
    let initial: OnboardingAnswer?
    let followedUnit: String?
    let followedValue: Double?
    let onAnswer: (OnboardingAnswer) -> Void

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            switch question.type {
            case .info:
                InfoInput(question: question) { onAnswer(.acknowledged) }

            case .singleChoice:
                SingleChoiceInput(
                    question: question,
                    selected: selectedOptionId,
                    onSelect: { onAnswer(.single(optionId: $0)) }
                )

            case .multiChoice:
                MultiChoiceInput(question: question, initial: initial) { optionIds, customValues in
                    onAnswer(.multi(optionIds: optionIds, customValues: customValues))
                }

            case .text:
                TextAnswerInput(question: question, initial: initial) { onAnswer(.text($0)) }

            case .number:
                NumberAnswerInput(question: question, initial: initial) { onAnswer(.number($0)) }

            case .date:
                DateAnswerInput(question: question, initial: initial) { year, month, day in
                    onAnswer(.date(year: year, month: month, day: day))
                }

            case .measure:
                MeasureWheelInput(
                    question: question,
                    initial: initial,
                    followedUnit: followedUnit,
                    followedValue: followedValue,
                    onConfirm: { onAnswer(.measure($0)) }
                )
            }

            if question.isRequired == false {
                Button {
                    onAnswer(.skipped)
                } label: {
                    Text(verbatim: question.skipLabel ?? String(localized: "onboarding.skip"))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColor.textSecondary)
                .padding(.top, AppSpacing.xs)
            }
        }
    }

    private var selectedOptionId: String? {
        if case let .single(optionId) = initial { return optionId }
        return nil
    }
}

// MARK: - Info

/// Not a question: bubbles the user reads and moves past. It still records an
/// answer, or stepping back cannot tell "not shown yet" from "already read".
struct InfoInput: View {
    let question: Question
    let onContinue: () -> Void

    var body: some View {
        Button(action: onContinue) {
            Text(verbatim: question.continueLabel ?? String(localized: "onboarding.continue"))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppColor.brandPrimaryFill)
        .controlSize(.large)
    }
}

// MARK: - Text

struct TextAnswerInput: View {
    let question: Question
    let initial: OnboardingAnswer?
    let onSubmit: (String) -> Void

    @State private var value: String = ""
    @FocusState private var isFocused: Bool

    private var maxLength: Int { question.text?.maxLength ?? 280 }
    private var trimmed: String { value.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            Group {
                if question.text?.multiline == true {
                    TextField(
                        question.text?.placeholder ?? "",
                        text: $value,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                } else {
                    TextField(question.text?.placeholder ?? "", text: $value)
                }
            }
            .textFieldStyle(.plain)
            .focused($isFocused)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
            .background(AppColor.surfaceElevated, in: .rect(cornerRadius: 14))
            // Capped as it is typed, not on submit: a counter that lets you
            // write 400 characters and then silently keeps 280 is worse than a
            // field that stops.
            .onChange(of: value) { _, new in
                if new.count > maxLength { value = String(new.prefix(maxLength)) }
            }

            Button {
                onSubmit(trimmed)
            } label: {
                Text("onboarding.confirm").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColor.brandPrimaryFill)
            .controlSize(.large)
            .disabled(trimmed.count < (question.validation?.minLength ?? (question.isRequired ? 1 : 0)))
        }
        .onAppear {
            if case let .text(existing) = initial { value = existing }
        }
    }
}

// MARK: - Number

struct NumberAnswerInput: View {
    let question: Question
    let initial: OnboardingAnswer?
    let onSubmit: (Double) -> Void

    @State private var value: Double = 0

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            if let config = question.number {
                Stepper(
                    value: $value,
                    in: config.min...config.max,
                    step: config.step
                ) {
                    HStack(spacing: AppSpacing.xs) {
                        Text(verbatim: value.formatted(.number.precision(.fractionLength(config.decimals))))
                            .rowValueRole()
                        if let unit = config.unit {
                            Text(verbatim: unit).foregroundStyle(AppColor.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(AppColor.surfaceElevated, in: .rect(cornerRadius: 14))

                Button {
                    onSubmit(value)
                } label: {
                    Text("onboarding.confirm").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColor.brandPrimaryFill)
                .controlSize(.large)
            }
        }
        .onAppear {
            if case let .number(existing) = initial {
                value = existing
            } else {
                value = question.number?.default ?? question.number?.min ?? 0
            }
        }
    }
}

// MARK: - Date

struct DateAnswerInput: View {
    let question: Question
    let initial: OnboardingAnswer?
    let onSubmit: (Int, Int, Int) -> Void

    @State private var value = Date()

    private var calendar: Calendar { .current }

    /// The bounds, resolved here rather than at decoding time: `today-16y` means
    /// the device's today, in its calendar.
    private var range: ClosedRange<Date>? {
        guard let config = question.date,
              let lower = config.minDate.resolve(calendar: calendar),
              let upper = config.maxDate.resolve(calendar: calendar),
              lower <= upper
        else { return nil }
        return lower...upper
    }

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            Group {
                if let range {
                    DatePicker("", selection: $value, in: range, displayedComponents: .date)
                } else {
                    DatePicker("", selection: $value, displayedComponents: .date)
                }
            }
            .datePickerStyle(.wheel)
            .labelsHidden()

            Button {
                let parts = calendar.dateComponents([.year, .month, .day], from: value)
                guard let year = parts.year, let month = parts.month, let day = parts.day else { return }
                onSubmit(year, month, day)
            } label: {
                Text("onboarding.confirm").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColor.brandPrimaryFill)
            .controlSize(.large)
        }
        .onAppear(perform: load)
    }

    private func load() {
        if case let .date(year, month, day) = initial,
           let existing = calendar.date(from: DateComponents(year: year, month: month, day: day)) {
            value = existing
            return
        }
        // Opening on today when the range ends 16 years ago means the picker
        // starts pinned to its own maximum, which reads as broken.
        if let fallback = question.date?.default?.resolve(calendar: calendar) {
            value = fallback
        } else if let range {
            value = range.upperBound
        }
    }
}
