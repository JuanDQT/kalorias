//
//  AppleSignInRequestFactory.swift
//  Kalorias
//
//  Builds one Sign in with Apple authorization and holds the secrets that prove
//  its result belongs to it (feature 010, FR-011).
//
//  TWO RANDOM VALUES, TWO DIFFERENT JOBS, AND BOTH ARE NEEDED.
//
//  The *nonce* is Apple's replay defence. The app sends Apple the SHA-256 of a
//  random value and keeps the original; Apple embeds that hash in the identity
//  token it signs. The backend hashes the raw nonce the app gives it and
//  compares. An attacker replaying a captured identity token has the hash but
//  not the preimage, so they cannot make the backend accept it. This is why the
//  raw nonce is sent to Kalorias and never to Apple, and the hash to Apple and
//  never to Kalorias.
//
//  The *state* is the app's own correlation value, and it defends against a
//  different thing: a callback arriving that belongs to some other attempt. It
//  is compared locally, before any network call, so a mismatched result is
//  discarded on the device and nothing is sent at all.
//
//  NO NAME OR EMAIL SCOPE (FR-012). Kalorias needs a verified stable identity,
//  not a person's name or address. Requesting them would collect data the
//  product does not use, and — because Apple returns them exactly once, on the
//  very first authorization for an app — would make correctness depend on a
//  field that is simply absent every other time.
//
//  ONE ATTEMPT AT A TIME. `begin()` replaces whatever was outstanding, and the
//  attempt is consumed on the first callback. Duplicate taps therefore cannot
//  produce two concurrent registrations.
//
//  `SecRandomCopyBytes`, not `Int.random`: this is a security value, and a
//  seedable PRNG is not one.
//

import AuthenticationServices
import CryptoKit
import Foundation

/// The two secrets bound to one authorization sheet. Memory only — it is never
/// written to disk and never logged.
nonisolated struct AppleSignInAttempt: Equatable, Sendable {
    /// The value the backend verifies against the token's nonce claim.
    let rawNonce: String
    /// The lowercase SHA-256 hex of `rawNonce`, which is what Apple receives.
    let hashedNonce: String
    /// Independent correlation value for this callback.
    let state: String
}

@MainActor
@Observable
final class AppleSignInRequestFactory {

    /// The outstanding attempt, if a sheet is open.
    private(set) var current: AppleSignInAttempt?

    /// How the random bytes are produced. Injectable so tests are deterministic;
    /// the default is the system CSPRNG.
    private let randomBytes: (Int) -> Data

    init(randomBytes: @escaping (Int) -> Data = AppleSignInRequestFactory.secureRandomBytes) {
        self.randomBytes = randomBytes
    }

    /// 32 bytes: the same order of magnitude as the token it protects, and well
    /// past any birthday-bound concern for a single-use value.
    nonisolated static let entropyByteCount = 32

    nonisolated static func secureRandomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            // The CSPRNG failing is not a condition to paper over with a weaker
            // source: an authorization bound by a guessable nonce is worse than
            // one that did not happen.
            fatalError("The system random number generator is unavailable.")
        }
        return Data(bytes)
    }

    // MARK: Beginning an attempt

    /// Prepare a fresh attempt and configure the request Apple will present.
    ///
    /// Any previous attempt is discarded here, which is what makes a second tap
    /// harmless rather than a second registration.
    func configure(_ request: ASAuthorizationAppleIDRequest) {
        let attempt = begin()
        // Deliberately empty: V1 asks Apple for no personal information.
        request.requestedScopes = []
        request.nonce = attempt.hashedNonce
        request.state = attempt.state
    }

    @discardableResult
    func begin() -> AppleSignInAttempt {
        let rawNonce = Self.base64URL(randomBytes(Self.entropyByteCount))
        let attempt = AppleSignInAttempt(
            rawNonce: rawNonce,
            hashedNonce: Self.sha256Hex(rawNonce),
            state: Self.base64URL(randomBytes(Self.entropyByteCount))
        )
        current = attempt
        return attempt
    }

    /// Forget the outstanding attempt: on cancellation, on error, and after a
    /// callback has been consumed. A nonce that outlives its sheet is a nonce
    /// that can be reused.
    func clear() {
        current = nil
    }

    // MARK: Consuming a callback

    /// Map an Apple credential into the value the backend is given, but only if
    /// it belongs to the outstanding attempt.
    ///
    /// Fails closed on every ambiguity: no attempt, a `state` that does not
    /// match exactly, a missing token or code, bytes that are not UTF-8, or an
    /// empty value. The attempt is consumed either way, so a rejected callback
    /// cannot be retried against the same nonce.
    func consume(
        _ credential: ASAuthorizationAppleIDCredential
    ) -> Result<AppleAuthorizationCredential, AppleAuthorizationError> {
        // A four-line adapter, and nothing else, over the framework type.
        // `ASAuthorizationAppleIDCredential` has no public initialiser, so the
        // rules below can only be tested if they do not live behind it.
        consume(
            state: credential.state,
            identityToken: credential.identityToken,
            authorizationCode: credential.authorizationCode,
            appleUserIdentifier: credential.user
        )
    }

    /// The rules themselves, over the raw fields Apple returns.
    func consume(
        state: String?,
        identityToken identityData: Data?,
        authorizationCode codeData: Data?,
        appleUserIdentifier user: String
    ) -> Result<AppleAuthorizationCredential, AppleAuthorizationError> {
        guard let attempt = current else { return .failure(.noAttemptInFlight) }
        clear()

        // Constant-time is unnecessary here — `state` is not a secret an
        // attacker can grind against a local comparison — but *exact* is not:
        // a prefix or case-insensitive match would defeat the point.
        guard state == attempt.state else { return .failure(.stateMismatch) }

        guard let identityData,
              let identityToken = String(data: identityData, encoding: .utf8),
              !identityToken.isEmpty
        else { return .failure(.missingIdentityToken) }

        guard let codeData,
              let authorizationCode = String(data: codeData, encoding: .utf8),
              !authorizationCode.isEmpty
        else { return .failure(.missingAuthorizationCode) }

        guard !user.isEmpty else { return .failure(.missingUserIdentifier) }

        return .success(
            AppleAuthorizationCredential(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                appleUserIdentifier: user,
                rawNonce: attempt.rawNonce
            )
        )
    }

    // MARK: Encoding

    /// Base64url without padding: safe inside a JWT claim and inside a URL,
    /// which is where these values end up.
    nonisolated static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Lowercase hex, because that is the representation Apple documents for the
    /// nonce claim and an uppercase one silently fails verification.
    nonisolated static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
