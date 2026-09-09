//
//  RemoteOnboardingService.swift
//  Kalorias
//
//  The real `OnboardingProviding`: `GET` the questionnaire, `POST` the answers.
//
//  PATHS, NEVER WHOLE URLS. The address comes from `BackendEnvironment` and
//  nowhere else (constitution, Backend Environments) — and in particular never
//  from inside the payload, which would be an open redirect wearing a different
//  hat.
//
//  THE QUESTIONNAIRE IS CACHEABLE, THE SUBMISSION IS NOT. The `GET` is public
//  content that changes on deploys, so it uses the shared session and lets
//  `ETag` do its job; the `POST` carries health data and goes out authenticated,
//  on an ephemeral session that keeps no cache and no cookies.
//
//  THE `GET` STAYS ANONYMOUS, AND THAT IS A REQUIREMENT, NOT AN OVERSIGHT
//  (FR-004, FR-045). It carries no `Authorization`, no user id, no device id and
//  no analytics identity, because it happens before an account exists and must
//  not become a way to correlate a person with the questionnaire they were
//  served. `ETag` is the only state it keeps.
//
//  THE `POST` IS THE OPPOSITE, since feature 010: a valid Kalorias bearer is
//  mandatory, and it goes through `AuthenticatedHTTPClient` so token refresh and
//  the single safe replay are decided in one place rather than here.
//
//  `Idempotency-Key` IS THE WHOLE RETRY STORY. The app resends the same
//  `sessionId` after a timeout, and the server is expected to answer the first
//  result rather than build a second plan.
//

import Foundation

nonisolated struct RemoteOnboardingService: OnboardingFetching {

    static let onboardingPath = "/api/v1/kalorias/onboarding"

    /// Shorter than the analysis timeout on purpose: this is a small JSON
    /// document, not a model waiting on a photo. A minute of spinner before the
    /// bundled copy appears would be a worse first launch than no network at all.
    static let requestTimeout: TimeInterval = 15
    static let resourceTimeout: TimeInterval = 30

    let baseURL: URL?
    let session: URLSession

    init(baseURL: URL? = BackendEnvironment.analysisBaseURL, session: URLSession = Self.makeSession()) {
        self.baseURL = baseURL
        self.session = session
    }

    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        return configuration
    }

    static func makeSession() -> URLSession {
        URLSession(configuration: makeConfiguration())
    }

    // MARK: Fetching

    func fetchQuestionnaire(languageCode: String) async throws -> FetchedQuestionnaire {
        guard let baseURL else { throw OnboardingError.serviceError }

        var components = URLComponents(
            url: baseURL.appending(path: Self.onboardingPath),
            resolvingAgainstBaseURL: false
        )
        // `stage` is explicit rather than left to the server's default: the app
        // asks for exactly the tranche it is about to show.
        components?.queryItems = [URLQueryItem(name: "stage", value: "onboarding")]
        guard let url = components?.url else { throw OnboardingError.serviceError }

        var request = URLRequest(url: url)
        request.setValue(languageCode, forHTTPHeaderField: "Accept-Language")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OnboardingError.serviceError }
        guard http.statusCode == 200 else { throw OnboardingError.serviceError }

        let questionnaire = try JSONDecoder().decode(QuestionnaireEnvelope.self, from: data).data

        // Refused whole rather than partially understood. Skipping the parts
        // this build does not recognise is how a plan gets calculated from data
        // that was never collected.
        guard questionnaire.schemaVersion <= Questionnaire.supportedSchemaVersion else {
            throw OnboardingError.unsupportedSchema(version: questionnaire.schemaVersion)
        }

        return FetchedQuestionnaire(questionnaire: questionnaire, payload: data)
    }
}
