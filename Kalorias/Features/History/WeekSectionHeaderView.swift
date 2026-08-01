//
//  WeekSectionHeaderView.swift
//  Kalorias
//
//  The small header above each week's meals: "Semana actual" / "Semana anterior"
//  for the two most recent weeks, and a date range ("1 Febrero - 7 Febrero") for
//  older ones (FR-003 … FR-006).
//
//  This is where a `WeekHeaderLabel` becomes localized text; the grouping logic
//  itself stays free of the string catalog so it can be unit-tested without a
//  bundle. No line limit or fixed height, so large Dynamic Type sizes wrap
//  instead of clipping (FR-019).
//

import SwiftUI

struct WeekSectionHeaderView: View {
    let label: WeekHeaderLabel
    /// Shared with the rows so a whole grouping pass builds one formatter.
    let formatting: MealDateFormatting
    /// The current year; endpoints outside it carry their year (FR-006).
    let referenceYear: Int

    var body: some View {
        text
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppColor.textSecondary)
            .textCase(nil)
            .accessibilityIdentifier("history.week.header")
    }

    @ViewBuilder
    private var text: some View {
        switch label {
        case .currentWeek:
            Text("history.week.current")
        case .previousWeek:
            Text("history.week.previous")
        case .dateRange(let start, let end):
            // Already localized and composed by `MealDateFormatting`, so it is
            // passed through verbatim rather than re-interpreted as a key.
            Text(verbatim: formatting.weekRange(
                start: start, end: end, referenceYear: referenceYear
            ))
        }
    }
}
