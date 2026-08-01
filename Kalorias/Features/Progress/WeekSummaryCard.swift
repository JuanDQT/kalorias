//
//  WeekSummaryCard.swift
//  Kalorias
//
//  Widget 1 of the Progress tab: this week's logged calories, the average per
//  logged day, how many meals were logged, and the highest day — each compared
//  against the previous week where a comparison is possible.
//
//  This view RENDERS a `WeekSummary` and computes nothing (constitution
//  Principle I). Every figure is labelled as *logged*, never as the user's actual
//  intake, because logging is partial by nature (FR-021).
//

import SwiftUI

struct WeekSummaryCard: View {
    let summary: WeekSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("progress.week.title")
                .font(.headline)
                .foregroundStyle(AppColor.textPrimary)

            if summary.hasData {
                headline
                Divider()
                secondaryStats
            } else {
                Text("progress.week.noData")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .accessibilityIdentifier("progress.week.noData")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityIdentifier("progress.week.card")
    }

    // MARK: Headline total

    private var headline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("progress.week.total")
                .font(.caption)
                .foregroundStyle(AppColor.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(summary.totalCalories, format: .number)
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text("history.kcalUnit")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                changeBadge(summary.totalChange)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("progress.week.total")
    }

    // MARK: Secondary stats

    private var secondaryStats: some View {
        HStack(alignment: .top, spacing: 12) {
            stat(
                "progress.week.average",
                value: summary.averagePerLoggedDay.map { "\($0)" },
                change: summary.averageChange,
                identifier: "progress.week.average"
            )
            stat(
                "progress.week.meals",
                value: "\(summary.mealCount)",
                change: nil,
                identifier: "progress.week.meals"
            )
            stat(
                "progress.week.highest",
                value: highestDayText,
                change: nil,
                identifier: "progress.week.highest"
            )
        }
    }

    /// A `nil` value renders the explicit unavailable marker, never a bare `0`
    /// (FR-020) — "0 kcal" would assert something the data does not support.
    @ViewBuilder
    private func stat(
        _ label: LocalizedStringKey,
        value: String?,
        change: PeriodChange?,
        identifier: String
    ) -> some View {
        // Value first, label underneath: a label that wraps to two lines (e.g.
        // "Average per logged day", or any label at a large Dynamic Type size)
        // would otherwise push its value out of line with the neighbouring
        // columns. Labels stay unlimited so nothing clips (FR-028).
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let value {
                    Text(verbatim: value)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                } else {
                    Text("progress.unavailable")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.textSecondary)
                }
                changeBadge(change)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private var highestDayText: String? {
        guard let highest = summary.highestDay else { return nil }
        let weekday = highest.day.formatted(.dateTime.weekday(.abbreviated))
        return "\(weekday) · \(highest.totalCalories)"
    }

    // MARK: Change badge

    /// A `nil` change renders NOTHING — not a dash, not "0%" (FR-006). There is a
    /// difference between "did not change" and "there is nothing to compare
    /// against", and only the former gets a badge.
    ///
    /// The badge is intentionally NEUTRAL in color. This feature has no calorie
    /// goal, so eating more is neither good nor bad — coloring up red and down
    /// green would assert a judgement the feature deliberately does not make. The
    /// direction is carried by the glyph and by the VoiceOver label instead, which
    /// also keeps it off color alone (FR-028).
    @ViewBuilder
    private func changeBadge(_ change: PeriodChange?) -> some View {
        if let change {
            HStack(spacing: 2) {
                Image(systemName: symbolName(for: change.direction))
                if change.direction != .unchanged {
                    Text(verbatim: formattedPercent(change.percent))
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(AppColor.textSecondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(for: change))
        }
    }

    private func symbolName(for direction: ChangeDirection) -> String {
        switch direction {
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .unchanged: "equal"
        }
    }

    /// Built with `String(format:)` over the localized pattern rather than string
    /// interpolation inside `Text(...)`: interpolating would derive the key
    /// `"progress.change.up %@"`, which is not the key in the catalog, and the
    /// label would silently fall back to showing that raw key.
    private func accessibilityLabel(for change: PeriodChange) -> Text {
        switch change.direction {
        case .unchanged:
            return Text("progress.change.unchanged")
        case .up, .down:
            let pattern = String(
                localized: change.direction == .up ? "progress.change.up" : "progress.change.down"
            )
            return Text(verbatim: String(format: pattern, formattedPercent(change.percent)))
        }
    }

    /// Locale-aware percentage. `.percent` expects a fraction, so an integer
    /// magnitude of 12 becomes 0.12 before formatting.
    private func formattedPercent(_ percent: Int) -> String {
        (Double(percent) / 100).formatted(.percent.precision(.fractionLength(0)))
    }
}
