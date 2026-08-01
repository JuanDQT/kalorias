//
//  MealDateFormattingTests.swift
//  KaloriasTests
//
//  Every test injects its own locale, calendar and time zone — nothing reads
//  `.current`, so these stay deterministic on any machine (constitution
//  Principle II).
//

import XCTest
@testable import Kalorias

nonisolated final class MealDateFormattingTests: XCTestCase {

    private let madrid = TimeZone(identifier: "Europe/Madrid") ?? .gmt

    private func calendar(_ locale: Locale, _ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        return calendar
    }

    private func formatter(
        _ identifier: String,
        timeZone: TimeZone? = nil
    ) -> MealDateFormatting {
        let locale = Locale(identifier: identifier)
        let zone = timeZone ?? madrid
        return MealDateFormatting(locale: locale, calendar: calendar(locale, zone), timeZone: zone)
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0,
        in timeZone: TimeZone? = nil
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone ?? madrid
        let components = DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        )
        guard let date = calendar.date(from: components) else {
            XCTFail("Could not build test date \(year)-\(month)-\(day)")
            return Date(timeIntervalSince1970: 0)
        }
        return date
    }

    /// 25 July 2025 was a Friday — the example in the feature request.
    private var friday: Date { date(2025, 7, 25, 16, 40) }

    // MARK: Row timestamp

    func testSpanishRowTimestampMatchesTheRequestedFormat() {
        XCTAssertEqual(formatter("es_ES").rowTimestamp(for: friday), "Vie. 25 Jul, 16:40")
    }

    func testEnglishRowTimestampUsesEnglishSymbols() {
        let text = formatter("en_GB").rowTimestamp(for: friday)
        XCTAssertEqual(text, "Fri. 25 Jul, 16:40")
    }

    /// A 12-hour region must render 12-hour time. This is the test that fails if
    /// the time is ever produced from a hardcoded "HH:mm" instead of the `j`
    /// skeleton (FR-010).
    func testTwelveHourLocaleRendersTwelveHourTime() {
        let text = formatter("en_US").rowTimestamp(for: friday)
        XCTAssertTrue(text.hasPrefix("Fri. 25 Jul, "), "unexpected prefix in \(text)")
        XCTAssertTrue(text.contains("4:40"), "expected 12-hour time in \(text)")
        XCTAssertFalse(text.contains("16:40"), "expected 12-hour time in \(text)")
    }

    /// The counterpart: a 24-hour region must not gain an AM/PM marker.
    func testTwentyFourHourLocaleRendersTwentyFourHourTime() {
        let text = formatter("en_GB").rowTimestamp(for: friday)
        XCTAssertTrue(text.contains("16:40"), "expected 24-hour time in \(text)")
        XCTAssertFalse(text.uppercased().contains("PM"), "unexpected AM/PM in \(text)")
    }

    func testWeekdayAndMonthAreCapitalizedInBothLanguages() {
        // Spanish CLDR symbols are lowercase ("vie", "jul"); English already
        // capitalizes. Both must come out capitalized, with a trailing period on
        // the weekday.
        XCTAssertTrue(formatter("es_ES").rowTimestamp(for: friday).hasPrefix("Vie. "))
        XCTAssertTrue(formatter("en_GB").rowTimestamp(for: friday).hasPrefix("Fri. "))
    }

    func testTimeZoneIsHonored() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        let madridText = formatter("en_GB").rowTimestamp(for: friday)
        let tokyoText = formatter("en_GB", timeZone: tokyo).rowTimestamp(for: friday)

        XCTAssertNotEqual(madridText, tokyoText)
        XCTAssertTrue(madridText.contains("16:40"))
        // Madrid is UTC+2 in July, Tokyo UTC+9 — the same instant is 23:40 there.
        XCTAssertTrue(tokyoText.contains("23:40"), "unexpected Tokyo rendering \(tokyoText)")
    }

    func testRowTimestampIsDeterministic() {
        let subject = formatter("es_ES")
        XCTAssertEqual(subject.rowTimestamp(for: friday), subject.rowTimestamp(for: friday))
    }

    // MARK: Week range

    func testWeekRangeInTheReferenceYearOmitsTheYear() {
        let text = formatter("es_ES").weekRange(
            start: date(2026, 2, 1),
            end: date(2026, 2, 7),
            referenceYear: 2026
        )
        XCTAssertEqual(text, "1 Febrero - 7 Febrero")
    }

    func testWeekRangeUsesFullCapitalizedMonthNames() {
        let text = formatter("en_GB").weekRange(
            start: date(2026, 2, 1),
            end: date(2026, 2, 7),
            referenceYear: 2026
        )
        XCTAssertEqual(text, "1 February - 7 February")
    }

    func testWeekRangeSpanningTwoMonthsNamesBothMonths() {
        let text = formatter("es_ES").weekRange(
            start: date(2026, 1, 29),
            end: date(2026, 2, 4),
            referenceYear: 2026
        )
        XCTAssertEqual(text, "29 Enero - 4 Febrero")
    }

    func testWeekRangeOutsideTheReferenceYearCarriesTheYear() {
        let text = formatter("es_ES").weekRange(
            start: date(2025, 2, 1),
            end: date(2025, 2, 7),
            referenceYear: 2026
        )
        XCTAssertEqual(text, "1 Febrero 2025 - 7 Febrero 2025")
    }

    /// A week straddling New Year: each endpoint is judged on its own year, so
    /// the December side is disambiguated while the January side (the reference
    /// year) stays clean (FR-006).
    func testWeekRangeStraddlingNewYearDisambiguatesPerEndpoint() {
        let text = formatter("es_ES").weekRange(
            start: date(2025, 12, 29),
            end: date(2026, 1, 4),
            referenceYear: 2026
        )
        XCTAssertEqual(text, "29 Diciembre 2025 - 4 Enero")
    }

    func testWeekRangeIsDeterministic() {
        let subject = formatter("es_ES")
        let start = date(2026, 2, 1)
        let end = date(2026, 2, 7)
        XCTAssertEqual(
            subject.weekRange(start: start, end: end, referenceYear: 2026),
            subject.weekRange(start: start, end: end, referenceYear: 2026)
        )
    }
}
