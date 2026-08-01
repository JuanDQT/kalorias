//
//  ProgressStatistics.swift
//  Kalorias
//
//  Every figure the Progress tab shows, computed here rather than in a view body
//  (constitution Principle I/II — this feature is almost entirely arithmetic, so
//  all of it must be unit-testable).
//
//  `Calendar` and "now" are parameters, never `.current` / `Date()` reads, so the
//  logic is deterministic under test (Principle II); the view boundary supplies
//  the real ones. Generic over feature 004's `WeekGroupable`, so tests run against
//  plain fixtures with no `ModelContainer`.
//
//  This file imports no SwiftUI: it yields plain values and leaves formatting and
//  color to the view layer.
//

import Foundation

/// One calendar day inside a window.
///
/// `hasLog` is deliberately derived from `mealCount`, NOT from `totalCalories`:
/// "the user logged nothing" and "the user logged something totalling 0 kcal" are
/// different facts, and conflating them is what makes an unlogged day render as a
/// misleading zero.
nonisolated struct DailyTally: Identifiable, Equatable {
    let day: Date
    let totalCalories: Int
    let mealCount: Int

    var id: Date { day }
    var hasLog: Bool { mealCount > 0 }
}

/// Which way a figure moved between two periods. An enum rather than a signed
/// number on purpose: it forces the view to render a glyph and words instead of
/// leaning on red/green, which would make the information color-only.
nonisolated enum ChangeDirection {
    case up
    case down
    case unchanged
}

/// A change between two periods. `percent` is a magnitude — the sign lives in
/// `direction` — so it is never negative.
nonisolated struct PeriodChange: Equatable {
    let direction: ChangeDirection
    let percent: Int
}

/// Everything the weekly summary card renders.
nonisolated struct WeekSummary: Equatable {
    let weekStart: Date
    /// Days elapsed in the current week including today, `1...7`. Drives the
    /// like-for-like comparison against the previous week.
    let elapsedDays: Int
    let totalCalories: Int
    let loggedDayCount: Int
    let mealCount: Int
    /// `nil` when no day this week has a log — never `0`, which would assert the
    /// user averaged zero calories when the truth is "unknown".
    let averagePerLoggedDay: Int?
    let highestDay: DailyTally?
    /// Against the SAME ELAPSED PORTION of the previous week (see `weekSummary`).
    let totalChange: PeriodChange?
    let averageChange: PeriodChange?

    var hasData: Bool { mealCount > 0 }
}

