//
//  AnalysisError.swift
//  Kalorias
//
//  Why an analysis could not produce a total. Each case maps to a localized,
//  actionable message (see AnalysisResultView) with Retry + Cancel (FR-011).
//  Never yields a displayed calorie number.
//

import Foundation

nonisolated enum AnalysisError: Error, Equatable {
    case noConnection
    case timeout
    case serviceError
    case invalidResponse

    /// Localization key for the user-facing message.
    var messageKey: String {
        switch self {
        case .noConnection: "analysis.error.noConnection"
        case .timeout: "analysis.error.timeout"
        case .serviceError: "analysis.error.service"
        case .invalidResponse: "analysis.error.invalidResponse"
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
