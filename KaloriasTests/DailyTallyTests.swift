//
//  DailyTallyTests.swift
//  KaloriasTests
//
//  Fixtures conform to `WeekGroupable` directly, so no `ModelContainer` is needed.
//  Every calendar and window end is injected — nothing reads `.current` or
//  `Date()` (constitution Principle II).
//

import XCTest
@testable import Kalorias

nonisolated final class DailyTallyTests: XCTestCase {

    private struct Fixture: WeekGroupable {
        let capturedAt: Date
        let totalCalories: Int
    }

    private let madrid = TimeZone(identifier: "Europe/Madrid") ?? .gmt

    private func calendar(_ timeZone: TimeZone? = nil) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "es_ES")
        calendar.timeZone = timeZone ?? madrid
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 12, _ minute: Int = 0,
        in timeZone: TimeZone? = nil
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone ?? madrid
        guard let date = calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        ) else {
            XCTFail("Could not build test date \(year)-\(month)-\(day)")
            return Date(timeIntervalSince1970: 0)
        }
        return date
    }

    /// Wednesday 22 July 2026 — the window is 16–22 July.
    private var windowEnd: Date { date(2026, 7, 22, 15) }

    private func tallies(_ items: [Fixture], timeZone: TimeZone? = nil) -> [DailyTally] {
        ProgressStatistics.dailyTallies(
            from: items,
            calendar: calendar(timeZone),
            endingOn: windowEnd,
            dayCount: 7
        )
    }

    // MARK: Window shape

    func testEmptyInputStillProducesSevenUnloggedDays() {
        let result = tallies([])
        XCTAssertEqual(result.count, 7)
        XCTAssertTrue(result.allSatisfy { !$0.hasLog })
        XCTAssertTrue(result.allSatisfy { $0.mealCount == 0 })
    }

    func testTalliesRunOldestToNewestEndingOnTheWindowDay() {
        let result = tallies([])
        let calendar = calendar()

        XCTAssertEqual(calendar.component(.day, from: result[0].day), 16)
        XCTAssertEqual(calendar.component(.day, from: result[6].day), 22)
        for index in 1..<result.count {
            XCTAssertTrue(result[index].day > result[index - 1].day)
        }
    }

    func testOnlyDaysWithMealsAreMarkedAsLogged() {
        let result = tallies([
            Fixture(capturedAt: date(2026, 7, 22), totalCalories: 500),
            Fixture(capturedAt: date(2026, 7, 20), totalCalories: 700),
            Fixture(capturedAt: date(2026, 7, 17), totalCalories: 300)
        ])

        XCTAssertEqual(result.filter(\.hasLog).count, 3)
        XCTAssertEqual(result.filter { !$0.hasLog }.count, 4)
    }

    // MARK: Aggregation

    func testTwoMealsOnTheSameDayCollapseIntoOneTally() {
        let result = tallies([
            Fixture(capturedAt: date(2026, 7, 21, 9), totalCalories: 400),
            Fixture(capturedAt: date(2026, 7, 21, 20), totalCalories: 650)
        ])

        let day21 = result.first { calendar().component(.day, from: $0.day) == 21 }
        XCTAssertEqual(day21?.mealCount, 2)
        XCTAssertEqual(day21?.totalCalories, 1_050)
    }

    /// The test that catches deriving `hasLog` from `totalCalories`. A logged meal
    /// that happens to total 0 kcal is still a log; treating it as "no data" would
    /// silently erase a real entry.
    func testAZeroCalorieMealStillCountsAsLogged() {
        let result = tallies([Fixture(capturedAt: date(2026, 7, 21), totalCalories: 0)])

        let day21 = result.first { calendar().component(.day, from: $0.day) == 21 }
        XCTAssertEqual(day21?.mealCount, 1)
        XCTAssertEqual(day21?.totalCalories, 0)
        XCTAssertEqual(day21?.hasLog, true, "a 0 kcal meal is still a log")
    }

    // MARK: Window boundaries

    func testMealOutsideTheWindowIsIgnored() {
        // 14 July is 8 days before the 22nd — outside a 7-day window.
        let result = tallies([Fixture(capturedAt: date(2026, 7, 14), totalCalories: 900)])
        XCTAssertTrue(result.allSatisfy { !$0.hasLog })
    }

    func testBoundaryDaysAreInclusive() {
        let result = tallies([
            Fixture(capturedAt: date(2026, 7, 16, 23, 59), totalCalories: 200),  // first day, late
            Fixture(capturedAt: date(2026, 7, 22, 0, 1), totalCalories: 300)     // last day, early
        ])

        XCTAssertEqual(result[0].totalCalories, 200)
        XCTAssertEqual(result[0].hasLog, true)
        XCTAssertEqual(result[6].totalCalories, 300)
        XCTAssertEqual(result[6].hasLog, true)
    }

    func testDaysAreBucketedInTheSuppliedTimeZone() {
        // 22 July 23:30 in Madrid is already 23 July in Tokyo, so the same instant
        // falls on different days — and in a Tokyo window it lands outside.
        let instant = date(2026, 7, 22, 23, 30)
        let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? .gmt

        let inMadrid = tallies([Fixture(capturedAt: instant, totalCalories: 400)])
        XCTAssertEqual(inMadrid[6].totalCalories, 400, "last day of the Madrid window")

        let inTokyo = tallies([Fixture(capturedAt: instant, totalCalories: 400)], timeZone: tokyo)
        XCTAssertTrue(
            inTokyo.allSatisfy { !$0.hasLog },
            "in Tokyo that instant is the day after the window's end"
        )
    }

    func testZeroDayCountProducesNoTallies() {
        let result = ProgressStatistics.dailyTallies(
            from: [Fixture](), calendar: calendar(), endingOn: windowEnd, dayCount: 0
        )
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: Average over logged days

    func testAverageDividesByLoggedDaysNotCalendarDays() {
        let result = tallies([
            Fixture(capturedAt: date(2026, 7, 22), totalCalories: 1_000),
            Fixture(capturedAt: date(2026, 7, 20), totalCalories: 500)
        ])

        // 1500 over 2 logged days = 750, NOT 1500/7 = 214.
        XCTAssertEqual(ProgressStatistics.averageOfLoggedDays(result), 750)
    }

    func testAverageIsNilWhenNothingIsLogged() {
        XCTAssertNil(ProgressStatistics.averageOfLoggedDays(tallies([])))
    }

    func testAverageIgnoresUnloggedDaysEvenWhenTheyOutnumberLoggedOnes() {
        let single = tallies([Fixture(capturedAt: date(2026, 7, 22), totalCalories: 640)])
        XCTAssertEqual(ProgressStatistics.averageOfLoggedDays(single), 640)
    }

    // MARK: Bounds for the color scale

    func testLoggedBoundsAreNilWhenNothingIsLogged() {
        XCTAssertNil(ProgressStatistics.loggedBounds(tallies([])))
    }

    func testLoggedBoundsOfASingleLoggedDayAreEqual() {
        let result = tallies([Fixture(capturedAt: date(2026, 7, 22), totalCalories: 820)])
        let bounds = ProgressStatistics.loggedBounds(result)

        XCTAssertEqual(bounds?.lowest, 820)
        XCTAssertEqual(bounds?.highest, 820)
    }

    func testLoggedBoundsSpanOnlyLoggedDays() {
        let result = tallies([
            Fixture(capturedAt: date(2026, 7, 22), totalCalories: 1_900),
            Fixture(capturedAt: date(2026, 7, 21), totalCalories: 340),
            Fixture(capturedAt: date(2026, 7, 18), totalCalories: 1_100)
        ])
        let bounds = ProgressStatistics.loggedBounds(result)

        // The four unlogged days sit at 0 but must not drag `lowest` down.
        XCTAssertEqual(bounds?.lowest, 340)
        XCTAssertEqual(bounds?.highest, 1_900)
    }
}