nonisolated enum ProgressStatistics {

    // MARK: Per-day tallies

    /// One tally per day for `dayCount` days ending on the day containing
    /// `endingOn`, oldest first. Unlogged days still get a tally (with
    /// `hasLog == false`) so a chart can render them as labelled empty slots.
    static func dailyTallies<Item: WeekGroupable>(
        from items: [Item],
        calendar: Calendar,
        endingOn: Date,
        dayCount: Int
    ) -> [DailyTally] {
        guard dayCount > 0 else { return [] }

        let lastDay = calendar.startOfDay(for: endingOn)

        // Built with calendar arithmetic (not fixed seconds) so a DST shift
        // inside the window does not move a day boundary.
        let days: [Date] = stride(from: dayCount - 1, through: 0, by: -1).compactMap {
            calendar.date(byAdding: .day, value: -$0, to: lastDay)
        }

        let wanted = Set(days)
        var buckets: [Date: (total: Int, count: Int)] = [:]
        for item in items {
            let day = calendar.startOfDay(for: item.capturedAt)
            guard wanted.contains(day) else { continue }
            let current = buckets[day] ?? (total: 0, count: 0)
            buckets[day] = (current.total + item.totalCalories, current.count + 1)
        }

        return days.map { day in
            let bucket = buckets[day] ?? (total: 0, count: 0)
            return DailyTally(day: day, totalCalories: bucket.total, mealCount: bucket.count)
        }
    }

    /// Mean over the days that have a log. `nil` when none do — never `0`, which
    /// would assert "you averaged zero calories" when the truth is "unknown".
    static func averageOfLoggedDays(_ tallies: [DailyTally]) -> Int? {
        let logged = tallies.filter(\.hasLog)
        guard !logged.isEmpty else { return nil }
        let total = logged.reduce(0) { $0 + $1.totalCalories }
        return Int((Double(total) / Double(logged.count)).rounded())
    }

    /// Lowest and highest totals among the logged days, for the color scale.
    /// `nil` when no day is logged.
    static func loggedBounds(_ tallies: [DailyTally]) -> (lowest: Int, highest: Int)? {
        let totals = tallies.filter(\.hasLog).map(\.totalCalories)
        guard let lowest = totals.min(), let highest = totals.max() else { return nil }
        return (lowest, highest)
    }

    /// The logged day with the greatest total. Ties resolve to the MOST RECENT
    /// day, so repeated calls on the same data always agree.
    static func highestLoggedDay(_ tallies: [DailyTally]) -> DailyTally? {
        tallies.filter(\.hasLog).max { lhs, rhs in
            if lhs.totalCalories == rhs.totalCalories { return lhs.day < rhs.day }
            return lhs.totalCalories < rhs.totalCalories
        }
    }

    // MARK: Change between periods

    /// Relative change from `baseline` to `current`.
    ///
    /// Returns `nil` when there is nothing to compare against: `(current - 0) / 0`
    /// is undefined, and rendering it would put `+∞` or `nan%` on screen. A change
    /// too small to show at integer precision is reported as `.unchanged` rather
    /// than as "↑0%", which reads as a contradiction.
    static func change(current: Int, baseline: Int) -> PeriodChange? {
        guard baseline > 0 else { return nil }

        let delta = Double(current - baseline) / Double(baseline) * 100
        let percent = Int(abs(delta).rounded())
        guard percent > 0 else { return PeriodChange(direction: .unchanged, percent: 0) }

        return PeriodChange(direction: current > baseline ? .up : .down, percent: percent)
    }

    // MARK: Weekly summary

    /// Figures for the week containing `now`, with comparisons against the
    /// previous week.
    ///
    /// The total's baseline covers the **same elapsed portion** of the previous
    /// week. Comparing a Wednesday-so-far total against a full 7-day week would
    /// show a ~55% "decline" every week regardless of what the user ate — wrong in
    /// exactly the direction users care about.
    static func weekSummary<Item: WeekGroupable>(
        from items: [Item],
        calendar: Calendar,
        now: Date
    ) -> WeekSummary {
        // `dateInterval(of:for:)` is optional in the API but never nil for the
        // Gregorian calendar; the fallback avoids a force-unwrap (Principle I).
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start
            ?? calendar.startOfDay(for: now)
        let today = calendar.startOfDay(for: now)

        let dayOffset = calendar.dateComponents([.day], from: weekStart, to: today).day ?? 0
        let elapsedDays = min(7, max(1, dayOffset + 1))

        // A window of `elapsedDays` ending today is exactly weekStart...today.
        let current = dailyTallies(
            from: items, calendar: calendar, endingOn: today, dayCount: elapsedDays
        )
        let total = current.reduce(0) { $0 + $1.totalCalories }
        let mealCount = current.reduce(0) { $0 + $1.mealCount }
        let average = averageOfLoggedDays(current)

        // Calendar arithmetic, not fixed seconds: a DST shift must not move the
        // window edge off midnight.
        let previousStart = calendar.date(byAdding: .day, value: -7, to: weekStart)

        var totalChange: PeriodChange?
        var averageChange: PeriodChange?

        // With nothing logged this week there is no meaningful "current" value to
        // compare, and the card shows its "nothing logged this week" state instead.
        if mealCount > 0, let previousStart {
            if let alignedEnd = calendar.date(
                byAdding: .day, value: elapsedDays - 1, to: previousStart
            ) {
                let aligned = dailyTallies(
                    from: items, calendar: calendar, endingOn: alignedEnd, dayCount: elapsedDays
                )
                totalChange = change(
                    current: total,
                    baseline: aligned.reduce(0) { $0 + $1.totalCalories }
                )
            }

            // The per-logged-day average is an intensity, not a volume, so it is
            // comparable against the previous week in full — no alignment needed.
            if let previousEnd = calendar.date(byAdding: .day, value: 6, to: previousStart),
               let currentAverage = average {
                let previousWeek = dailyTallies(
                    from: items, calendar: calendar, endingOn: previousEnd, dayCount: 7
                )
                if let previousAverage = averageOfLoggedDays(previousWeek) {
                    averageChange = change(current: currentAverage, baseline: previousAverage)
                }
            }
        }

        return WeekSummary(
            weekStart: weekStart,
            elapsedDays: elapsedDays,
            totalCalories: total,
            loggedDayCount: current.filter(\.hasLog).count,
            mealCount: mealCount,
            averagePerLoggedDay: average,
            highestDay: highestLoggedDay(current),
            totalChange: totalChange,
            averageChange: averageChange
        )
    }
}
