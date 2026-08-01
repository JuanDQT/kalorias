//
//  MealWeekGroupingTests.swift
//  KaloriasTests
//
//  Fixtures conform to `WeekGroupable` directly, so these tests need no
//  `ModelContainer`. Every calendar and "now" is injected — nothing reads
//  `.current` or `Date()` (constitution Principle II).
//

import XCTest
@testable import Kalorias

nonisolated final class MealWeekGroupingTests: XCTestCase {

    private struct Fixture: WeekGroupable {
        let capturedAt: Date
        let totalCalories: Int
    }

    private let madrid = TimeZone(identifier: "Europe/Madrid") ?? .gmt

    /// Monday-first (Spain, `firstWeekday == 2`).
    private func mondayFirstCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "es_ES")
        calendar.timeZone = madrid
        calendar.firstWeekday = 2
        return calendar
    }

    /// Sunday-first (United States, `firstWeekday == 1`).
    private func sundayFirstCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = madrid
        calendar.firstWeekday = 1
        return calendar
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 12, _ minute: Int = 0
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = madrid
        let components = DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        )
        guard let date = calendar.date(from: components) else {
            XCTFail("Could not build test date \(year)-\(month)-\(day)")
            return Date(timeIntervalSince1970: 0)
        }
        return date
    }

    /// Wednesday 22 July 2026 — mid-week, so "this week" has days either side.
    private var now: Date { date(2026, 7, 22) }

    // MARK: Empty & partition invariants

    func testEmptyInputProducesNoGroups() {
        let groups = MealWeekGrouping.groups(
            from: [Fixture](), calendar: mondayFirstCalendar(), now: now
        )
        XCTAssertTrue(groups.isEmpty)
    }

    func testEveryItemLandsInExactlyOneGroup() {
        let items = [
            Fixture(capturedAt: date(2026, 7, 22), totalCalories: 100),
            Fixture(capturedAt: date(2026, 7, 20), totalCalories: 200),
            Fixture(capturedAt: date(2026, 7, 15), totalCalories: 300),
            Fixture(capturedAt: date(2026, 6, 30), totalCalories: 400),
            Fixture(capturedAt: date(2026, 6, 29), totalCalories: 500)
        ]
        let groups = MealWeekGrouping.groups(
            from: items, calendar: mondayFirstCalendar(), now: now
        )

        XCTAssertEqual(groups.reduce(0) { $0 + $1.items.count }, items.count)
        let totals = groups.flatMap { $0.items.map(\.totalCalories) }.sorted()
        XCTAssertEqual(totals, [100, 200, 300, 400, 500])
    }

    func testNoGroupIsEverEmpty() {
        // A gap week (nothing in 13–19 July) must simply not appear.
        let items = [
            Fixture(capturedAt: date(2026, 7, 22), totalCalories: 100),
            Fixture(capturedAt: date(2026, 7, 8), totalCalories: 200)
        ]
        let groups = MealWeekGrouping.groups(
            from: items, calendar: mondayFirstCalendar(), now: now
        )

        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups.allSatisfy { !$0.items.isEmpty })
    }

    // MARK: Ordering

    func testGroupsAreOrderedNewestWeekFirst() {
        let items = [
            Fixture(capturedAt: date(2026, 7, 8), totalCalories: 100),   // 3 weeks ago
            Fixture(capturedAt: date(2026, 7, 22), totalCalories: 200),  // this week
            Fixture(capturedAt: date(2026, 7, 15), totalCalories: 300)   // last week
        ]
        let groups = MealWeekGrouping.groups(
            from: items, calendar: mondayFirstCalendar(), now: now
        )

        XCTAssertEqual(groups.count, 3)
        XCTAssertTrue(groups[0].weekStart > groups[1].weekStart)
        XCTAssertTrue(groups[1].weekStart > groups[2].weekStart)
    }

    func testItemsWithinAGroupAreOrderedNewestFirst() {
        // Deliberately supplied oldest-first, to prove the grouping re-sorts.
        let items = [
            Fixture(capturedAt: date(2026, 7, 20, 8), totalCalories: 100),
            Fixture(capturedAt: date(2026, 7, 21, 9), totalCalories: 200),
            Fixture(capturedAt: date(2026, 7, 22, 10), totalCalories: 300)
        ]
        let groups = MealWeekGrouping.groups(
            from: items, calendar: mondayFirstCalendar(), now: now
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].items.map(\.totalCalories), [300, 200, 100])
    }

    // MARK: Region-driven week boundaries (FR-002)

    func testMondayFirstCalendarSplitsSundayFromTheFollowingMonday() {
        // Sunday 19 July 2026 22:00 and Monday 20 July 08:00.
        let items = [
            Fixture(capturedAt: date(2026, 7, 19, 22), totalCalories: 100),
            Fixture(capturedAt: date(2026, 7, 20, 8), totalCalories: 200)
        ]
        let groups = MealWeekGrouping.groups(
            from: items, calendar: mondayFirstCalendar(), now: now
        )

        XCTAssertEqual(groups.count, 2, "Monday-first: Sunday ends the week")
    }

    func testSundayFirstCalendarGroupsSundayWithTheFollowingMonday() {
        let items = [
            Fixture(capturedAt: date(2026, 7, 19, 22), totalCalories: 100),
            Fixture(capturedAt: date(2026, 7, 20, 8), totalCalories: 200)
        ]
        let groups = MealWeekGrouping.groups(
            from: items, calendar: sundayFirstCalendar(), now: now
        )

        XCTAssertEqual(groups.count, 1, "Sunday-first: Sunday starts the week")
    }

    func testSundayFirstCalendarSplitsSaturdayFromTheFollowingSunday() {
        // Saturday 18 July 2026 and Sunday 19 July: same week when Monday-first,
        // different weeks when Sunday-first.
        let items = [
            Fixture(capturedAt: date(2026, 7, 18, 22), totalCalories: 100),
            Fixture(capturedAt: date(2026, 7, 19, 8), totalCalories: 200)
        ]

        XCTAssertEqual(
            MealWeekGrouping.groups(from: items, calendar: sundayFirstCalendar(), now: now).count,
            2
        )
        XCTAssertEqual(
            MealWeekGrouping.groups(from: items, calendar: mondayFirstCalendar(), now: now).count,
            1
        )
    }

    // MARK: Labels (FR-003 … FR-006)

    func testWeekContainingNowIsLabelledCurrentWeek() {
        let groups = MealWeekGrouping.groups(
            from: [Fixture(capturedAt: date(2026, 7, 20), totalCalories: 100)],
            calendar: mondayFirstCalendar(),
            now: now
        )
        XCTAssertEqual(groups.first?.label, .currentWeek)
    }

    func testWeekSevenDaysBeforeNowIsLabelledPreviousWeek() {
        let groups = MealWeekGrouping.groups(
            from: [Fixture(capturedAt: date(2026, 7, 15), totalCalories: 100)],
            calendar: mondayFirstCalendar(),
            now: now
        )
        XCTAssertEqual(groups.first?.label, .previousWeek)
    }

    func testOlderWeeksAreLabelledWithTheirDateRange() {
        let groups = MealWeekGrouping.groups(
            from: [Fixture(capturedAt: date(2026, 7, 8), totalCalories: 100)],
            calendar: mondayFirstCalendar(),
            now: now
        )

        guard case .dateRange(let start, let end) = groups.first?.label else {
            return XCTFail("expected a date range, got \(String(describing: groups.first?.label))")
        }
        // Week of Monday 6 July – Sunday 12 July 2026.
        let calendar = mondayFirstCalendar()
        XCTAssertEqual(calendar.component(.day, from: start), 6)
        XCTAssertEqual(calendar.component(.day, from: end), 12)
    }

    /// `DateInterval.end` is exclusive; using it raw would report the week as
    /// ending on the *next* Monday (FR-005).
    func testWeekEndIsTheWeeksLastDayNotTheExclusiveIntervalEnd() {
        let groups = MealWeekGrouping.groups(
            from: [Fixture(capturedAt: date(2026, 7, 8), totalCalories: 100)],
            calendar: mondayFirstCalendar(),
            now: now
        )
        let calendar = mondayFirstCalendar()

        guard let group = groups.first else { return XCTFail("expected one group") }
        XCTAssertEqual(calendar.component(.day, from: group.weekStart), 6)
        XCTAssertEqual(calendar.component(.day, from: group.weekEnd), 12)
        XCTAssertEqual(
            calendar.dateComponents([.day], from: group.weekStart, to: group.weekEnd).day,
            6
        )
    }

    func testThreeWeeksProduceCurrentPreviousAndRangeLabelsInOrder() {
        let items = [
            Fixture(capturedAt: date(2026, 7, 22), totalCalories: 100),
            Fixture(capturedAt: date(2026, 7, 15), totalCalories: 200),
            Fixture(capturedAt: date(2026, 7, 8), totalCalories: 300)
        ]
        let groups = MealWeekGrouping.groups(
            from: items, calendar: mondayFirstCalendar(), now: now
        )

        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups[0].label, .currentWeek)
        XCTAssertEqual(groups[1].label, .previousWeek)
        if case .dateRange = groups[2].label {} else {
            XCTFail("expected a date range for the oldest week")
        }
    }

    /// A week straddling New Year stays one group, with endpoints in different
    /// years for the header to disambiguate.
    func testWeekStraddlingNewYearIsASingleGroup() {
        let items = [
            Fixture(capturedAt: date(2025, 12, 30), totalCalories: 100),
            Fixture(capturedAt: date(2026, 1, 2), totalCalories: 200)
        ]
        let calendar = mondayFirstCalendar()
        let groups = MealWeekGrouping.groups(from: items, calendar: calendar, now: now)

        XCTAssertEqual(groups.count, 1)
        guard let group = groups.first else { return XCTFail("expected one group") }
        XCTAssertEqual(calendar.component(.year, from: group.weekStart), 2025)
        XCTAssertEqual(calendar.component(.year, from: group.weekEnd), 2026)
    }

    // MARK: Calorie bounds (FR-011)

    func testGroupBoundsAreTheMinAndMaxOfItsItems() {
        let items = [
            Fixture(capturedAt: date(2026, 7, 20), totalCalories: 640),
            Fixture(capturedAt: date(2026, 7, 21), totalCalories: 120),
            Fixture(capturedAt: date(2026, 7, 22), totalCalories: 2000)
        ]
        let groups = MealWeekGrouping.groups(
            from: items, calendar: mondayFirstCalendar(), now: now
        )

        XCTAssertEqual(groups.first?.lowestCalories, 120)
        XCTAssertEqual(groups.first?.highestCalories, 2000)
    }

    func testSingleItemGroupHasEqualBounds() {
        let groups = MealWeekGrouping.groups(
            from: [Fixture(capturedAt: date(2026, 7, 22), totalCalories: 550)],
            calendar: mondayFirstCalendar(),
            now: now
        )

        XCTAssertEqual(groups.first?.lowestCalories, 550)
        XCTAssertEqual(groups.first?.highestCalories, 550)
    }

    func testBoundsAreScopedPerGroupNotAcrossTheWholeList() {
        let items = [
            Fixture(capturedAt: date(2026, 7, 22), totalCalories: 300),  // this week
            Fixture(capturedAt: date(2026, 7, 21), totalCalories: 400),  // this week
            Fixture(capturedAt: date(2026, 7, 15), totalCalories: 900),  // last week
            Fixture(capturedAt: date(2026, 7, 14), totalCalories: 1500)  // last week
        ]
        let groups = MealWeekGrouping.groups(
            from: items, calendar: mondayFirstCalendar(), now: now
        )

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].lowestCalories, 300)
        XCTAssertEqual(groups[0].highestCalories, 400)
        XCTAssertEqual(groups[1].lowestCalories, 900)
        XCTAssertEqual(groups[1].highestCalories, 1500)
    }
}
