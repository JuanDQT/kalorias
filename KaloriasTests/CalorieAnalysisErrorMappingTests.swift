//
//  CalorieAnalysisErrorMappingTests.swift
//  KaloriasTests
//

import XCTest
@testable import Kalorias

nonisolated final class CalorieAnalysisErrorMappingTests: XCTestCase {

    func testNoConnectionMapping() {
        XCTAssertEqual(AnalysisError.from(URLError(.notConnectedToInternet)), .noConnection)
        XCTAssertEqual(AnalysisError.from(URLError(.networkConnectionLost)), .noConnection)
        XCTAssertEqual(AnalysisError.from(URLError(.dataNotAllowed)), .noConnection)
    }

    func testTimeoutMapping() {
        XCTAssertEqual(AnalysisError.from(URLError(.timedOut)), .timeout)
    }

    func testOtherURLErrorsMapToServiceError() {
        XCTAssertEqual(AnalysisError.from(URLError(.badServerResponse)), .serviceError)
    }

    func testDecodingErrorMapsToInvalidResponse() {
        let decodingError = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "x"))
        XCTAssertEqual(AnalysisError.from(decodingError), .invalidResponse)
    }

    func testExistingAnalysisErrorPassesThrough() {
        XCTAssertEqual(AnalysisError.from(AnalysisError.invalidResponse), .invalidResponse)
    }

    // MARK: The two cases feature 009 added

    /// Both come from an HTTP status rather than from a thrown `URLError`, so
    /// `from(_:)` sees them only as pass-throughs — but they must survive that
    /// trip intact, associated value and all.
    func testNewCasesPassThroughUnchanged() {
        XCTAssertEqual(AnalysisError.from(AnalysisError.photoRejected), .photoRejected)
        XCTAssertEqual(
            AnalysisError.from(AnalysisError.rateLimited(retryAfter: 20)),
            .rateLimited(retryAfter: 20)
        )
    }

    /// The wait is part of the case's identity: two rate limits with different
    /// countdowns are not the same state, and the store starts its cooldown from
    /// this number.
    func testRateLimitedEqualityIncludesTheWait() {
        XCTAssertNotEqual(
            AnalysisError.rateLimited(retryAfter: 20),
            AnalysisError.rateLimited(retryAfter: 60)
        )
        XCTAssertNotEqual(AnalysisError.photoRejected, AnalysisError.serviceError)
    }

    /// Rule E3 / FR-019: a rejected photo must be distinguishable from every
    /// retryable failure, because it is the one that offers Retake instead.
    func testEachCaseCarriesItsOwnMessageKey() {
        let keys = [
            AnalysisError.noConnection,
            .timeout,
            .serviceError,
            .invalidResponse,
            .photoRejected,
            .rateLimited(retryAfter: 20)
        ].map(\.messageKey)

        XCTAssertEqual(Set(keys).count, keys.count, "two states sharing a message would read as one")
        XCTAssertEqual(AnalysisError.photoRejected.messageKey, "analysis.error.photoRejected")
        XCTAssertEqual(AnalysisError.rateLimited(retryAfter: 20).messageKey, "analysis.error.rateLimited")
    }

    /// The countdown lives on the button, in `analysis.retryIn`, so the message
    /// itself must not vary with the wait — otherwise there are two moving
    /// values saying the same thing (contracts/ui-contracts.md).
    func testRateLimitedMessageDoesNotVaryWithTheWait() {
        XCTAssertEqual(
            AnalysisError.rateLimited(retryAfter: 5).messageKey,
            AnalysisError.rateLimited(retryAfter: 3000).messageKey
        )
    }

    // MARK: What a failure message may never contain (T042 / FR-021a, FR-022)

    private static let allErrors: [AnalysisError] = [
        .noConnection, .timeout, .serviceError, .invalidResponse,
        .photoRejected, .rateLimited(retryAfter: 20)
    ]

    private func localized(_ key: String, language: String) throws -> String {
        let path = try XCTUnwrap(
            Bundle.main.path(forResource: language, ofType: "lproj"),
            "no \(language) resources in the app bundle"
        )
        let bundle = try XCTUnwrap(Bundle(path: path))
        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        XCTAssertNotEqual(value, key, "\(key) has no \(language) value")
        return value
    }

    /// Principle VI: both languages ship together, and neither may fall back to
    /// a raw key that VoiceOver would then read aloud.
    func testEveryErrorMessageHasEnglishAndSpanishCopy() throws {
        for error in Self.allErrors {
            for language in ["en", "es"] {
                let message = try localized(error.messageKey, language: language)
                XCTAssertFalse(message.isEmpty)
                XCTAssertFalse(message.hasPrefix("analysis."), "raw key leaked into the UI")
            }
        }
    }

    /// FR-022. The user is told what happened and what to do; they are never
    /// shown who the app talks to or what code came back. A provider name on
    /// screen is also how a "generic" `503` stops being generic.
    func testNoErrorMessageNamesAProviderOrACode() throws {
        let forbidden = ["gemini", "google", "openai", "http", "503", "422", "429",
                         "status", "api", "token", "request id", "x-request-id"]

        for error in Self.allErrors {
            for language in ["en", "es"] {
                let message = try localized(error.messageKey, language: language).lowercased()
                for term in forbidden {
                    XCTAssertFalse(
                        message.contains(term),
                        "\(error.messageKey) [\(language)] leaks \"\(term)\": \(message)"
                    )
                }
                XCTAssertFalse(
                    message.contains(where: \.isNumber),
                    "\(error.messageKey) [\(language)] carries a number; the countdown belongs on the button"
                )
            }
        }
    }

    /// Rule E2 / FR-021a. `AnalysisError` has nowhere to *put* the server's
    /// Spanish-only message, which is the structural reason it can never reach
    /// an English screen. `.rateLimited`'s wait is a `TimeInterval`, not text.
    func testNoErrorCaseCanCarryServerText() {
        for error in Self.allErrors {
            let description = String(describing: error)
            XCTAssertFalse(
                description.contains("no está disponible") || description.contains("no es válida"),
                "an error case must not be able to carry the server's own copy"
            )
        }
    }
}
