//
//  BackendEnvironment.swift
//  Kalorias
//
//  The one place the app decides *where* it talks to. Replaces `AppSecrets`,
//  which held an AI-provider key: the app no longer has one. Analysis happens
//  on the Kalorias backend, which owns the prompt, the response schema and the
//  credential (feature 009).
//
//  THE ADDRESS COMES FROM THE BUILD CONFIGURATION, NOT FROM SOURCE. The
//  constitution's Backend Environments clause allows exactly two mechanisms for
//  the debug/production decision, and this is the second: the address is an
//  xcconfig value (`KALORIAS_API_BASE_URL`, selected by `$(CONFIGURATION)` in
//  `Config/Secrets.xcconfig`) surfaced through `Info.plist` and read here at
//  launch. The choice therefore lives in the build configuration, in one place,
//  where a release build cannot resolve a debug address and no runtime default
//  can override it.
//
//  SAYS *WHERE*, NEVER *WHAT*. It names the Info-dictionary key an address
//  arrives under; it holds no credential, no path, and no request shape.
//
//  `nonisolated` is load-bearing, not stylistic: the project builds with
//  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so without it this enum would
//  be MainActor-isolated and unusable from `RemoteCalorieService`'s nonisolated
//  context.
//

import Foundation

nonisolated enum BackendEnvironment {

    /// The Info-dictionary key the backend address arrives under, fed by
    /// `KALORIAS_API_BASE_URL` in the git-ignored `Config/Secrets.xcconfig`.
    ///
    /// This is the *name of a location*, which this type may hold.
    static let baseURLInfoDictionaryKey = "KaloriasAPIBaseURL"

    /// How a value is fetched from the app's Info dictionary. A parameter
    /// rather than a hardcoded `Bundle.main` call so the parsing rules can be
    /// tested — including that the *right* key is asked for.
    ///
    /// Stubbing `Bundle` itself does not work: `Bundle.init(path:)` returns the
    /// cached instance for that path, so a subclass's overrides are never
    /// called and the test silently reads the real Info.plist instead.
    static let infoDictionaryLookup: @Sendable (String) -> String? = { key in
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    /// Scheme and host only. Call sites append a path; nobody writes a whole
    /// URL.
    ///
    /// `nil` when the value is absent, blank, or does not parse into an
    /// absolute URL carrying **both a scheme and a host**. That last condition
    /// is the xcconfig `//` guard: written literally, `https://www.quispe.com`
    /// becomes `https:` in an xcconfig, which `URL(string:)` accepts happily
    /// and which resolves to nothing. Requiring a host turns that silent
    /// misconfiguration into `.serviceError` on the first analysis instead of a
    /// mystery, and `BackendEnvironmentTests` fails on it at build time.
    static var analysisBaseURL: URL? { baseURL(readingFrom: infoDictionaryLookup) }

    /// Whether this build has a usable backend address.
    static var isConfigured: Bool { analysisBaseURL != nil }

    /// The Info-dictionary key the published privacy policy arrives under, fed
    /// by `PRIVACY_POLICY_URL` in `Config/Secrets.xcconfig`.
    ///
    /// It lives here for the same reason the API address does: the constitution
    /// allows exactly one place to decide *where* the app points, and the
    /// grep-able audit that enforces it does not — and should not — try to tell
    /// an API host from a policy host. It is a public document, not a
    /// credential, and the app only ever opens it (feature 010).
    static let privacyPolicyURLInfoDictionaryKey = "KaloriasPrivacyPolicyURL"

    static let privacyNoticeVersionInfoDictionaryKey = "KaloriasPrivacyNoticeVersion"

    static let healthDataConsentVersionInfoDictionaryKey = "KaloriasHealthDataConsentVersion"

    /// Public App Store listing used by the mandatory-update gate. This is a
    /// release setting because the numeric App Store ID does not exist until
    /// App Store Connect creates the product record.
    static let appStoreURLInfoDictionaryKey = "KaloriasAppStoreURL"

    /// The privacy notice's external link, or `nil` when this build has no
    /// approved release configuration.
    static var privacyPolicyURL: URL? { baseURL(readingFrom: infoDictionaryLookup, key: privacyPolicyURLInfoDictionaryKey) }

    static var appStoreURL: URL? {
        baseURL(readingFrom: infoDictionaryLookup, key: appStoreURLInfoDictionaryKey)
    }

    /// The three Product/Legal inputs that must move together. Returning `nil`
    /// is a fail-closed release guard: a build with a missing policy URL or an
    /// invalid version can display the notice, but cannot mint a consent receipt
    /// or upload health answers.
    static var consentConfiguration: ConsentConfiguration? {
        consentConfiguration(readingFrom: infoDictionaryLookup)
    }

    static func consentConfiguration(
        readingFrom lookup: (String) -> String?
    ) -> ConsentConfiguration? {
        guard
            let policyURL = baseURL(readingFrom: lookup, key: privacyPolicyURLInfoDictionaryKey),
            let privacyNoticeVersion = configuredIdentifier(
                lookup(privacyNoticeVersionInfoDictionaryKey)
            ),
            let healthDataConsentVersion = configuredIdentifier(
                lookup(healthDataConsentVersionInfoDictionaryKey)
            )
        else {
            return nil
        }

        return ConsentConfiguration(
            privacyPolicyURL: policyURL,
            privacyNoticeVersion: privacyNoticeVersion,
            healthDataConsentVersion: healthDataConsentVersion
        )
    }

    /// The parsing rules, over an injectable lookup so they are testable.
    static func baseURL(
        readingFrom lookup: (String) -> String?,
        key: String = BackendEnvironment.baseURLInfoDictionaryKey
    ) -> URL? {
        guard let raw = lookup(key) else { return nil }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard
            let url = URL(string: trimmed),
            let scheme = url.scheme, !scheme.isEmpty,
            let host = url.host(), !host.isEmpty
        else {
            return nil
        }

        return url
    }

    /// Consent identifiers are an API contract, not display text. Reject blank,
    /// oversized and visibly provisional values so they cannot become audit
    /// receipts by accident.
    static func configuredIdentifier(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= ConsentConfiguration.maximumVersionLength else {
            return nil
        }

        let normalized = value.lowercased()
        guard !normalized.contains("pendiente"), !normalized.contains("placeholder") else {
            return nil
        }
        return value
    }
}
