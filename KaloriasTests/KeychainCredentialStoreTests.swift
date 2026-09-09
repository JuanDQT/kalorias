//
//  KeychainCredentialStoreTests.swift
//  KaloriasTests
//
//  Against the real Keychain, not a stand-in: the bugs this store exists to
//  prevent — `errSecDuplicateItem` on a second save, a delete that takes the
//  wrong record with it — only exist in `SecItem` itself and a fake would agree
//  with whatever the code does. Each run uses a unique service suffix so it
//  cannot see or clobber the device's own records.
//

import Security
import XCTest
@testable import Kalorias

nonisolated final class KeychainCredentialStoreTests: XCTestCase {

    private var store: KeychainCredentialStore!

    override func setUp() {
        super.setUp()
        store = KeychainCredentialStore(serviceSuffix: ".test.\(UUID().uuidString)")
    }

    override func tearDown() {
        try? store.deleteSession()
        try? store.deleteKnownAccount()
        try? store.deleteDeletionAttempt()
        store = nil
        super.tearDown()
    }

    // MARK: Fixtures

    private func makeSession(
        userId: String = "user-1",
        accessToken: String = "access-1",
        onboardingStatus: OnboardingServerStatus = .required
    ) -> AuthSession {
        AuthSession(
            userId: userId,
            appleUserIdentifier: "apple-sub-1",
            accessToken: accessToken,
            accessTokenExpiresAt: Date(timeIntervalSince1970: 2_000),
            refreshToken: "refresh-1",
            refreshTokenExpiresAt: Date(timeIntervalSince1970: 100_000),
            onboardingStatus: onboardingStatus
        )
    }

    // MARK: Session

    func testSessionRoundTrips() throws {
        let session = makeSession()
        try store.saveSession(session)
        XCTAssertEqual(try store.loadSession(), session)
    }

    func testLoadingAnAbsentSessionReturnsNil() throws {
        XCTAssertNil(try store.loadSession())
    }

    /// The `errSecDuplicateItem` regression: a second save must update the
    /// stored value, not silently keep the first one.
    func testSavingTwiceUpdatesRatherThanDuplicating() throws {
        try store.saveSession(makeSession(accessToken: "first"))
        try store.saveSession(makeSession(accessToken: "second"))

        XCTAssertEqual(try store.loadSession()?.accessToken, "second")
    }

    func testDeletingSessionRemovesIt() throws {
        try store.saveSession(makeSession())
        try store.deleteSession()
        XCTAssertNil(try store.loadSession())
    }

    /// Cleanup after a confirmed deletion may be interrupted and resumed.
    func testDeletingAnAbsentSessionSucceeds() {
        XCTAssertNoThrow(try store.deleteSession())
    }

    // MARK: Separate records

    func testSessionAndKnownAccountAreSeparateRecords() throws {
        let session = makeSession()
        try store.saveSession(session)
        try store.saveKnownAccount(KnownAccount(session: session))

        try store.deleteSession()

        XCTAssertNil(try store.loadSession())
        XCTAssertEqual(try store.loadKnownAccount()?.userId, "user-1")
    }

    func testKnownAccountRoundTripsWithoutACredential() throws {
        let account = KnownAccount(
            userId: "user-1",
            appleUserIdentifier: "apple-sub-1",
            onboardingStatus: .complete
        )
        try store.saveKnownAccount(account)
        XCTAssertEqual(try store.loadKnownAccount(), account)
    }

    func testDeletionAttemptIsItsOwnRecord() throws {
        let attempt = AccountDeletionAttempt(
            operationId: UUID(),
            presentedAccessToken: "access-1",
            ownerUserID: "user-1",
            confirmedAt: Date(timeIntervalSince1970: 500)
        )
        try store.saveSession(makeSession())
        try store.saveDeletionAttempt(attempt)

        try store.deleteSession()
        try store.deleteKnownAccount()

        XCTAssertEqual(try store.loadDeletionAttempt(), attempt)
    }

    // MARK: Attributes

    /// `WhenUnlockedThisDeviceOnly` is the whole privacy argument: not in iCloud
    /// Keychain, not in an encrypted backup, not readable while locked.
    func testStoredItemIsDeviceOnlyAndNotSynchronizing() throws {
        try store.saveSession(makeSession())

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainCredentialStore.Service.session + store.serviceSuffix,
            kSecAttrAccount as String: "current",
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        query[kSecReturnData as String] = false

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        XCTAssertEqual(status, errSecSuccess)

        let attributes = try XCTUnwrap(item as? [String: Any])
        XCTAssertEqual(
            attributes[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        )
        // Absent or false; never true.
        XCTAssertNotEqual(attributes[kSecAttrSynchronizable as String] as? Bool, true)
    }

    // MARK: Decoding failures

    /// Bytes that are not a session read as a malformed record, never as a
    /// partially-usable one.
    func testUndecodableItemIsReportedAsMalformed() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainCredentialStore.Service.session + store.serviceSuffix,
            kSecAttrAccount as String: "current",
            kSecValueData as String: Data("not a session".utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        XCTAssertEqual(SecItemAdd(query as CFDictionary, nil), errSecSuccess)

        XCTAssertThrowsError(try store.loadSession()) { error in
            XCTAssertEqual(error as? CredentialStoreError, .malformedRecord)
        }
    }
}

// MARK: - Record validation

nonisolated final class AuthSessionValidationTests: XCTestCase {

    private func makeSession(
        userId: String = "user-1",
        appleUserIdentifier: String = "apple-sub-1",
        accessToken: String = "access-1",
        accessExpiry: TimeInterval = 2_000,
        refreshToken: String = "refresh-1",
        refreshExpiry: TimeInterval = 100_000
    ) -> AuthSession {
        AuthSession(
            userId: userId,
            appleUserIdentifier: appleUserIdentifier,
            accessToken: accessToken,
            accessTokenExpiresAt: Date(timeIntervalSince1970: accessExpiry),
            refreshToken: refreshToken,
            refreshTokenExpiresAt: Date(timeIntervalSince1970: refreshExpiry),
            onboardingStatus: .required
        )
    }

    func testCompleteSessionIsValid() {
        XCTAssertTrue(makeSession().isValid)
    }

    func testEmptyIdentifiersAndTokensAreRejected() {
        XCTAssertFalse(makeSession(userId: "").isValid)
        XCTAssertFalse(makeSession(appleUserIdentifier: "").isValid)
        XCTAssertFalse(makeSession(accessToken: "").isValid)
        XCTAssertFalse(makeSession(refreshToken: "").isValid)
    }

    /// A refresh credential that dies first describes a session that cannot
    /// renew itself even once.
    func testRefreshExpiringBeforeAccessIsRejected() {
        XCTAssertFalse(makeSession(accessExpiry: 5_000, refreshExpiry: 1_000).isValid)
    }

    func testAccessTokenIsSpentBeforeItsStatedExpiry() {
        let session = makeSession(accessExpiry: 1_000)
        XCTAssertTrue(session.isAccessTokenUsable(at: Date(timeIntervalSince1970: 900)))
        // Inside the margin: still nominally valid, already treated as spent.
        XCTAssertFalse(session.isAccessTokenUsable(at: Date(timeIntervalSince1970: 960)))
    }

    func testRotatingKeepsIdentityAndStatus() {
        let rotated = makeSession().rotating(
            accessToken: "access-2",
            accessTokenExpiresAt: Date(timeIntervalSince1970: 9_000),
            refreshToken: "refresh-2",
            refreshTokenExpiresAt: Date(timeIntervalSince1970: 900_000)
        )
        XCTAssertEqual(rotated.userId, "user-1")
        XCTAssertEqual(rotated.appleUserIdentifier, "apple-sub-1")
        XCTAssertEqual(rotated.accessToken, "access-2")
        XCTAssertEqual(rotated.refreshToken, "refresh-2")
        XCTAssertEqual(rotated.onboardingStatus, .required)
    }

    func testCommittingCompleteStatusKeepsCredentials() {
        let completed = makeSession().with(onboardingStatus: .complete)
        XCTAssertEqual(completed.onboardingStatus, .complete)
        XCTAssertEqual(completed.accessToken, "access-1")
    }
}

// MARK: - Status decoding

nonisolated final class OnboardingServerStatusTests: XCTestCase {

    private struct Wrapper: Decodable { let status: OnboardingServerStatus }

    func testKnownValuesDecode() throws {
        let decoder = JSONDecoder()
        XCTAssertEqual(
            try decoder.decode(Wrapper.self, from: Data(#"{"status":"required"}"#.utf8)).status,
            .required
        )
        XCTAssertEqual(
            try decoder.decode(Wrapper.self, from: Data(#"{"status":"complete"}"#.utf8)).status,
            .complete
        )
    }

    /// An unknown status must fail the whole response rather than default to
    /// anything — least of all to `complete`, which opens the app.
    func testUnknownValueFailsDecoding() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(Wrapper.self, from: Data(#"{"status":"pending"}"#.utf8))
        )
    }
}
