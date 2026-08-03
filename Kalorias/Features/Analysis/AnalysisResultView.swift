//
//  AnalysisResultView.swift
//  Kalorias
//
//  Presents the photo-analysis flow: analyzing → total + breakdown / no-food /
//  error. Native Liquid Glass surfaces, `AppColor` tokens, localized copy. A
//  failure never shows a calorie number (FR-011). `onFinish` returns to the
//  main screen; `onRetake` returns to the live camera (FR-012/FR-015).
//

import SwiftUI

struct AnalysisResultView: View {
    @State var store: CalorieAnalysisStore
    let onFinish: () -> Void
    let onRetake: () -> Void

    var body: some View {
        ZStack {
            AppColor.surfacePrimary.ignoresSafeArea()

            switch store.state {
            case .analyzing:
                analyzing
            case .result(let analysis):
                result(analysis)
            case .noFood:
                noFood
            case .failed(let error):
                failed(error)
            }
        }
        .accessibilityIdentifier("analysis.screen")
        .onAppear { store.start() }
    }

    // MARK: Analyzing

    private var analyzing: some View {
        VStack(spacing: 24) {
            thumbnail
            ProgressView()
                .controlSize(.large)
            Text("analysis.analyzing")
                .font(.headline)
                .foregroundStyle(AppColor.textSecondary)
            Button(role: .cancel, action: cancel) {
                Text("analysis.cancel").padding(.horizontal, 24)
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("analysis.cancelButton")
        }
        .padding(32)
        .accessibilityIdentifier("analysis.loading")
    }

    // MARK: Result (total + breakdown)

    private func result(_ analysis: CalorieAnalysis) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    thumbnail

                    VStack(spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(analysis.totalCalories)")
                                .font(.system(size: 56, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColor.brandPrimary)
                            Text("analysis.kcalUnit")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(AppColor.textSecondary)
                        }

                        Text("analysis.totalLabel")
                            .font(.subheadline)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("analysis.total")

                    foodList(analysis.items)
                }
                .padding(24)
            }

            Button(action: onFinish) {
                Text("analysis.done").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(AppColor.brandPrimaryFill)
            .controlSize(.large)
            .padding(24)
            .accessibilityIdentifier("analysis.doneButton")
        }
    }

    private func foodList(_ items: [FoodItem]) -> some View {
        VStack(spacing: 12) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(item.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(AppColor.textPrimary)
                        Spacer()
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(item.calories)")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(AppColor.textPrimary)
                            Text("analysis.kcalUnit")
                                .font(.caption)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                    if item.hasMacros {
                        HStack(spacing: 14) {
                            macro("analysis.macro.protein", item.proteinGrams, AppColor.macroProtein)
                            macro("analysis.macro.carbs", item.carbsGrams, AppColor.macroCarbs)
                            macro("analysis.macro.fat", item.fatGrams, AppColor.macroFat)
                        }
                    }
                }
                .padding(16)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
            }
        }
        .accessibilityIdentifier("analysis.foodList")
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

    // MARK: No food

    private var noFood: some View {
        messageState(
            systemImage: "questionmark.circle",
            messageKey: "analysis.noFood",
            messageIdentifier: "analysis.noFoodMessage",
            primaryTitle: "analysis.retake",
            primaryIdentifier: "analysis.retakeButton",
            primaryAction: onRetake
        )
    }

    // MARK: Failure

    private func failed(_ error: AnalysisError) -> some View {
        messageState(
            systemImage: "exclamationmark.triangle",
            messageKey: LocalizedStringKey(error.messageKey),
            messageIdentifier: "analysis.errorMessage",
            primaryTitle: "analysis.retry",
            primaryIdentifier: "analysis.retryButton",
            primaryAction: { store.retry() }
        )
    }

    private func messageState(
        systemImage: String,
        messageKey: LocalizedStringKey,
        messageIdentifier: String,
        primaryTitle: LocalizedStringKey,
        primaryIdentifier: String,
        primaryAction: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 20) {
            thumbnail
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(AppColor.warning)
            Text(messageKey)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppColor.textPrimary)
                .accessibilityIdentifier(messageIdentifier)

            VStack(spacing: 12) {
                Button(action: primaryAction) {
                    Text(primaryTitle).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(AppColor.brandPrimaryFill)
                .accessibilityIdentifier(primaryIdentifier)

                Button(role: .cancel, action: cancel) {
                    Text("analysis.cancel").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("analysis.cancelButton")
            }
            .controlSize(.large)
            .padding(.horizontal, 24)
        }
        .padding(32)
    }

    // MARK: Shared

    @ViewBuilder
    private var thumbnail: some View {
        if let image = store.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 120, height: 120)
                .clipShape(.rect(cornerRadius: 24))
        }
    }

    private func cancel() {
        store.cancel()
        onFinish()
    }
}
