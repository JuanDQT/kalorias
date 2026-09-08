//
//  OnboardingProviding.swift
//  Kalorias
//
//  The boundary that hides the onboarding endpoints from the store and the UI
//  (constitution Principle V), so both are unit-testable against a stub.
//
//  Two calls and no more: one `GET` when the chat opens, one `POST` when it
//  finishes. There is no request per question and no session state on the
//  server — going back and editing is entirely a client-side matter, which is
//  why it can be instant.
//

import Foundation

/// A questionnaire and the bytes it was decoded from.
///
/// THE BYTES ARE THE POINT. The cache stores what the server actually sent, not
/// a re-encoding of the decoded value: a synthesised encoder does not produce
/// the keys this decoder reads, and a future build with a wider decoder can
/// still make sense of a payload this one only partly understood.
nonisolated struct FetchedQuestionnaire: Sendable {
    let questionnaire: Questionnaire
    let payload: Data
}

protocol OnboardingProviding: Sendable {
    /// The questionnaire for `languageCode`, already translated by the server.
    func fetchQuestionnaire(languageCode: String) async throws -> FetchedQuestionnaire
    /// Submit the finished onboarding. Idempotent on the submission's
    /// `sessionId`, so a resend after a timeout cannot create a second plan.
    func submit(_ submission: OnboardingSubmission) async throws
}

/// Why the onboarding could not be fetched or submitted.
///
/// No case names a provider, a status code or an internal identifier: the
/// constitution's external-services clause bars all three from the UI, and the
/// user gets a plain, actionable message instead.
nonisolated enum OnboardingError: Error, Equatable {
    case noConnection
    case timeout
    case serviceError
    case invalidResponse
    /// The payload declares a structure this build does not understand. The app
    /// falls back to its bundled copy rather than guessing at the difference.
    case unsupportedSchema(version: Int)

    var messageKey: String.LocalizationValue {
        switch self {
        case .noConnection: "onboarding.error.noConnection"
        case .timeout: "onboarding.error.timeout"
        case .serviceError, .invalidResponse, .unsupportedSchema: "onboarding.error.service"
        }
    }

    static func from(_ error: any Error) -> OnboardingError {
        if let onboarding = error as? OnboardingError { return onboarding }
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
