//
//  DateTokenTests.swift
//  KaloriasTests
//
//  `today-16y` and friends. Nothing here reads the system clock: every
//  resolution is against an injected `now` and a fixed calendar, so the
//  assertions are exact rather than "about right" (Principle II).
//

import XCTest
@testable import Kalorias

nonisolated final class DateTokenTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func token(_ raw: String) throws -> DateToken {
        try XCTUnwrap(DateToken.parse(raw))
    }

    // MARK: Parsing

    func testAbsoluteDay() throws {
        XCTAssertEqual(try token("1993-04-18").form, .absolute(year: 1993, month: 4, day: 18))
    }

    func testRelativeTokens() throws {
        XCTAssertEqual(try token("today").form, .relative(offset: 0, unit: .day))
        XCTAssertEqual(try token("today-16y").form, .relative(offset: -16, unit: .year))
        XCTAssertEqual(try token("today+30d").form, .relative(offset: 30, unit: .day))
        XCTAssertEqual(try token("today-3m").form, .relative(offset: -3, unit: .month))
    }

    /// Deliberately narrow. Every extra spelling accepted here is one more thing
    /// the server and the app have to agree on forever.
    func testAnythingElseIsRefused() {
        for raw in ["", "tomorrow", "today-", "today-16", "today16y", "today-16w",
                    "1993-4-18", "93-04-18", "today-xy", "2026-13-01"] {
            XCTAssertNil(DateToken.parse(raw), "\(raw) should not parse")
        }
    }

    // MARK: Resolution

    func testRelativeYearsResolveAgainstTheGivenDay() throws {
        let now = date(2026, 9, 7)
        XCTAssertEqual(try token("today-16y").resolve(now: now, calendar: calendar), date(2010, 9, 7))
        XCTAssertEqual(try token("today").resolve(now: now, calendar: calendar), date(2026, 9, 7))
    }

    /// A birthday bound is a moving target: the same token means a different day
    /// tomorrow. That is the whole reason it is not written as a fixed date in
    /// the bundled copy.
    func testTheSameTokenResolvesDifferentlyOnDifferentDays() throws {
        let token = try token("today-16y")
        XCTAssertEqual(token.resolve(now: date(2026, 9, 7), calendar: calendar), date(2010, 9, 7))
        XCTAssertEqual(token.resolve(now: date(2027, 9, 7), calendar: calendar), date(2011, 9, 7))
    }

    func testResolutionUsesTheStartOfTheDay() throws {
        let noon = calendar.date(byAdding: .hour, value: 12, to: date(2026, 9, 7))!
        XCTAssertEqual(try token("today").resolve(now: noon, calendar: calendar), date(2026, 9, 7))
    }

    func testAnImpossibleAbsoluteDayResolvesToNothing() throws {
        var strict = calendar
        strict.timeZone = TimeZone(identifier: "UTC")!
        // 31 February parses (the digits are in range) but is not a day.
        let token = try XCTUnwrap(DateToken.parse("2026-02-31"))
        let resolved = token.resolve(now: date(2026, 9, 7), calendar: strict)
        XCTAssertNotEqual(resolved, date(2026, 2, 28), "must not silently become another day")
    }
}
