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
    /// Only the signed-in account's meals, filtered in the SwiftData predicate
    /// rather than after the fetch (feature 010, FR-042): two people can use the
    /// same phone over time, and the second must never load — let alone see —
    /// the first's food. Rows with no owner predate accounts and belong to
    /// nobody, so they are hidden too.
    @Environment(Router.self) private var router

    @Query private var entries: [MealEntry]

    init(ownerUserID: String? = nil) {
        // A sentinel rather than an optional comparison inside the predicate:
        // no account can own the empty string, because a session with an empty
        // user id is rejected before it is ever stored. So "no active account"
        // and "rows that belong to nobody" both correctly match nothing.
        let owner = ownerUserID ?? ""
        _entries = Query(
            filter: #Predicate<MealEntry> { $0.ownerUserID == owner },
            sort: \MealEntry.capturedAt,
            order: .reverse
        )
    }

    /// How many days the calorie chart covers.
    private let chartDayCount = 7

    var body: some View {
        @Bindable var router = router

        return NavigationStack(path: $router.progressPath) {
            Group {
                if entries.isEmpty {
                    emptyState
                } else {
                    widgets
                }
            }
            .navigationTitle("progress.title")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        router.openAccount()
                    } label: {
                        Label {
                            Text("account.title")
                        } icon: {
                            Image(systemName: "person.crop.circle")
                        }
                    }
                    .accessibilityIdentifier("progress.accountButton")
                }
            }
            .navigationDestination(for: ProgressRoute.self) { route in
                switch route {
                case .account:
                    AccountSettingsView()
                }
            }
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
