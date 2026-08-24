//
//  AnalysisError.swift
//  Kalorias
//
//  Why an analysis could not produce a total. Each case maps to a localized,
//  actionable message (see AnalysisResultView). Never yields a displayed calorie
//  number.
//
//  THE ACTION IS PART OF THE CASE, not an afterthought. Most failures offer
//  Retry, but `.photoRejected` must not: re-sending the same bytes cannot
//  succeed, so the screen offers Retake instead (rule E3 / FR-019). And
//  `.rateLimited` offers Retry that is *disabled* until its countdown expires.
//
//  NO MESSAGE NAMES A PROVIDER, MODEL OR UPSTREAM CODE (rule E1 / FR-022), and
//  the server's own message text is never surfaced — it arrives Spanish-only
//  while the app is bilingual, so it goes to the log instead (rule E2 / FR-021a).
//

import Foundation

nonisolated enum AnalysisError: Error, Equatable {
    case noConnection
    case timeout
    case serviceError
    case invalidResponse
    /// The photo itself cannot be analyzed — refused by the server (`422`,
    /// `413`) or too large to send at all. Retaking is the only way forward.
    case photoRejected
    /// Too many analyses for now (`429`). Carries the server's `Retry-After`
    /// in seconds, already parsed and clamped by `RetryCooldown`.
    case rateLimited(retryAfter: TimeInterval)

    /// Localization key for the user-facing message.
    var messageKey: String {
        switch self {
        case .noConnection: "analysis.error.noConnection"
        case .timeout: "analysis.error.timeout"
        case .serviceError: "analysis.error.service"
        case .invalidResponse: "analysis.error.invalidResponse"
        case .photoRejected: "analysis.error.photoRejected"
        // Deliberately carries no number: the remaining seconds live on the
        // button, in `analysis.retryIn`, so there is one moving value in one
        // place (contracts/ui-contracts.md).
        case .rateLimited: "analysis.error.rateLimited"
        }
    }

    /// Map a low-level error (e.g. from URLSession) to an analysis error.
    static func from(_ error: any Error) -> AnalysisError {
        if let analysis = error as? AnalysisError { return analysis }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return .noConnection
            case .timedOut:
                return .timeout
            default:
                return .serviceError
            }
        }
        if error is DecodingError { return .invalidResponse }
        return .serviceError
    }
}
