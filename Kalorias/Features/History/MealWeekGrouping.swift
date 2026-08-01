//
//  MealWeekGrouping.swift
//  Kalorias
//
//  Pure, testable partitioning of history entries into calendar-week groups
//  (constitution Principle I/II — grouping logic lives here, never in a view
//  body).
//
//  Week boundaries come from the supplied `Calendar`, whose `firstWeekday` is
//  region-driven, so Spain gets Monday–Sunday and the US gets Sunday–Saturday
//  for free (FR-002). The calendar and "now" are parameters rather than
//  `.current` / `Date()` reads so the logic is deterministic under test; the
//  view boundary supplies the real ones.
//
//  This file deliberately imports no SwiftUI: it yields `WeekHeaderLabel`, a
//  domain enum, and leaves localization and color to the view layer.
//

import Foundation

/// The minimum an item must expose to be grouped. Keeps this file independent
/// of SwiftData so the tests can run against plain fixtures.
nonisolated protocol WeekGroupable {
    var capturedAt: Date { get }
    var totalCalories: Int { get }
}

/// What a week section's header should say. Deliberately not a `String` — the
/// localization lives in the view layer, so grouping stays testable without a
/// bundle.
nonisolated enum WeekHeaderLabel: Equatable {
    case currentWeek
    case previousWeek
    /// Inclusive endpoints; the year is added per endpoint at render time.
    case dateRange(start: Date, end: Date)
}

/// One rendered week section. Non-empty by construction, so a week without
/// meals never produces a header (FR-008).
nonisolated struct MealWeekGroup<Item: WeekGroupable>: Identifiable {
    let id: Date
    let weekStart: Date
    /// The week's LAST day. `DateInterval.end` is exclusive — using it directly
    /// would render an off-by-one header ("2 Febrero - 8 Febrero").
    let weekEnd: Date
    let label: WeekHeaderLabel
    /// Newest first, never empty.
    let items: [Item]
    let lowestCalories: Int
    let highestCalories: Int
}

nonisolated enum MealWeekGrouping {

    /// Partition `items` into week groups, newest week first.
    ///
    /// - Parameters:
    ///   - items: entries in any order; within each group they are re-sorted
    ///     newest-first, so the caller's ordering does not matter.
    ///   - calendar: supplies `firstWeekday`; pass `Calendar.current` at the
    ///     view boundary.
    ///   - now: reference instant for the current / previous week labels.
    static func groups<Item: WeekGroupable>(
        from items: [Item],
        calendar: Calendar,
        now: Date
    ) -> [MealWeekGroup<Item>] {
        guard !items.isEmpty else { return [] }

        let currentWeekStart = weekStart(for: now, in: calendar)
        let previousWeekStart = calendar.date(byAdding: .day, value: -7, to: now)
            .map { weekStart(for: $0, in: calendar) }

        var buckets: [Date: [Item]] = [:]
        for item in items {
            buckets[weekStart(for: item.capturedAt, in: calendar), default: []].append(item)
        }

        return buckets.map { start, bucket in
            let sorted = bucket.sorted { $0.capturedAt > $1.capturedAt }
            let totals = sorted.map(\.totalCalories)
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start

            return MealWeekGroup(
                id: start,
                weekStart: start,
                weekEnd: end,
                label: label(
                    forWeekStarting: start,
                    endingOn: end,
                    currentWeekStart: currentWeekStart,
                    previousWeekStart: previousWeekStart
                ),
                items: sorted,
                // `sorted` is non-empty (it came from a bucket that exists), so
                // these defaults are unreachable; they avoid a force-unwrap.
                lowestCalories: totals.min() ?? 0,
                highestCalories: totals.max() ?? 0
            )
        }
        .sorted { $0.weekStart > $1.weekStart }
    }

    private static func label(
        forWeekStarting start: Date,
        endingOn end: Date,
        currentWeekStart: Date,
        previousWeekStart: Date?
    ) -> WeekHeaderLabel {
        if start == currentWeekStart { return .currentWeek }
        if let previousWeekStart, start == previousWeekStart { return .previousWeek }
        return .dateRange(start: start, end: end)
    }

    /// First instant of the week containing `date`.
    ///
    /// `dateInterval(of:for:)` is optional in the API but never nil for the
    /// Gregorian calendar this app uses; the `startOfDay` fallback exists purely
    /// to avoid a force-unwrap (Principle I).
    private static func weekStart(for date: Date, in calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
    }
}
