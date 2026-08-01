//
//  MealRowView.swift
//  Kalorias
//
//  A history list row: thumbnail (left) | title + nutrition (center) | date +
//  total calories (right). Uses `AppColor` tokens and loads the thumbnail off
//  the main thread with a placeholder fallback.
//

import SwiftUI

/// Everything a row renders, computed once when the week groups are built so the
/// row body does no date formatting or scale work — that is what keeps the list
/// at 60fps as entries accumulate (FR-017).
struct MealRowDisplay: Identifiable {
    let entry: MealEntry
    let formattedDate: String
    /// Where this meal's total sits within ITS OWN week group (FR-011).
    let colorStep: CalorieColorStep

    var id: UUID { entry.id }
}

struct MealRowView: View {
    let display: MealRowDisplay
    let imageStore: any ImageStoring

    @State private var thumbnail: UIImage?

    private var entry: MealEntry { display.entry }

    var body: some View {
        HStack(spacing: 12) {
            thumbnailView

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                    .accessibilityIdentifier("history.row.title")
                nutritionSummary
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(display.formattedDate)
                    .font(.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .accessibilityIdentifier("history.row.date")
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    // The number is always present as text, so the color is a
                    // supplementary cue and never the sole carrier of meaning.
                    Text("\(entry.totalCalories)")
                        .font(.headline)
                        .foregroundStyle(calorieColor)
                    Text("history.kcalUnit")
                        .font(.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .accessibilityIdentifier("history.row.total")
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("history.row")
        .task(id: entry.imageFileName) {
            let name = entry.imageFileName
            let store = imageStore
            thumbnail = await Task.detached { store.loadImage(named: name) }.value
        }
    }

    /// Maps the calorie scale step to a palette token (constitution Principle
    /// III — every color comes from `AppColor`, never a literal). Green is this
    /// week's lightest meal, red its heaviest.
    private var calorieColor: Color {
        switch display.colorStep {
        case .low: AppColor.success
        case .moderate: AppColor.caution
        case .high: AppColor.warning
        case .veryHigh: AppColor.danger
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                AppColor.surfaceElevated
                    .overlay(Image(systemName: "fork.knife").foregroundStyle(AppColor.textSecondary))
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(.rect(cornerRadius: 12))
    }

    @ViewBuilder
    private var nutritionSummary: some View {
        let protein = sum(\.protein)
        let carbs = sum(\.carbs)
        let fat = sum(\.fat)
        if protein != nil || carbs != nil || fat != nil {
            HStack(spacing: 10) {
                macro("analysis.macro.protein", protein, AppColor.macroProtein)
                macro("analysis.macro.carbs", carbs, AppColor.macroCarbs)
                macro("analysis.macro.fat", fat, AppColor.macroFat)
            }
        }
    }

    @ViewBuilder
    private func macro(_ key: LocalizedStringKey, _ grams: Double?, _ color: Color) -> some View {
        if let grams {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text("\(Int(grams.rounded()))g")
                    .font(.caption2)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }

    /// Sum a macro across the entry's foods, or nil if none provide it.
    private func sum(_ keyPath: KeyPath<StoredFood, Double?>) -> Double? {
        let values = entry.foods.compactMap { $0[keyPath: keyPath] }
        return values.isEmpty ? nil : values.reduce(0, +)
    }
}
