//
//  MealDetailsView.swift
//  Kalorias
//
//  Expanded view of a saved meal: larger photo, full itemized breakdown, total
//  calories, and the date/time taken. Native Liquid Glass + `AppColor` tokens.
//

import SwiftUI

struct MealDetailsView: View {
    let entry: MealEntry
    /// Where this meal sits on its own week's scale. Passed in from the history
    /// list so both screens show the same colour (FR-005/FR-006) — never
    /// re-derived here, which would let the two drift apart.
    let colorStep: CalorieColorStep
    let imageStore: any ImageStoring

    @State private var image: UIImage?
    /// Per-ingredient crops of `image`, keyed by `StoredFood.id`. Empty until the
    /// crop pass finishes — the screen renders first (FR-018) — and permanently
    /// empty for meals saved before regions were recorded.
    @State private var thumbnails: [UUID: UIImage] = [:]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                photo

                VStack(spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(entry.totalCalories)")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(colorStep.color)
                        Text("history.kcalUnit")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Text("mealDetails.totalLabel")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .accessibilityIdentifier("mealDetails.total")

                Text(entry.capturedAt, format: .dateTime.weekday().day().month().year().hour().minute())
                    .font(.footnote)
                    .foregroundStyle(AppColor.textSecondary)

                foodList
            }
            .padding(24)
        }
        // Reserve room for the floating bottom bar INSIDE the scroll container.
        // A root-level safe-area inset does not reach here — NavigationStack
        // consumes it (see RootView).
        .contentMargins(.bottom, BottomBar.scrollClearance, for: .scrollContent)
        .background(AppColor.surfacePrimary)
        .navigationTitle(Text(entry.title))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("mealDetails.screen")
        .task(id: entry.imageFileName) {
            let name = entry.imageFileName
            let store = imageStore
            let loaded = await Task.detached { store.loadImage(named: name) }.value
            image = loaded

            // Every crop in ONE detached pass over the image already in memory.
            // A `.task` per row would cost one decode per ingredient on top of the
            // load above; a 15-ingredient meal would do 15 of them (FR-018).
            guard let loaded else { return }
            // Captured into locals so the detached closure reads nothing
            // MainActor-isolated.
            let foods = entry.foods
            let maxDimension = Self.thumbnailMaxDimension
            thumbnails = await Task.detached {
                ImageCropper.crops(
                    for: foods, from: loaded, maxDimension: maxDimension
                )
            }.value
        }
    }

    /// Rendered size of an ingredient thumbnail, in points.
    private static let thumbnailSide: CGFloat = 44
    /// Crops are rasterized at 3× the displayed size to stay sharp on Retina.
    private static let thumbnailMaxDimension: CGFloat = 132

    @ViewBuilder
    private var photo: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                AppColor.surfaceElevated
                    .overlay(Image(systemName: "fork.knife").font(.largeTitle).foregroundStyle(AppColor.textSecondary))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
        .clipShape(.rect(cornerRadius: 28))
    }

    private var foodList: some View {
        VStack(spacing: 12) {
            ForEach(entry.foods) { food in
                HStack(alignment: .top, spacing: 12) {
                    thumbnail(for: food)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(food.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(AppColor.textPrimary)
                            Spacer()
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text("\(food.calories)")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(AppColor.textPrimary)
                                Text("history.kcalUnit")
                                    .font(.caption)
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                        }
                        if food.hasMacros {
                            HStack(spacing: 14) {
                                macro("analysis.macro.protein", food.protein, AppColor.macroProtein)
                                macro("analysis.macro.carbs", food.carbs, AppColor.macroCarbs)
                                macro("analysis.macro.fat", food.fat, AppColor.macroFat)
                            }
                        }
                    }
                }
                // The shared Liquid Glass helper rather than an ad-hoc
                // `.glassEffect(...)` — Principle III requires glass to go through
                // one place. `padding: 16` reproduces the previous inset exactly.
                .glassCard(padding: 16)
            }
        }
        .accessibilityIdentifier("mealDetails.foodList")
    }

    /// A crop of the meal photo showing this ingredient, or the same placeholder the
    /// header photo falls back to.
    ///
    /// Fixed size, never flexible width: at large Dynamic Type sizes the row grows
    /// in height and the text wraps, rather than the image squeezing the text
    /// (FR-012). Decorative and hidden from assistive technology — the name and
    /// calories beside it are the informative content and are already announced, so
    /// labelling a generated crop would only add noise (FR-022).
    private func thumbnail(for food: StoredFood) -> some View {
        Group {
            if let crop = thumbnails[food.id] {
                Image(uiImage: crop)
                    .resizable()
                    .scaledToFill()
            } else {
                AppColor.surfaceElevated
                    .overlay(
                        Image(systemName: "fork.knife")
                            .font(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    )
            }
        }
        .frame(width: Self.thumbnailSide, height: Self.thumbnailSide)
        .clipShape(.rect(cornerRadius: 10))
        .accessibilityHidden(true)
        .accessibilityIdentifier("mealDetails.food.thumbnail")
    }

    @ViewBuilder
    private func macro(_ key: LocalizedStringKey, _ grams: Double?, _ color: Color) -> some View {
        if let grams {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(key).font(.caption2).foregroundStyle(AppColor.textSecondary)
                Text("\(Int(grams.rounded()))g").font(.caption2.weight(.medium)).foregroundStyle(AppColor.textPrimary)
            }
        }
    }
}
