//
//  DailyCaloriesChart.swift
//  Kalorias
//
//  Widget 2 of the Progress tab: logged calories per day for the last 7 days, with
//  the average marked.
//
//  Two decisions worth knowing before editing:
//
//  1. A day with NO logs gets NO bar — it is a labelled empty slot. Any "ghost
//     bar" at a small height would read as a small value, which is exactly the
//     misreading FR-012 exists to prevent. The x scale is pinned to all 7 days so
//     the gap is visibly intentional rather than looking like a broken chart.
//  2. The x axis is CATEGORICAL (one slot per weekday label) rather than a date
//     scale. A date scale would have to be padded past the last day to avoid
//     clipping the edge bars, and empty days could drop out of the axis entirely.
//
//  This view RENDERS what it is given and computes nothing (Principle I).
//

import Charts
import SwiftUI

struct DailyCaloriesChart: View {
    let tallies: [DailyTally]
    /// Average across the LOGGED days only; `nil` when none are logged.
    let average: Int?
    /// Lowest/highest among the logged days, for the color scale; `nil` when none.
    let bounds: (lowest: Int, highest: Int)?

    /// One x-axis slot. The label doubles as the categorical plot value.
    private struct Slot: Identifiable {
        let id: Date
        let label: String
        let tally: DailyTally
    }

    private var slots: [Slot] {
        tallies.map {
            Slot(
                id: $0.day,
                label: $0.day.formatted(.dateTime.weekday(.abbreviated)),
                tally: $0
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("progress.chart.title")
                    .font(.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer(minLength: 8)
                if average != nil {
                    averageLegend
                }
            }
            chart
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Opaque: a dense chart card sitting directly on the app background.
        // Nothing behind it is worth revealing, so translucency here would be
        // finish rather than hierarchy (apple-design, materials and depth).
        .cardSurface()
        // The marks are hidden from assistive tech and replaced by one element
        // that reads every day INCLUDING the unlogged ones — a per-mark approach
        // cannot announce a day that has no mark (FR-028).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("progress.chart.title"))
        .accessibilityValue(Text(verbatim: accessibilitySummary))
        .accessibilityIdentifier("progress.chart")
    }

    private var averageLegend: some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(AppColor.textSecondary)
                .frame(width: 12, height: 1)
            Text("progress.chart.average")
                .font(.caption2)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(slots.filter(\.tally.hasLog)) { slot in
                BarMark(
                    x: .value("progress.chart.title", slot.label),
                    y: .value("history.kcalUnit", slot.tally.totalCalories)
                )
                .foregroundStyle(color(for: slot.tally))
                .cornerRadius(5)
            }

            if let average {
                RuleMark(y: .value("progress.chart.average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        // Pinning the domain to every slot is what keeps an unlogged day present
        // as a labelled gap instead of vanishing from the axis.
        .chartXScale(domain: slots.map(\.label))
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(AppColor.textSecondary.opacity(0.2))
                AxisValueLabel {
                    if let kcal = value.as(Int.self) {
                        Text(kcal, format: .number)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        Text(verbatim: label)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
        }
        .frame(height: 150)
    }

    /// Colored on the same scale the History tab uses, relative to the logged days
    /// in this window. With no bounds there is nothing to plot, so the fallback is
    /// never reached in practice.
    private func color(for tally: DailyTally) -> Color {
        guard let bounds else { return AppColor.successFill }
        return CalorieColorScale.step(
            for: tally.totalCalories,
            lowest: bounds.lowest,
            highest: bounds.highest
        ).fillColor
    }

    /// "Mon: 1,200 kcal, Tue: no data, …" — every day is represented, so an
    /// unlogged day is announced as missing rather than silently skipped.
    private var accessibilitySummary: String {
        let unit = String(localized: "history.kcalUnit")
        let noData = String(localized: "progress.chart.noData")

        return slots.map { slot in
            let value = slot.tally.hasLog
                ? "\(slot.tally.totalCalories.formatted(.number)) \(unit)"
                : noData
            return "\(slot.label): \(value)"
        }
        .joined(separator: ", ")
    }
}
