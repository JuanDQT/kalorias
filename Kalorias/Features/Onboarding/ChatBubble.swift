//
//  ChatBubble.swift
//  Kalorias
//
//  The two things the onboarding thread is made of: what the app asks, and what
//  the user answered.
//
//  THE ANSWER BUBBLE IS THE BACK BUTTON. There is no chevron and no "previous"
//  control anywhere in this flow — in a chat the last answer is already on
//  screen, and it is the thing a user reaches for when they want to change it.
//  Making the bubble itself the target is fewer controls and a shorter path.
//
//  IT IS A REAL `Button`, not a `.onTapGesture`. That is what puts it in the
//  accessibility tree as something activatable, gives it the tap-target size
//  the system enforces, and lets VoiceOver announce the hint below.
//
//  THE EMOJI IS DECORATIVE. It sits beside a title that already says the same
//  thing, so leaving it in the accessibility label makes VoiceOver read
//  "fire, lose weight" — the constitution's rule that a raw glyph is never what
//  gets read aloud (Principle VI).
//

import SwiftUI

/// A bubble the app said. Left-aligned, on the elevated surface.
struct QuestionBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .supportingTextRole()
            .foregroundStyle(AppColor.textPrimary)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
            .background(AppColor.surfaceElevated, in: .rect(cornerRadius: 18))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A bubble the user said. Right-aligned, brand-filled, and tappable to change.
struct AnswerBubble: View {
    let text: String
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            Text(text)
                .supportingTextRole()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.white)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)
                .background(AppColor.brandPrimaryFill, in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityLabel(text)
        .accessibilityHint(Text("onboarding.edit.hint"))
    }
}

/// The heading that introduces a section of the thread.
struct SectionDivider: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            Text(title)
                .sectionLabelRole()
                .foregroundStyle(AppColor.brandPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppSpacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One option, as it appears in a choice list.
///
/// The emoji leads visually but comes last in the reading order, and is hidden
/// from accessibility entirely — see the file comment.
struct OptionLabel: View {
    let option: QuestionOption
    let isSelected: Bool

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            if let emoji = option.emoji {
                Text(emoji)
                    .font(.title2)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(option.title)
                    .rowTitleRole()
                    .foregroundStyle(AppColor.textPrimary)
                if let description = option.description {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColor.brandPrimary)
                    .accessibilityHidden(true)
            }
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.surfaceElevated, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isSelected ? AppColor.brandPrimary : .clear,
                    lineWidth: 2
                )
        }
        // One element, one announcement: title, then description, then state.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
