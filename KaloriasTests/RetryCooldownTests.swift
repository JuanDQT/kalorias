//
//  RetryCooldownTests.swift
//  KaloriasTests
//
//  Contract A11 / rules R1–R6. **Nothing here sleeps or reads the clock** — the
//  whole point of making the cooldown a pure type is that its arithmetic is
//  asserted against injected dates (Principle II).
//

import XCTest
@testable import Kalorias

nonisolated final class RetryCooldownTests: XCTestCase {

    /// A fixed instant, so every expectation below is exact rather than
    /// approximate.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func httpDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.string(from: date)
    }

    // MARK: R1 — delay-seconds

    func testDelaySecondsAreReadAsSeconds() {
        XCTAssertEqual(RetryCooldown.parseRetryAfter("45", now: now), 45)
        XCTAssertEqual(RetryCooldown.parseRetryAfter("1", now: now), 1)
        XCTAssertEqual(RetryCooldown.parseRetryAfter("  20  ", now: now), 20)
    }

    // MARK: R2 — the HTTP-date form

    /// Servers behind a proxy send this form, so parsing only the integer one
    /// yields nothing exactly in production.
    func testHTTPDateIsReadAsSecondsUntilThatMoment() {
        let header = httpDate(now.addingTimeInterval(90))
        XCTAssertEqual(RetryCooldown.parseRetryAfter(header, now: now), 90, accuracy: 1)
    }

    /// R3: a moment that has already passed tells us nothing about how long to
    /// wait — usually clock skew — so it takes the default rather than
    /// re-enabling retry instantly.
    func testAnHTTPDateInThePastFallsBackToOneMinute() {
        let header = httpDate(now.addingTimeInterval(-300))
        XCTAssertEqual(RetryCooldown.parseRetryAfter(header, now: now), 60)
    }

    // MARK: R3 — absent, empty, unreadable

    func testAbsentHeaderIsOneMinute() {
        XCTAssertEqual(RetryCooldown.parseRetryAfter(nil, now: now), 60)
    }

    func testEmptyHeaderIsOneMinute() {
        XCTAssertEqual(RetryCooldown.parseRetryAfter("", now: now), 60)
        XCTAssertEqual(RetryCooldown.parseRetryAfter("   ", now: now), 60)
    }

    func testGarbageHeaderIsOneMinute() {
        XCTAssertEqual(RetryCooldown.parseRetryAfter("soon", now: now), 60)
        XCTAssertEqual(RetryCooldown.parseRetryAfter("Mon, 99 Xyz 20AA", now: now), 60)
    }

    // MARK: R4 — clamping

    /// A `0` or a negative would re-enable retry instantly and make the state
    /// meaningless; these are nonsense values rather than unreadable ones, so
    /// they clamp to the floor instead of taking the default.
    func testZeroAndNegativeWaitsClampToTheFloor() {
        XCTAssertEqual(RetryCooldown.parseRetryAfter("0", now: now), 1)
        XCTAssertEqual(RetryCooldown.parseRetryAfter("-5", now: now), 1)
        XCTAssertEqual(RetryCooldown.parseRetryAfter("-99999", now: now), 1)
    }

    /// An absurd value must not pin the retry button off for hours over what is
    /// normally a one-minute limit.
    func testAbsurdWaitsClampToAnHour() {
        XCTAssertEqual(RetryCooldown.parseRetryAfter("99999", now: now), 3600)
        XCTAssertEqual(RetryCooldown.parseRetryAfter("3601", now: now), 3600)
        XCTAssertEqual(RetryCooldown.parseRetryAfter("3600", now: now), 3600)
    }

    func testTheCooldownItselfClampsTheSameWay() {
        XCTAssertEqual(RetryCooldown(seconds: 0, now: now).secondsRemaining(at: now), 1)
        XCTAssertEqual(RetryCooldown(seconds: -10, now: now).secondsRemaining(at: now), 1)
        XCTAssertEqual(RetryCooldown(seconds: 99999, now: now).secondsRemaining(at: now), 3600)
        XCTAssertEqual(RetryCooldown(seconds: .infinity, now: now).secondsRemaining(at: now), 60)
        XCTAssertEqual(RetryCooldown(seconds: .nan, now: now).secondsRemaining(at: now), 60)
    }

    // MARK: R5 — the countdown

    func testSecondsRemainingCountsDownToZero() {
        let cooldown = RetryCooldown(seconds: 20, now: now)

        XCTAssertEqual(cooldown.secondsRemaining(at: now), 20)
        XCTAssertEqual(cooldown.secondsRemaining(at: now.addingTimeInterval(5)), 15)
        XCTAssertEqual(cooldown.secondsRemaining(at: now.addingTimeInterval(19)), 1)
        XCTAssertEqual(cooldown.secondsRemaining(at: now.addingTimeInterval(20)), 0)
    }

    /// Rounding **up** so "1" stays on screen until the wait is genuinely over.
    /// Rounding down would show "0" for a whole second while the button was
    /// still disabled, which reads as broken.
    func testAPartialSecondRoundsUp() {
        let cooldown = RetryCooldown(seconds: 20, now: now)

        XCTAssertEqual(cooldown.secondsRemaining(at: now.addingTimeInterval(19.1)), 1)
        XCTAssertEqual(cooldown.secondsRemaining(at: now.addingTimeInterval(19.9)), 1)
        XCTAssertEqual(cooldown.secondsRemaining(at: now.addingTimeInterval(0.5)), 20)
    }

    func testSecondsRemainingNeverGoesNegative() {
        let cooldown = RetryCooldown(seconds: 20, now: now)

        XCTAssertEqual(cooldown.secondsRemaining(at: now.addingTimeInterval(21)), 0)
        XCTAssertEqual(cooldown.secondsRemaining(at: now.addingTimeInterval(100_000)), 0)
        XCTAssertEqual(cooldown.secondsRemaining(at: now.addingTimeInterval(-50)), 20 + 50)
    }

    func testHasExpiredTracksTheCountdown() {
        let cooldown = RetryCooldown(seconds: 20, now: now)

        XCTAssertFalse(cooldown.hasExpired(at: now))
        XCTAssertFalse(cooldown.hasExpired(at: now.addingTimeInterval(19.9)))
        XCTAssertTrue(cooldown.hasExpired(at: now.addingTimeInterval(20)))
        XCTAssertTrue(cooldown.hasExpired(at: now.addingTimeInterval(60)))
    }

    // MARK: The header and the cooldown together

    /// The path a `429` actually travels: header → seconds → countdown.
    func testAServerWaitBecomesTheCountdownTheUserSees() {
        let seconds = RetryCooldown.parseRetryAfter("20", now: now)
        let cooldown = RetryCooldown(seconds: seconds, now: now)

        XCTAssertEqual(cooldown.secondsRemaining(at: now), 20)
        XCTAssertEqual(cooldown.secondsRemaining(at: now.addingTimeInterval(20)), 0)
        XCTAssertTrue(cooldown.hasExpired(at: now.addingTimeInterval(20)))
    }
}
