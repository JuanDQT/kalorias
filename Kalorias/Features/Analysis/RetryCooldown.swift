//
//  RetryCooldown.swift
//  Kalorias
//
//  How long the user must wait before retrying after a rate limit, and the
//  arithmetic behind the countdown on the button.
//
//  NO TIMER, NO CLOCK OF ITS OWN. Every question this type answers takes the
//  current date as an argument, which is what makes the whole countdown
//  testable without sleeping: the store owns the `Task` that ticks, and the
//  rules — remaining seconds, expiry, clamping, both header formats — are pure
//  functions asserted against injected dates (Principle II).
//
//  `Retry-After` COMES IN TWO FORMS. HTTP defines it as *either* a number of
//  seconds *or* an HTTP-date, and servers behind proxies send both. Parsing only
//  the integer form yields nothing exactly when a proxy is involved — that is,
//  in production.
//

import Foundation

nonisolated struct RetryCooldown: Equatable, Sendable {

    /// Bounds on any wait. A `0` or a negative would re-enable retry instantly
    /// and make the state meaningless; an absurd value would pin the button off
    /// for hours over what is usually a one-minute limit.
    static let permittedSeconds: ClosedRange<TimeInterval> = 1...3600

    /// Used when the server says nothing usable (FR-020a).
    static let defaultSeconds: TimeInterval = 60

    /// When retrying becomes possible again.
    let expiry: Date

    init(seconds: TimeInterval, now: Date) {
        expiry = now.addingTimeInterval(Self.clamped(seconds))
    }

    /// Whole seconds left, rounded **up** and floored at 0.
    ///
    /// Up rather than down so "1" stays on screen until the wait is genuinely
    /// over: rounding down would show "0" for a whole second while the button
    /// was still disabled, which reads as broken.
    func secondsRemaining(at date: Date) -> Int {
        let remaining = expiry.timeIntervalSince(date)
        guard remaining > 0 else { return 0 }
        return Int(remaining.rounded(.up))
    }

    func hasExpired(at date: Date) -> Bool {
        secondsRemaining(at: date) == 0
    }

    // MARK: Parsing the header

    /// Read a `Retry-After` header into a number of seconds.
    ///
    /// Falls back to `defaultSeconds` when the header is absent, empty,
    /// unparseable, or names a moment that has already passed — in every one of
    /// those cases the server has told us nothing we can act on, and guessing a
    /// minute is better than either retrying instantly into the same limit or
    /// disabling the button forever.
    static func parseRetryAfter(_ header: String?, now: Date) -> TimeInterval {
        guard let header else { return defaultSeconds }

        let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultSeconds }

        // Delay-seconds. A negative or zero is nonsense rather than unreadable,
        // so it clamps to the floor instead of falling back.
        if let seconds = TimeInterval(trimmed) {
            return clamped(seconds)
        }

        // HTTP-date.
        if let date = httpDateFormatter.date(from: trimmed) {
            let interval = date.timeIntervalSince(now)
            // A date already in the past tells us nothing about how long to
            // wait — most often a clock skew — so it takes the default.
            return interval > 0 ? clamped(interval) : defaultSeconds
        }

        return defaultSeconds
    }

    static func clamped(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite else { return defaultSeconds }
        return min(max(seconds, permittedSeconds.lowerBound), permittedSeconds.upperBound)
    }

    /// RFC 1123, the form `Retry-After` and `Date` use. Fixed locale and time
    /// zone: with the user's own, a device set to a non-Gregorian calendar
    /// silently fails to parse a perfectly good header.
    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
}
