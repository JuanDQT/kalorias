//
//  OnboardingProviding.swift
//  Kalorias
//
//  The boundary that hides the onboarding endpoints from the store and the UI
//  (constitution Principle V), so both are unit-testable against a stub.
//
//  TWO PROTOCOLS, BECAUSE THEY ARE TWO DIFFERENT TRUST DOMAINS. Feature 010
//  split what used to be one: `GET`ting the questionnaire is public product
//  content that anyone may read and that must work before an account exists;
//  `POST`ing the answers is authenticated, consented, health data. Keeping them
//  in one protocol meant the store that runs the chat held a reference to the
//  thing that can upload — and "the type that could send it never had it" is a
//  much stronger guarantee than "the type that could send it chose not to".
//
//  There is still no request per question and no session state on the server —
//  going back and editing is entirely a client-side matter, which is why it can
//  be instant.
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

/// The public half: content only, no credential, no user, no device identity
/// (FR-004, FR-045).
protocol OnboardingFetching: Sendable {
    /// The questionnaire for `languageCode`, already translated by the server.
    nonisolated func fetchQuestionnaire(languageCode: String) async throws -> FetchedQuestionnaire
}

/// The authenticated half: the sealed answers, sent once an account exists and
/// consent has been given (FR-019, FR-046).
protocol OnboardingSubmitting: Sendable {
    /// Submit the sealed onboarding with its consent receipt.
    ///
    /// Idempotent on `pending.submission.sessionId`, which also travels as
    /// `Idempotency-Key`, so a resend after a timeout returns the original
    /// result instead of creating a second plan.
    nonisolated func submit(_ pending: PendingOnboarding) async throws -> OnboardingSubmissionResult
}

/// What the server says it did with a submission.
nonisolated struct OnboardingSubmissionResult: Decodable, Equatable, Sendable {
    let onboardingStatus: OnboardingServerStatus
    let planId: String?
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

    // The stable submission outcomes feature 010 has to act on differently.
    // They are separate cases rather than one `serviceError` because each drives
    // a different journey transition, not merely different copy.

    /// The session was rejected even after one refresh. Back to access, answers
    /// preserved (FR-032).
    case authenticationRequired
    /// The account already has a plan. Reconcile to complete; do not resend.
    case alreadyComplete
    /// The same key was presented with a different body. Stop retrying — a new
    /// key would be a second plan (contract, `idempotency_payload_mismatch`).
    case idempotencyMismatch
    /// The accepted consent version is no longer the approved one. Back to the
    /// consent gate; the old receipt cannot be reused.
    case consentOutdated
    /// The server refused the answers themselves. They stay local.
    case invalidOnboarding

    var messageKey: String.LocalizationValue {
        switch self {
        case .noConnection: "onboarding.error.noConnection"
        case .timeout: "onboarding.error.timeout"
        case .serviceError, .invalidResponse, .unsupportedSchema: "onboarding.error.service"
        case .authenticationRequired, .alreadyComplete: "finalization.error.generic"
        case .idempotencyMismatch: "finalization.error.generic"
        case .consentOutdated: "consent.outdated"
        case .invalidOnboarding: "finalization.error.validation"
        }
    }

    /// The finalization screen's copy, which distinguishes a network problem
    /// from answers the server would not accept.
    var finalizationMessageKey: String.LocalizationValue {
        switch self {
        case .noConnection, .timeout: "finalization.error.network"
        case .invalidOnboarding: "finalization.error.validation"
        case .consentOutdated: "consent.outdated"
        default: "finalization.error.generic"
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
