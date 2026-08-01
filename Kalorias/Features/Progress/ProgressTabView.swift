//
//  ProgressTabView.swift
//  Kalorias
//
//  The Progress tab: a weekly summary card and a 7-day calorie chart, both built
//  only from meals already saved by feature 003. Nothing here is written.
//
//  NAMING: this is `ProgressTabView`, deliberately NOT `ProgressView` — that name
//  belongs to SwiftUI's built-in spinner, and shadowing it inside the module would
//  silently redirect any future `ProgressView()` to this dashboard.
//
//  This view is the ONLY place that reads `Calendar.current` and `Date()`; the
//  statistics functions take them as parameters so they stay deterministic under
//  test (constitution Principle II). Because "now" is resolved at body evaluation,
//  day and week rollover re-resolve when the tab is next presented — no timer.
//

import SwiftData
import SwiftUI

struct ProgressTabView: View {
    @Query(sort: \MealEntry.capturedAt, order: .reverse) private var entries: [MealEntry]

    /// How many days the calorie chart covers.
    private let chartDayCount = 7

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    emptyState
                } else {
                    widgets
                }
            }
            .navigationTitle("progress.title")
        }
        .accessibilityIdentifier("screen.progress")
    }

    private var widgets: some View {
        // Read the environment's calendar and clock once, here, and pass them
        // down: everything below this line is a pure function of them.
        let calendar = Calendar.current
        let now = Date()
        let tallies = ProgressStatistics.dailyTallies(
            from: entries, calendar: calendar, endingOn: now, dayCount: chartDayCount
        )
        let summary = ProgressStatistics.weekSummary(
            from: entries, calendar: calendar, now: now
        )

        return ScrollView {
            VStack(spacing: 16) {
                WeekSummaryCard(summary: summary)
                DailyCaloriesChart(
                    tallies: tallies,
                    average: ProgressStatistics.averageOfLoggedDays(tallies),
                    bounds: ProgressStatistics.loggedBounds(tallies)
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        // Reserve room for the floating bottom bar INSIDE the scroll container.
        // A root-level safe-area inset does not reach here — NavigationStack
        // consumes it (see RootView).
        .contentMargins(.bottom, BottomBar.scrollClearance, for: .scrollContent)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("progress.empty.title")
            } icon: {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundStyle(AppColor.brandPrimary)
            }
        } description: {
            Text("progress.empty.message")
        }
        .accessibilityIdentifier("progress.empty")
    }
}
