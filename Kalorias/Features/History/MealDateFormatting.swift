//
//  MealDateFormatting.swift
//  Kalorias
//
//  Builds the History screen's two date strings: a row timestamp
//  ("Vie. 25 Jul, 16:40", FR-010) and a week-range header ("1 Febrero -
//  7 Febrero", FR-005/FR-006).
//
//  Both are COMPOSED from the locale's own symbols and arranged by a localized
//  pattern in `Localizable.xcstrings`, because no stock formatter produces these
//  shapes: `es_ES` gives "sáb, 25 jul" (lowercase, no period) and "1 de febrero",
//  while `en_US` reverses to "February 1". Composing keeps the month/weekday
//  names and the 12/24-hour clock coming from the device while translators keep
//  control of word order (constitution Principle VI — no hardcoded format
//  literals).
//
//  Locale, calendar and time zone are injected rather than read from `.current`
//  so the logic is deterministic under test (Principle II). Formatters are built
//  once per instance and one instance serves a whole grouping pass, which keeps
//  the list at 60fps (Principle IV).
//

import Foundation

nonisolated struct MealDateFormatting {
    private let locale: Locale
    private let calendar: Calendar

    /// Symbol tables read once at init; `DateFormatter` lookups are expensive
    /// enough that doing this per row would show up while scrolling.
    private let shortWeekdaySymbols: [String]
    private let shortMonthSymbols: [String]
    private let standaloneMonthSymbols: [String]

    /// Time-only formatter. The `j` skeleton is what makes the device's
    /// 12/24-hour preference apply — a literal "HH:mm" would force 24-hour and
    /// break FR-010 on US devices.
    private let timeFormatter: DateFormatter

    init(locale: Locale, calendar: Calendar, timeZone: TimeZone) {
        self.locale = locale

        var resolvedCalendar = calendar
        resolvedCalendar.locale = locale
        resolvedCalendar.timeZone = timeZone
        self.calendar = resolvedCalendar

        let symbols = DateFormatter()
        symbols.locale = locale
        symbols.timeZone = timeZone
        symbols.calendar = resolvedCalendar
        self.shortWeekdaySymbols = symbols.shortWeekdaySymbols ?? []
        self.shortMonthSymbols = symbols.shortMonthSymbols ?? []
        self.standaloneMonthSymbols = symbols.standaloneMonthSymbols ?? []

        let time = DateFormatter()
        time.locale = locale
        time.timeZone = timeZone
        time.calendar = resolvedCalendar
        time.setLocalizedDateFormatFromTemplate("jmm")
        self.timeFormatter = time
    }

    // MARK: Row timestamp

    /// "Vie. 25 Jul, 16:40" — abbreviated weekday, day, abbreviated month, time.
    func rowTimestamp(for date: Date) -> String {
        let components = calendar.dateComponents([.weekday, .day, .month], from: date)

        let weekday = weekdaySymbol(components.weekday)
        let day = components.day ?? 1
        let month = capitalizingFirstLetter(monthSymbol(components.month, from: shortMonthSymbols))
        let time = timeFormatter.string(from: date)

        return String(
            format: pattern("history.date.rowFormat"),
            locale: locale,
            weekday, "\(day)", month, time
        )
    }

    // MARK: Week range header

    /// "1 Febrero - 7 Febrero". An endpoint falling outside `referenceYear`
    /// carries its year, which covers both an ordinary older week and a week
    /// straddling New Year (FR-006).
    func weekRange(start: Date, end: Date, referenceYear: Int) -> String {
        String(
            format: pattern("history.week.range"),
            locale: locale,
            endpoint(start, referenceYear: referenceYear),
            endpoint(end, referenceYear: referenceYear)
        )
    }

    private func endpoint(_ date: Date, referenceYear: Int) -> String {
        let components = calendar.dateComponents([.day, .month, .year], from: date)
        let day = components.day ?? 1
        let month = capitalizingFirstLetter(monthSymbol(components.month, from: standaloneMonthSymbols))
        let year = components.year ?? referenceYear

        if year == referenceYear {
            return String(format: pattern("history.week.dayMonth"), locale: locale, "\(day)", month)
        }
        return String(
            format: pattern("history.week.dayMonthYear"),
            locale: locale,
            "\(day)", month, "\(year)"
        )
    }

    // MARK: Symbols

    /// The abbreviated weekday with a trailing period, as the design asks for
    /// ("Vie."). Spanish CLDR abbreviations carry no period of their own, so one
    /// is appended unless the locale already supplies it.
    private func weekdaySymbol(_ weekday: Int?) -> String {
        // `.weekday` is 1-based from Sunday regardless of the calendar's
        // `firstWeekday`, matching `shortWeekdaySymbols`' own ordering.
        let index = (weekday ?? 1) - 1
        guard shortWeekdaySymbols.indices.contains(index) else { return "" }

        let symbol = capitalizingFirstLetter(shortWeekdaySymbols[index])
        return symbol.hasSuffix(".") ? symbol : symbol + "."
    }

    private func monthSymbol(_ month: Int?, from symbols: [String]) -> String {
        let index = (month ?? 1) - 1
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index]
    }

    /// Uppercases only the first character. Whole-string `.capitalized` would
    /// title-case every word, which is wrong for multi-word month names.
    private func capitalizingFirstLetter(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased(with: locale) + text.dropFirst()
    }

    /// The arrangement pattern for a composed date string.
    ///
    /// Note that `locale:` here formats interpolated values; the *language* of
    /// the returned pattern comes from the bundle's active localization. That is
    /// the behavior we want at runtime — the app's language and the strings it
    /// shows stay in step — and the two shipped patterns are identical in EN and
    /// ES, so the composed output is stable regardless of which is resolved.
    private func pattern(_ key: String.LocalizationValue) -> String {
        String(localized: key, locale: locale)
    }
}
