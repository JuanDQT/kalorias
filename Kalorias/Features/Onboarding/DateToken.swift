//
//  DateToken.swift
//  Kalorias
//
//  A date bound in the questionnaire: either an ISO-8601 day (`1993-04-18`) or
//  a token relative to today (`today`, `today-16y`, `today+30d`).
//
//  THE RELATIVE FORM EXISTS BECAUSE THE QUESTIONNAIRE IS ALSO SHIPPED IN THE
//  BUNDLE. A fixed `maxDate` written today turns a 16-year-old into a
//  17-year-old next year, and the bundled copy is exactly the one that goes
//  stale — it is the fallback used on a first launch with no network, which is
//  the moment nobody is watching.
//
//  RESOLVED ON THE DEVICE, IN ITS CALENDAR AND TIME ZONE. `today` means the
//  user's today, not the server's: a questionnaire cached last night in Madrid
//  and opened this morning must not still think it is yesterday.
//
//  `today-16y` on `birth_date` is a product decision rather than a detail: a
//  calorie-deficit plan for a minor is not something this app should generate.
//

import Foundation

nonisolated struct DateToken: Decodable, Equatable, Sendable {

    nonisolated enum Unit: String, Sendable {
        case day = "d", month = "m", year = "y"

        var calendarComponent: Calendar.Component {
            switch self {
            case .day: .day
            case .month: .month
            case .year: .year
            }
        }
    }

    nonisolated enum Form: Equatable, Sendable {
        /// Year, month, day. Held as components rather than a `Date` so the
        /// instant is only produced against a calendar, in `resolve`.
        case absolute(year: Int, month: Int, day: Int)
        case relative(offset: Int, unit: Unit)
    }

    let raw: String
    let form: Form

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = Self.parse(raw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unrecognised date token: \(raw)")
            )
        }
        self = parsed
    }

    private init(raw: String, form: Form) {
        self.raw = raw
        self.form = form
    }

    /// `nil` for anything that is neither an ISO day nor a `today±n` token.
    ///
    /// Deliberately narrow: no times, no weeks, no month names. Every accepted
    /// spelling is one more thing the server and the app must agree on forever.
    static func parse(_ raw: String) -> DateToken? {
        if let iso = parseISO(raw) { return DateToken(raw: raw, form: iso) }
        if let relative = parseRelative(raw) { return DateToken(raw: raw, form: relative) }
        return nil
    }

    private static func parseISO(_ raw: String) -> Form? {
        let parts = raw.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        return .absolute(year: year, month: month, day: day)
    }

    private static func parseRelative(_ raw: String) -> Form? {
        guard raw.hasPrefix("today") else { return nil }
        let suffix = raw.dropFirst("today".count)
        if suffix.isEmpty { return .relative(offset: 0, unit: .day) }

        guard let sign = suffix.first, sign == "+" || sign == "-" else { return nil }
        guard let unit = suffix.last.flatMap({ Unit(rawValue: String($0)) }) else { return nil }

        let digits = suffix.dropFirst().dropLast()
        guard digits.isEmpty == false, let magnitude = Int(digits) else { return nil }

        return .relative(offset: sign == "-" ? -magnitude : magnitude, unit: unit)
    }

    /// The instant this token names, at the start of that day.
    ///
    /// `nil` only for an absolute token naming a day that does not exist
    /// (31 February), which decoding cannot catch without a calendar.
    func resolve(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch form {
        case let .absolute(year, month, day):
            return calendar.date(from: DateComponents(year: year, month: month, day: day))
        case let .relative(offset, unit):
            let today = calendar.startOfDay(for: now)
            return calendar.date(byAdding: unit.calendarComponent, value: offset, to: today)
        }
    }
}
