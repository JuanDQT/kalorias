//
//  AnalysisResultView.swift
//  Kalorias
//
//  Presents the photo-analysis flow: analyzing → total + breakdown / no-food /
//  error. Native Liquid Glass surfaces, `AppColor` tokens, localized copy. A
//  failure never shows a calorie number (FR-011). `onFinish` returns to the
//  main screen; `onRetake` returns to the live camera (FR-012/FR-015).
//
//  ONLY THE FAILURE BRANCH KNOWS about the move to the Kalorias backend — the
//  analyzing, result and no-food states are untouched, because on the happy path
//  this feature is meant to be invisible.
//

import SwiftUI

struct AnalysisResultView: View {
    @State var store: CalorieAnalysisStore
    let onFinish: () -> Void
    let onRetake: () -> Void

    var body: some View {
        ZStack {
            AppColor.surfacePrimary.ignoresSafeArea()

            // The state machine used to SNAP: analyzing → result / noFood /
            // failed replaced the whole screen with no continuity, so the user
            // had to re-read it to work out what had changed. Principle III
            // defaults motion on for exactly this, and the animation comes from
            // the vocabulary rather than from a literal here (T055/T056).
            Group {
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
            .transition(AppMotion.standardTransition)
        }
        .animation(AppMotion.standard, value: store.state)
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
            primaryLabel: Text("analysis.retake"),
            primaryIdentifier: "analysis.retakeButton",
            primaryAction: onRetake
        )
    }

    // MARK: Failure

    /// Every failure is actionable — the action is just not the same one.
    ///
    /// A REJECTED PHOTO OFFERS RETAKE, NOT RETRY (rule U2 / FR-019): re-sending
    /// the same bytes cannot succeed, so a Retry button there is a dead end
    /// dressed as a way out. It reuses `analysis.retakeButton`, so the
    /// identifier keeps naming what the control *does*.
    ///
    /// A RATE LIMIT OFFERS RETRY, DISABLED, COUNTING DOWN (rule U3 / FR-020),
    /// and re-enables in place at zero with no navigation. The store refuses the
    /// retry independently of this `disabled` (rule U4), so the two cannot drift
    /// apart.
    ///
    /// No failure shows a calorie number, a request id, an HTTP status, a
    /// provider name, or the server's own message text (rules U1, U6).
    @ViewBuilder
    private func failed(_ error: AnalysisError) -> some View {
        switch error {
        case .photoRejected:
            messageState(
                systemImage: "exclamationmark.triangle",
                messageKey: LocalizedStringKey(error.messageKey),
                messageIdentifier: "analysis.errorMessage",
                primaryLabel: Text("analysis.retake"),
                primaryIdentifier: "analysis.retakeButton",
                primaryAction: onRetake
            )

        case .rateLimited:
            messageState(
                systemImage: "exclamationmark.triangle",
                messageKey: LocalizedStringKey(error.messageKey),
                messageIdentifier: "analysis.errorMessage",
                primaryLabel: retryLabel,
                primaryIdentifier: "analysis.retryButton",
                primaryDisabled: !store.canRetry,
                primaryAction: { store.retry() }
            )
            // The countdown ticks once a second and the control re-enables at
            // zero: both are observable state changes Principle III defaults on.
            // `subtle` because a 1 Hz counter animated any harder reads as the
            // screen being busy — and because no animation may delay the user's
            // retry, which is why this is 0.20 s and not the house 0.30 s
            // ("fluid is not busy").
            .animation(AppMotion.subtle, value: store.secondsUntilRetry)
            .animation(AppMotion.subtle, value: store.canRetry)

        case .noConnection, .timeout, .serviceError, .invalidResponse:
            messageState(
                systemImage: "exclamationmark.triangle",
                messageKey: LocalizedStringKey(error.messageKey),
                messageIdentifier: "analysis.errorMessage",
                primaryLabel: Text("analysis.retry"),
                primaryIdentifier: "analysis.retryButton",
                primaryAction: { store.retry() }
            )
        }
    }

    /// "Retry in 12 s" while cooling, plain "Retry" once it expires.
    ///
    /// Built with `String(format:)` over the localized pattern rather than by
    /// interpolating inside `Text(...)`: interpolation would derive the key
    /// `"analysis.retryIn %lld"`, which is not the key in the catalog, and the
    /// button would silently render that raw string instead.
    private var retryLabel: Text {
        guard store.secondsUntilRetry > 0 else { return Text("analysis.retry") }
        return Text(
            verbatim: String(format: String(localized: "analysis.retryIn"), store.secondsUntilRetry)
        )
    }

    private func messageState(
        systemImage: String,
        messageKey: LocalizedStringKey,
        messageIdentifier: String,
        primaryLabel: Text,
        primaryIdentifier: String,
        primaryDisabled: Bool = false,
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

            // The failure branch's own layout comes from the spacing ramp
            // (T059). `md` and `xl` are exactly the 12 and 24 that were here, so
            // nothing moves — what changes is that the numbers now have one
            // home. The rest of this file's literals belong to the features that
            // own those branches.
            VStack(spacing: AppSpacing.md) {
                Button(action: primaryAction) {
                    primaryLabel
                        .supportingTextRole()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(AppColor.brandPrimaryFill)
                .disabled(primaryDisabled)
                .accessibilityIdentifier(primaryIdentifier)

                Button(role: .cancel, action: cancel) {
                    Text("analysis.cancel").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("analysis.cancelButton")
            }
            .controlSize(.large)
            .padding(.horizontal, AppSpacing.xl)
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
