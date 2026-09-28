//
//  RemoteOnboardingSubmissionService.swift
//  Kalorias
//
//  `POST /api/v1/kalorias/onboarding`: the sealed answers, sent once an account
//  exists and consent has been given (feature 010, FR-019, FR-046).
//
//  IT IS A SEPARATE TYPE FROM THE FETCH SERVICE ON PURPOSE. The store that runs
//  the chat holds only `OnboardingFetching`, so the object that can upload
//  health data is not reachable from the screen where the user is still typing.
//  "It never had the ability" beats "it chose not to".
//
//  THE BODY IS THE SEALED SUBMISSION PLUS THE RECEIPT, AND NOTHING ELSE. Consent
//  travels as its own object; it is not folded into an answer, and no Apple
//  credential is attached — the bearer is the only authority the server needs.
//
//  `Idempotency-Key` EQUALS `sessionId`, ON EVERY ATTEMPT. This is what makes a
//  lost response harmless: the retry is byte-identical, and the server returns
//  the plan it already made instead of making a second one. Generating a new key
//  after a timeout is the single most expensive mistake available here, which is
//  why the key is read off the payload rather than passed in.
//
//  IT GOES THROUGH `AuthenticatedHTTPClient`, so the "one refresh, one replay"
//  rule is not restated here — and could not drift from the rule the analysis
//  route follows.
//
//  A `409 onboarding_already_complete` IS NOT AN ERROR TO SHOW. It is the server
//  saying the account already has a plan, which is exactly what the client wants
//  to know; the journey reconciles and discards the redundant payload.
//

import Foundation

nonisolated struct RemoteOnboardingSubmissionService: OnboardingSubmitting {

    static let onboardingPath = "/api/v1/kalorias/onboarding"

    let baseURL: URL?
    let client: AuthenticatedHTTPClient

    init(baseURL: URL? = BackendEnvironment.analysisBaseURL, client: AuthenticatedHTTPClient) {
        self.baseURL = baseURL
        self.client = client
    }

    func submit(_ pending: PendingOnboarding) async throws -> OnboardingSubmissionResult {
        guard let baseURL else { throw OnboardingError.serviceError }
        guard let consent = pending.consent else {
            // Unreachable through the journey, and a hard stop if it ever became
            // reachable: no receipt, no upload (FR-018).
            throw OnboardingError.serviceError
        }

        var request = URLRequest(url: baseURL.appending(path: Self.onboardingPath))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            pending.idempotencyKey.uuidString,
            forHTTPHeaderField: "Idempotency-Key"
        )
        request.httpBody = try OnboardingSubmission.makeEncoder().encode(
            Body(submission: pending.submission, consent: consent)
        )

        let (data, http) = try await client.send(request, allowsReplay: true)
        let requestId = http.value(forHTTPHeaderField: "X-Request-Id")

        guard http.statusCode == 200 else {
            let mapped = Self.mapError(status: http.statusCode, data: data)
            AuthLog.failure(
                .onboardingSubmission,
                outcome: String(describing: mapped),
                requestId: requestId
            )
            throw mapped
        }

        let envelope = try OnboardingSubmission.makeDecoder()
            .decode(ResultEnvelope.self, from: data)
        guard envelope.data.onboardingStatus == .complete else {
            // The server accepted the request but does not say the plan exists.
            // Opening the app on that would open it with no plan behind it.
            throw OnboardingError.invalidResponse
        }
        AuthLog.success(.onboardingSubmission, requestId: requestId)
        return envelope.data
    }

    /// The submission fields flattened next to the receipt, matching the wire
    /// contract exactly. Written as its own type so the sealed submission does
    /// not have to carry a consent field it has no business owning.
    private struct Body: Encodable {
        let submission: OnboardingSubmission
        let consent: ConsentReceipt

        private enum CodingKeys: String, CodingKey {
            case sessionId, onboardingId, schemaVersion, contentVersion, locale
            case startedAt, completedAt, consent, answers
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(submission.sessionId, forKey: .sessionId)
            try c.encode(submission.onboardingId, forKey: .onboardingId)
            try c.encode(submission.schemaVersion, forKey: .schemaVersion)
            try c.encode(submission.contentVersion, forKey: .contentVersion)
            try c.encode(submission.locale, forKey: .locale)
            try c.encode(submission.startedAt, forKey: .startedAt)
            try c.encode(submission.completedAt, forKey: .completedAt)
            try c.encode(consent, forKey: .consent)
            try c.encode(submission.answers, forKey: .answers)
        }
    }

    private struct ResultEnvelope: Decodable {
        let data: OnboardingSubmissionResult
    }

    static func mapError(status: Int, data: Data) -> OnboardingError {
        let code = (try? JSONDecoder().decode(RemoteAuthService.ErrorEnvelope.self, from: data))?
            .error.code

        switch (status, code) {
        case (401, "authentication_required"):
            return .authenticationRequired
        case (409, "onboarding_already_complete"):
            return .alreadyComplete
        case (409, "idempotency_payload_mismatch"):
            return .idempotencyMismatch
        case (409, "consent_version_outdated"):
            return .consentOutdated
        case (422, "invalid_onboarding"):
            return .invalidOnboarding
        case (429, "onboarding_rate_limited"),
             (503, "onboarding_service_error"):
            return .serviceError
        default:
            return .serviceError
        }
    }
}
