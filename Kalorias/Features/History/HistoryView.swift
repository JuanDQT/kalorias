//
//  HistoryView.swift
//  Kalorias
//
//  The History tab: a newest-first list of saved meals (reactive via @Query)
//  with an empty state, wrapped in a NavigationStack driven by the Router.
//  Tapping a meal drills into its details.
//

import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(Router.self) private var router
    @Query(sort: \MealEntry.capturedAt, order: .reverse) private var entries: [MealEntry]

    private let imageStore: any ImageStoring = DiskImageStore()

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.historyPath) {
            Group {
                if entries.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("history.title")
            .navigationDestination(for: MealEntry.self) { entry in
                // The colour comes from the SAME grouping that coloured the row,
                // so the two screens cannot disagree (FR-006). Re-deriving the
                // week bounds here would be a second implementation of "which
                // week is this", and that is exactly how they drift apart.
                MealDetailsView(
                    entry: entry,
                    colorStep: colorStep(for: entry),
                    imageStore: imageStore
                )
            }
        }
    }

    /// The week groups behind both the list and the details colour.
    ///
    /// `Calendar.current`, `Date()` and `Locale.current` are read HERE and in
    /// `list` only: the grouping and formatting types take them as parameters so
    /// they stay deterministic under test (Principle II). Because `now` is
    /// resolved at evaluation, the "current"/"previous" labels re-resolve when the
    /// week rolls over — no timer needed.
    private var weekGroups: [MealWeekGroup<MealEntry>] {
        MealWeekGrouping.groups(from: entries, calendar: .current, now: Date())
    }

    /// Where this meal sits on its own week's scale — the value the list row uses.
    private func colorStep(for entry: MealEntry) -> CalorieColorStep {
        guard let group = weekGroups.first(where: { group in
            group.items.contains { $0.id == entry.id }
        }) else {
            // Unreachable: feature 004's grouping partitions every entry. Present
            // only to avoid a force-unwrap (Principle I).
            return .low
        }
        return CalorieColorScale.step(
            for: entry.totalCalories,
            lowest: group.lowestCalories,
            highest: group.highestCalories
        )
    }

    private var list: some View {
        let calendar = Calendar.current
        let now = Date()
        let formatting = MealDateFormatting(
            locale: .current, calendar: calendar, timeZone: .current
        )
        let referenceYear = calendar.component(.year, from: now)
        let groups = MealWeekGrouping.groups(from: entries, calendar: calendar, now: now)

        return List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.items) { entry in
                        row(for: entry, in: group, formatting: formatting)
                    }
                } header: {
                    WeekSectionHeaderView(
                        label: group.label,
                        formatting: formatting,
                        referenceYear: referenceYear
                    )
                }
            }
        }
        .listStyle(.plain)
        // Reserve room for the floating bottom bar INSIDE the scroll container.
        // A root-level safe-area inset does not reach here — NavigationStack
        // consumes it (see RootView).
        .contentMargins(.bottom, BottomBar.scrollClearance, for: .scrollContent)
        .accessibilityIdentifier("history.list")
    }

    /// One tappable meal row. The display value is built here — once per
    /// grouping pass — so the row body never formats a date or computes a scale
    /// step (FR-017).
    private func row(
        for entry: MealEntry,
        in group: MealWeekGroup<MealEntry>,
        formatting: MealDateFormatting
    ) -> some View {
        Button {
            router.openMeal(entry)
        } label: {
            MealRowView(
                display: MealRowDisplay(
                    entry: entry,
                    formattedDate: formatting.rowTimestamp(for: entry.capturedAt),
                    // Scaled against THIS group's bounds, so each week is judged
                    // against itself (FR-012).
                    colorStep: CalorieColorScale.step(
                        for: entry.totalCalories,
                        lowest: group.lowestCalories,
                        highest: group.highestCalories
                    )
                ),
                imageStore: imageStore
            )
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("history.empty.title")
            } icon: {
                Image(systemName: "photo.on.rectangle.angled")
                    .foregroundStyle(AppColor.brandPrimary)
            }
        } description: {
            Text("history.empty.message")
        }
        .accessibilityIdentifier("history.empty")
    }
}
