//
//  WeekSummaryTests.swift
//  KaloriasTests
//
//  The elapsed-alignment rule is what this suite exists to protect: the current
//  week's total must be compared against the SAME NUMBER OF DAYS of the previous
//  week, or every week shows a false decline until Sunday.
//

import XCTest
@testable import Kalorias

nonisolated final class WeekSummaryTests: XCTestCase {

    private struct Fixture: WeekGroupable {
        let capturedAt: Date
        let totalCalories: Int
    }

    private let madrid = TimeZone(identifier: "Europe/Madrid") ?? .gmt

    private func calendar(firstWeekday: Int = 2, timeZone: TimeZone? = nil) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "es_ES")
        calendar.timeZone = timeZone ?? madrid
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = madrid
        guard let date = calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour)
        ) else {
            XCTFail("Could not build test date \(year)-\(month)-\(day)")
            return Date(timeIntervalSince1970: 0)
        }
        return date
    }

    /// Wednesday 22 July 2026. Monday-first week starts Mon 20 July.
    private var wednesday: Date { date(2026, 7, 22, 15) }

    private func summary(
        _ items: [Fixture],
        now: Date? = nil,
        firstWeekday: Int = 2
    ) -> WeekSummary {
        ProgressStatistics.weekSummary(
            from: items,
            calendar: calendar(firstWeekday: firstWeekday),
            now: now ?? wednesday
        )
    }

    // MARK: Week boundaries and elapsed days

    func testMondayFirstWeekStartsOnMondayWithThreeDaysElapsedOnWednesday() {
        let result = summary([])
        let calendar = calendar()

        XCTAssertEqual(calendar.component(.day, from: result.weekStart), 20)
        XCTAssertEqual(result.elapsedDays, 3)
    }

    func testSundayFirstWeekStartsOnSundayWithFourDaysElapsedOnWednesday() {
        let result = summary([], firstWeekday: 1)
        let calendar = calendar(firstWeekday: 1)

        XCTAssertEqual(calendar.component(.day, from: result.weekStart), 19)
        XCTAssertEqual(result.elapsedDays, 4)
    }

    func testFirstDayOfTheWeekHasOneElapsedDay() {
        // Monday 20 July.
        XCTAssertEqual(summary([], now: date(2026, 7, 20, 9)).elapsedDays, 1)
    }

    func testLastDayOfTheWeekHasSevenElapsedDays() {
        // Sunday 26 July, Monday-first week.
        XCTAssertEqual(summary([], now: date(2026, 7, 26, 22)).elapsedDays, 7)
    }

    // MARK: Figures

    func testTotalsAndCountsCoverOnlyTheCurrentWeek() {
        let result = summary([
            Fixture(capturedAt: date(2026, 7, 22), totalCalories: 600),   // this week
            Fixture(capturedAt: date(2026, 7, 20), totalCalories: 400),   // this week
            Fixture(capturedAt: date(2026, 7, 17), totalCalories: 999)    // last week — excluded
        ])

        XCTAssertEqual(result.totalCalories, 1_000)
        XCTAssertEqual(result.mealCount, 2)
        XCTAssertEqual(result.loggedDayCount, 2)
        XCTAssertTrue(result.hasData)
    }

    func testAverageDividesByLoggedDaysNotByElapsedDays() {
        let result = summary([
            Fixture(capturedAt: date(2026, 7, 22), totalCalories: 1_000),
            Fixture(capturedAt: date(2026, 7, 20), totalCalories: 500)
        ])

        // 1500 over 2 logged days = 750, not 1500/3 elapsed days = 500.
        XCTAssertEqual(result.averagePerLoggedDay, 750)
    }

    func testNothingLoggedThisWeekYieldsNilAverageAndNoData() {
        let result = summary([Fixture(capturedAt: date(2026, 7, 15), totalCalories: 800)])

        XCTAssertFalse(result.hasData)
        XCTAssertNil(result.averagePerLoggedDay, "must be nil, never 0")
        XCTAssertNil(result.highestDay)
        XCTAssertNil(result.totalChange)
        XCTAssertNil(result.averageChange)
    }

    func testEmptyInputYieldsAnEmptySummary() {
        let result = summary([])

        XCTAssertFalse(result.hasData)
        XCTAssertEqual(result.totalCalories, 0)
        XCTAssertEqual(result.loggedDayCount, 0)
        XCTAssertNil(result.averagePerLoggedDay)
        XCTAssertNil(result.highestDay)
    }

    // MARK: Highest day

    func testHighestDayIsTheGreatestLoggedTotal() {
        let result = summary([
            Fixture(capturedAt: date(2026, 7, 20), totalCalories: 400),
            Fixture(capturedAt: date(2026, 7, 21), totalCalories: 1_800),
            Fixture(capturedAt: date(2026, 7, 22), totalCalories: 900)
        ])

        XCTAssertEqual(result.highestDay?.totalCalories, 1_800)
        XCTAssertEqual(calendar().component(.day, from: result.highestDay?.day ?? .distantPast), 21)
    }

    /// Without a defined tie-break, two runs could disagree about which day is
    /// "highest" on identical data.
    func testHighestDayTieResolvesToTheMostRecentDayRepeatably() {
        let items = [
            Fixture(capturedAt: date(2026, 7, 20), totalCalories: 1_000),
            Fixture(capturedAt: date(2026, 7, 22), totalCalories: 1_000)
        ]

        for _ in 0..<5 {
            let result = summary(items)
            XCTAssertEqual(
                calendar().component(.day, from: result.highestDay?.day ?? .distantPast),
                22,
                "a tie must resolve to the most recent day, every time"
            )
        }
    }

    // MARK: The elapsed-alignment rule

    /// The previous week was only loaded on its days 5–7, which fall outside the
    /// aligned 3-day baseline — so there is nothing to compare against and the
    /// change must be suppressed rather than reported as a huge swing.
    func testBaselineOutsideTheElapsedPortionSuppressesTheChange() {
        let result = summary([
            Fixture(capturedAt: date(2026, 7, 22), totalCalories: 1_200),  // this week
            Fixture(capturedAt: date(2026, 7, 17), totalCalories: 2_000),  // prev Fri (day 5)
            Fixture(capturedAt: date(2026, 7, 18), totalCalories: 2_000)   // prev Sat (day 6)
        ])

        XCTAssertNil(
            result.totalChange,
            "the aligned baseline (prev Mon–Wed) is empty, so no comparison is possible"
        )
    }

    /// The load-bearing test: the baseline must be the previous week's first three
    /// days (1000), not its full-week total (1000 + 5000 = 6000, which would report
    /// an 80% collapse).
    func testTotalChangeUsesOnlyTheAlignedPortionOfThePreviousWeek() {
        let result = summary([
            // Current week, Mon–Wed: 1120
            Fixture(capturedAt: date(2026, 7, 20), totalCalories: 500),
            Fixture(capturedAt: date(2026, 7, 21), totalCalories: 320),
            Fixture(capturedAt: date(2026, 7, 22), totalCalories: 300),
            // Previous week, Mon–Wed: 1000  ← the baseline
            Fixture(capturedAt: date(2026, 7, 13), totalCalories: 400),
            Fixture(capturedAt: date(2026, 7, 14), totalCalories: 300),
            Fixture(capturedAt: date(2026, 7, 15), totalCalories: 300),
            // Previous week, Thu–Sun: 5000  ← must be EXCLUDED
            Fixture(capturedAt: date(2026, 7, 16), totalCalories: 2_500),
            Fixture(capturedAt: date(2026, 7, 19), totalCalories: 2_500)
        ])

        XCTAssertEqual(result.totalCalories, 1_120)
        XCTAssertEqual(result.totalChange?.direction, .up)
        XCTAssertEqual(
            result.totalChange?.percent, 12,
            "1120 vs the aligned 1000 is +12%; against the full 6000 it would be -81%"
        )
    }

    func testAverageChangeComparesAgainstThePreviousWeekInFull() {
        let result = summary([
            // This week: one logged day at 1000 → average 1000
            Fixture(capturedAt: date(2026, 7, 22), totalCalories: 1_000),
            // Previous week: two logged days at 800 and 800 → average 800
            Fixture(capturedAt: date(2026, 7, 14), totalCalories: 800),
            Fixture(capturedAt: date(2026, 7, 19), totalCalories: 800)
        ])

        XCTAssertEqual(result.averagePerLoggedDay, 1_000)
        XCTAssertEqual(result.averageChange?.direction, .up)
        XCTAssertEqual(result.averageChange?.percent, 25)
    }

    func testNoPreviousWeekDataSuppressesBothChanges() {
        let result = summary([Fixture(capturedAt: date(2026, 7, 22), totalCalories: 900)])

        XCTAssertTrue(result.hasData)
        XCTAssertNil(result.totalChange)
        XCTAssertNil(result.averageChange)
    }

    // MARK: DST and determinism

    /// Madrid falls back on 25 October 2026. Window edges must stay on midnight;
    /// fixed-second arithmetic would slide them to 23:00 and pull in an extra
    /// evening's meals.
    func testDaylightSavingWeekKeepsWindowEdgesOnMidnight() {
        let calendar = calendar()
        // Wednesday 28 October 2026; Monday-first week starts Mon 26 October.
        let result = summary([], now: date(2026, 10, 28, 12))

        XCTAssertEqual(calendar.component(.day, from: result.weekStart), 26)
        XCTAssertEqual(calendar.component(.hour, from: result.weekStart), 0)
        XCTAssertEqual(result.elapsedDays, 3)
    }

    func testDaylightSavingWeekDoesNotPullInThePreviousSundayEvening() {
        // Sunday 25 October 22:00 belongs to the PREVIOUS week (Mon 19 – Sun 25).
        let result = summary(
            [Fixture(capturedAt: date(2026, 10, 25, 22), totalCalories: 700)],
            now: date(2026, 10, 28, 12)
        )

        XCTAssertEqual(result.totalCalories, 0, "that meal is in the previous week")
        XCTAssertFalse(result.hasData)
    }

    func testSummaryIsDeterministic() {
        let items = [
            Fixture(capturedAt: date(2026, 7, 22), totalCalories: 900),
            Fixture(capturedAt: date(2026, 7, 14), totalCalories: 700)
        ]
        XCTAssertEqual(summary(items), summary(items))
    }
}
