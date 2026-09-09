//
//  AppleSignInRequestFactoryTests.swift
//  KaloriasTests
//
//  The two random values that make one Apple authorization unrepeatable, and the
//  rules that decide whether its callback is trusted at all.
//
//  THE NONCE SPLIT IS THE WHOLE SECURITY ARGUMENT, so it is asserted directly:
//  Apple receives the SHA-256 *hash*, the backend receives the *preimage*, and
//  swapping them — or letting the same value serve both — makes a captured
//  identity token replayable. A test that only checked "a nonce was set" would
//  pass on exactly that mistake.
//

import AuthenticationServices
import CryptoKit
import XCTest
@testable import Kalorias

nonisolated final class AppleSignInRequestFactoryTests: XCTestCase {

    /// A counter-based generator, so every value in a test is known and every
    /// call still differs from the last.
    private static func countingBytes() -> @Sendable (Int) -> Data {
        let counter = Counter()
        return { count in
            let seed = counter.next()
            return Data((0..<count).map { UInt8(($0 + Int(seed)) % 251) })
        }
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value: UInt8 = 0
        func next() -> UInt8 {
            lock.withLock {
                value = value &+ 1
                return value
            }
        }
    }

    // MARK: Shape

    @MainActor
    func testTheHashedNonceIsTheLowercaseSHA256OfTheRawOne() {
        let factory = AppleSignInRequestFactory(randomBytes: Self.countingBytes())

        let attempt = factory.begin()

        let expected = SHA256.hash(data: Data(attempt.rawNonce.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        XCTAssertEqual(attempt.hashedNonce, expected)
        XCTAssertEqual(attempt.hashedNonce, attempt.hashedNonce.lowercased(),
                       "Apple documents lowercase hex; uppercase fails verification silently")
        XCTAssertEqual(attempt.hashedNonce.count, 64)
    }

    /// If the state were derived from the nonce, an attacker who learned one
    /// would have both. They are independent draws.
    @MainActor
    func testStateIsIndependentOfTheNonce() {
        let factory = AppleSignInRequestFactory(randomBytes: Self.countingBytes())

        let attempt = factory.begin()

        XCTAssertNotEqual(attempt.state, attempt.rawNonce)
        XCTAssertNotEqual(attempt.state, attempt.hashedNonce)
        XCTAssertFalse(attempt.state.isEmpty)
    }

    /// Base64url without padding: these values travel inside a JWT claim and a
    /// URL, where `+`, `/` and `=` are all wrong.
    @MainActor
    func testRandomValuesAreURLSafe() {
        let factory = AppleSignInRequestFactory(randomBytes: Self.countingBytes())

        let attempt = factory.begin()

        for value in [attempt.rawNonce, attempt.state] {
            XCTAssertFalse(value.contains("+"))
            XCTAssertFalse(value.contains("/"))
            XCTAssertFalse(value.contains("="))
        }
    }

    @MainActor
    func testEachAttemptDrawsFreshValues() {
        let factory = AppleSignInRequestFactory(randomBytes: Self.countingBytes())

        let first = factory.begin()
        let second = factory.begin()

        XCTAssertNotEqual(first.rawNonce, second.rawNonce)
        XCTAssertNotEqual(first.state, second.state)
    }

    // MARK: The request Apple is given

    /// Apple gets the hash and never the preimage — the single most important
    /// property here.
    @MainActor
    func testAppleReceivesTheHashedNonceAndNoProfileScope() {
        let factory = AppleSignInRequestFactory(randomBytes: Self.countingBytes())
        let request = ASAuthorizationAppleIDProvider().createRequest()

        factory.configure(request)

        let attempt = try! XCTUnwrap(factory.current)
        XCTAssertEqual(request.nonce, attempt.hashedNonce)
        XCTAssertNotEqual(request.nonce, attempt.rawNonce, "the preimage must not reach Apple")
        XCTAssertEqual(request.state, attempt.state)
        XCTAssertEqual(request.requestedScopes ?? [], [],
                       "V1 asks Apple for no name and no email (FR-012)")
    }

    // MARK: Consuming a callback

    /// A callback with no attempt outstanding is a callback that belongs to
    /// nothing. Nothing is sent.
    @MainActor
    func testAConsumeWithNoAttemptFails() {
        let factory = AppleSignInRequestFactory(randomBytes: Self.countingBytes())

        let result = factory.consume(state: "anything")

        XCTAssertEqual(result.failureError, .noAttemptInFlight)
    }

    @MainActor
    func testAMismatchedStateIsRejectedLocally() {
        let factory = AppleSignInRequestFactory(randomBytes: Self.countingBytes())
        factory.begin()

        let result = factory.consume(state: "somebody-else's-state")

        XCTAssertEqual(result.failureError, .stateMismatch)
    }

    @MainActor
    func testAMissingIdentityTokenIsRefused() {
        let factory = AppleSignInRequestFactory(randomBytes: Self.countingBytes())
        let attempt = factory.begin()

        let result = factory.consume(state: attempt.state, identityToken: nil)

        XCTAssertEqual(result.failureError, .missingIdentityToken)
    }

    @MainActor
    func testAMissingAuthorizationCodeIsRefused() {
        let factory = AppleSignInRequestFactory(randomBytes: Self.countingBytes())
        let attempt = factory.begin()

        let result = factory.consume(state: attempt.state, authorizationCode: nil)

        XCTAssertEqual(result.failureError, .missingAuthorizationCode)
    }

    /// Bytes that are not UTF-8 are not a token, and coercing them would send
    /// the backend something Apple never signed.
    @MainActor
    func testInvalidUTF8IsRefused() {
        let factory = AppleSignInRequestFactory(randomBytes: Self.countingBytes())
        let attempt = factory.begin()

        let result = factory.consume(
            state: attempt.state,
            identityTokenData: Data([0xFF, 0xFE, 0xFD])
        )

        XCTAssertEqual(result.failureError, .missingIdentityToken)
    }

    @MainActor
    func testAnEmptyTokenIsRefused() {
        let factory = AppleSignInRequestFactory(randomBytes: Self.countingBytes())
        let attempt = factory.begin()

        let result = factory.consume(state: attempt.state, identityToken: "")

        XCTAssertEqual(result.failureError, .missingIdentityToken)
    }

    @MainActor
    func testAValidCallbackCarriesTheRawNonceForwards() {
        let factory = AppleSignInRequestFactory(randomBytes: Self.countingBytes())
        let attempt = factory.begin()

        let result = factory.consume(state: attempt.state)

        let credential = try! XCTUnwrap(result.successValue)
        XCTAssertEqual(credential.rawNonce, attempt.rawNonce, "the backend gets the preimage")
        XCTAssertEqual(credential.identityToken, "identity-token")
        XCTAssertEqual(credential.authorizationCode, "authorization-code")
        XCTAssertEqual(credential.appleUserIdentifier, "apple-sub-1")
    }

    /// A nonce that outlives its sheet is a nonce that can be reused.
    @MainActor
    func testAnAttemptIsConsumedExactlyOnce() {
        let factory = AppleSignInRequestFactory(randomBytes: Self.countingBytes())
        let attempt = factory.begin()

        _ = factory.consume(state: attempt.state)
        let second = factory.consume(state: attempt.state)

        XCTAssertNil(factory.current)
        XCTAssertEqual(second.failureError, .noAttemptInFlight)
    }

    /// A rejected callback consumes the attempt too, so it cannot be retried
    /// against the same nonce.
    @MainActor
    func testARejectedCallbackAlsoConsumesTheAttempt() {
        let factory = AppleSignInRequestFactory(randomBytes: Self.countingBytes())
        factory.begin()

        _ = factory.consume(state: "wrong")

        XCTAssertNil(factory.current)
    }

    @MainActor
    func testClearingForgetsTheAttempt() {
        let factory = AppleSignInRequestFactory(randomBytes: Self.countingBytes())
        factory.begin()

        factory.clear()

        XCTAssertNil(factory.current)
    }

    // MARK: Redaction

    /// Interpolating a credential must not print a token. Both descriptions are
    /// overridden, because `print` and the debugger reach for different ones.
    @MainActor
    func testACredentialCannotBeLogged() {
        let credential = AuthFixtures.appleCredential()

        XCTAssertFalse("\(credential)".contains("identity-token"))
        XCTAssertFalse(String(reflecting: credential).contains("identity-token"))
        XCTAssertFalse("\(credential)".contains("raw-nonce"))
    }

    @MainActor
    func testADeletionAttemptCannotLogItsBearer() {
        let attempt = AccountDeletionAttempt(
            operationId: UUID(),
            presentedAccessToken: "super-secret-bearer",
            ownerUserID: "user-1",
            confirmedAt: Date(timeIntervalSince1970: 1)
        )

        XCTAssertFalse("\(attempt)".contains("super-secret-bearer"))
        XCTAssertFalse(String(reflecting: attempt).contains("super-secret-bearer"))
    }
}

// MARK: - Calling the rules

/// `ASAuthorizationAppleIDCredential` has no public initialiser and cannot be
/// subclassed usefully, which is exactly why `consume` takes the raw fields: the
/// rules are reachable without the framework object standing in the way.
private extension AppleSignInRequestFactory {
    @MainActor
    func consume(
        state: String?,
        identityToken: String? = "identity-token",
        authorizationCode: String? = "authorization-code",
        identityTokenData: Data? = nil,
        appleUserIdentifier: String = "apple-sub-1"
    ) -> Result<AppleAuthorizationCredential, AppleAuthorizationError> {
        consume(
            state: state,
            identityToken: identityTokenData ?? identityToken.map { Data($0.utf8) },
            authorizationCode: authorizationCode.map { Data($0.utf8) },
            appleUserIdentifier: appleUserIdentifier
        )
    }
}

// MARK: - Result helpers

private extension Result where Success == AppleAuthorizationCredential,
                               Failure == AppleAuthorizationError {
    var successValue: AppleAuthorizationCredential? {
        if case let .success(value) = self { return value }
        return nil
    }

    var failureError: AppleAuthorizationError? {
        if case let .failure(error) = self { return error }
        return nil
    }
}
