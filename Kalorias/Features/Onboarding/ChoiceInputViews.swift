//
//  ChoiceInputViews.swift
//  Kalorias
//
//  The two option-list inputs.
//
//  SINGLE CHOICE ADVANCES ON TAP. There is no confirm button, because adding one
//  costs a tap on every single question of the questionnaire to protect against
//  a mistake the user can undo by tapping their own answer.
//
//  MULTI CHOICE MUST CONFIRM, because "I have finished choosing" is not
//  observable any other way.
//
//  THE EXCLUSIVE OPTION IS NOT AN ORDINARY OPTION. Picking "None" clears the
//  rest; picking anything else clears "None"; and typing a free value clears it
//  too, on the same principle. Without that, "None + Broccoli" ends up in the
//  database and nothing ever complains.
//

import SwiftUI

struct SingleChoiceInput: View {
    let question: Question
    let selected: String?
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            ForEach(question.options) { option in
                Button {
                    onSelect(option.id)
                } label: {
                    OptionLabel(option: option, isSelected: option.id == selected)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct MultiChoiceInput: View {
    let question: Question
    /// The answer being edited, if this question already had one.
    let initial: OnboardingAnswer?
    let onConfirm: ([String], [String]) -> Void

    @State private var selected: Set<String> = []
    @State private var customValues: [String] = []
    @State private var draft: String = ""
    @FocusState private var isTyping: Bool

    private var canConfirm: Bool {
        let minimum = question.validation?.minSelections ?? (question.isRequired ? 1 : 0)
        return selected.count + customValues.count >= minimum
    }

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            ForEach(question.options) { option in
                Button {
                    toggle(option)
                } label: {
                    OptionLabel(option: option, isSelected: selected.contains(option.id))
                }
                .buttonStyle(.plain)
            }

            ForEach(customValues, id: \.self) { value in
                Button {
                    customValues.removeAll { $0 == value }
                } label: {
                    HStack(spacing: AppSpacing.md) {
                        Text(value)
                            .rowTitleRole()
                            .foregroundStyle(AppColor.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppColor.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.md)
                    .background(AppColor.surfaceElevated, in: .rect(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(AppColor.brandPrimary, lineWidth: 2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(value)
                .accessibilityHint(Text("onboarding.custom.removeHint"))
            }

            if let config = question.allowsCustom, config.enabled, customValues.count < config.maxItems {
                HStack(spacing: AppSpacing.sm) {
                    TextField(config.placeholder ?? config.label, text: $draft)
                        .textFieldStyle(.plain)
                        .focused($isTyping)
                        .submitLabel(.done)
                        .onSubmit(commitDraft)
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.vertical, AppSpacing.md)
                        .background(AppColor.surfaceElevated, in: .rect(cornerRadius: 14))

                    Button(action: commitDraft) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(AppColor.brandPrimary)
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel(config.label)
                }
            }

            Button {
                onConfirm(question.options.map(\.id).filter(selected.contains), customValues)
            } label: {
                Text(verbatim: question.confirmLabel ?? String(localized: "onboarding.confirm"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColor.brandPrimaryFill)
            .controlSize(.large)
            .disabled(canConfirm == false)
            .padding(.top, AppSpacing.sm)
        }
        .animation(AppMotion.subtle, value: customValues)
        .animation(AppMotion.subtle, value: selected)
        .onAppear(perform: loadInitial)
    }

    private func loadInitial() {
        guard case let .multi(optionIds, values) = initial else { return }
        selected = Set(optionIds)
        customValues = values
    }

    private func toggle(_ option: QuestionOption) {
        if selected.contains(option.id) {
            selected.remove(option.id)
            return
        }
        if option.isExclusive {
            selected = [option.id]
            customValues = []
        } else {
            selected.insert(option.id)
            clearExclusive()
        }
    }

    /// Adding anything means the exclusive option no longer holds.
    private func clearExclusive() {
        for option in question.options where option.isExclusive {
            selected.remove(option.id)
        }
    }

    private func commitDraft() {
        switch CustomValue.evaluate(draft, for: question, existing: customValues) {
        case .accepted(let value):
            customValues.append(value)
            clearExclusive()
            draft = ""
        case .matchesOption(let id):
            // They typed something already on the list. Tick it rather than
            // storing a near-duplicate the backend cannot match.
            selected.insert(id)
            clearExclusive()
            draft = ""
        case .duplicate:
            draft = ""
        case .rejected, .full:
            break
        }
        isTyping = false
    }
}
