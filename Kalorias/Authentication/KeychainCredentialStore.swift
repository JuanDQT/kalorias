//
//  KeychainCredentialStore.swift
//  Kalorias
//
//  The only place a Kalorias credential is written down (feature 010, FR-026).
//
//  NOT `UserDefaults`, NOT A FILE, NOT A LOG. A bearer token in preferences is a
//  bearer token in an unencrypted plist that any backup copies verbatim. The
//  constitution's privacy clause and FR-026 both say Keychain, and this type is
//  what makes "only Keychain" enforceable rather than aspirational — nothing
//  else in the app touches `SecItem`.
//
//  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, BOTH HALVES DELIBERATE.
//  `WhenUnlocked` because the app has no background work that needs a token
//  while the phone is locked, so there is no reason for one to be readable then.
//  `ThisDeviceOnly` because it keeps the item out of iCloud Keychain and out of
//  encrypted backups: a session restored onto a second device is a session the
//  server never issued to it, and a token in a backup outlives every revocation.
//
//  THREE RECORDS, THREE LIFETIMES. The session dies with the session. The known
//  account outlives it, so an expired token sends a finished user to Apple
//  rather than back through the questionnaire. The deletion attempt outlives
//  both, because it has to survive the very thing it is deleting.
//
//  UPDATE, NOT ADD-AGAIN. `SecItemAdd` over an existing item returns
//  `errSecDuplicateItem` and changes nothing, which reads at the call site as a
//  successful save of a value that was never stored — the classic Keychain bug.
//  Every write here adds or updates.
//

import Foundation
import Security

/// The credential storage boundary, so the journey store and the session actor
/// can be tested against an in-memory stand-in (Principle II, V).
/// Every requirement is `nonisolated` (the project defaults to MainActor
/// isolation): the session actor reads these from its own executor, and a
/// Keychain call hopping to the main actor would be a hitch on every request.
protocol CredentialStoring: Sendable {
    nonisolated func loadSession() throws -> AuthSession?
    nonisolated func saveSession(_ session: AuthSession) throws
    nonisolated func deleteSession() throws

    nonisolated func loadKnownAccount() throws -> KnownAccount?
    nonisolated func saveKnownAccount(_ account: KnownAccount) throws
    nonisolated func deleteKnownAccount() throws

    nonisolated func loadDeletionAttempt() throws -> AccountDeletionAttempt?
    nonisolated func saveDeletionAttempt(_ attempt: AccountDeletionAttempt) throws
    nonisolated func deleteDeletionAttempt() throws
}

nonisolated enum CredentialStoreError: Error, Equatable {
    /// The Keychain refused the operation. The status is kept for diagnostics
    /// and is a number, not a credential.
    case keychain(OSStatus)
    /// An item was found but does not decode — a record from an incompatible
    /// build, or damaged. Treated as "no credential", never as a partial one.
    case malformedRecord
}

nonisolated struct KeychainCredentialStore: CredentialStoring {

    /// One service per record type, so the three lifetimes cannot collide and a
    /// session delete cannot take the known-account marker with it.
    enum Service {
        static let session = "com.quispe.kalorias.auth.session"
        static let knownAccount = "com.quispe.kalorias.auth.knownAccount"
        static let deletionAttempt = "com.quispe.kalorias.auth.deletionAttempt"
    }

    /// A single account name per service: this app stores one of each.
    private static let account = "current"

    let accessGroup: String?
    /// Appended to each service name. Empty in the app; tests pass a unique
    /// value so a run cannot read or clobber the real device's records.
    let serviceSuffix: String

    init(accessGroup: String? = nil, serviceSuffix: String = "") {
        self.accessGroup = accessGroup
        self.serviceSuffix = serviceSuffix
    }

    // MARK: Session

    func loadSession() throws -> AuthSession? { try load(AuthSession.self, service: Service.session) }

    func saveSession(_ session: AuthSession) throws {
        try save(session, service: Service.session)
    }

    func deleteSession() throws { try delete(service: Service.session) }

    // MARK: Known account

    func loadKnownAccount() throws -> KnownAccount? {
        try load(KnownAccount.self, service: Service.knownAccount)
    }

    func saveKnownAccount(_ account: KnownAccount) throws {
        try save(account, service: Service.knownAccount)
    }

    func deleteKnownAccount() throws { try delete(service: Service.knownAccount) }

    // MARK: Deletion attempt

    func loadDeletionAttempt() throws -> AccountDeletionAttempt? {
        try load(AccountDeletionAttempt.self, service: Service.deletionAttempt)
    }

    func saveDeletionAttempt(_ attempt: AccountDeletionAttempt) throws {
        try save(attempt, service: Service.deletionAttempt)
    }

    func deleteDeletionAttempt() throws { try delete(service: Service.deletionAttempt) }

    // MARK: SecItem

    private func baseQuery(service: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service + serviceSuffix,
            kSecAttrAccount as String: Self.account,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private func load<Value: Decodable>(_ type: Value.Type, service: String) throws -> Value? {
        var query = baseQuery(service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw CredentialStoreError.malformedRecord }
            guard let value = try? Self.decoder.decode(Value.self, from: data) else {
                throw CredentialStoreError.malformedRecord
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw CredentialStoreError.keychain(status)
        }
    }

    private func save(_ value: some Encodable, service: String) throws {
        guard let data = try? Self.encoder.encode(value) else {
            throw CredentialStoreError.malformedRecord
        }

        let query = baseQuery(service: service)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw CredentialStoreError.keychain(updateStatus)
        }

        var insert = query
        insert.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw CredentialStoreError.keychain(addStatus) }
    }

    /// Deleting what is not there is success. Cleanup after a confirmed account
    /// deletion has to be safe to run twice, because it can be interrupted.
    private func delete(service: String) throws {
        let status = SecItemDelete(baseQuery(service: service) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status)
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
