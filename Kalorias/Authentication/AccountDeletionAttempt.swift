//
//  AccountDeletionAttempt.swift
//  Kalorias
//
//  A deletion the user has confirmed, written down before it is attempted
//  (feature 010, FR-040a).
//
//  IT IS PERSISTED *BEFORE* THE FIRST REQUEST, not after a response. The
//  dangerous window is: the server deletes the account, the response is lost,
//  the app is killed. Without this record the next launch finds a valid-looking
//  session for an account that no longer exists and shows the user their data as
//  if nothing happened. With it, bootstrap knows a deletion is outstanding and
//  goes straight to the recovery gate.
//
//  IT KEEPS THE EXACT BEARER, WHICH LOOKS WRONG AND IS NOT. Ordinary refresh is
//  impossible once the server has deleted the session family, so a retry with a
//  fresh token cannot authenticate. The backend keeps a short-lived tombstone
//  keyed by an HMAC of this exact token and operation id; presenting them
//  replays the completed deletion and nothing else. It grants no other route and
//  can resurrect no data — and it never leaves the device-only Keychain.
//
//  ONE OPERATION ID FOR EVERY RETRY. A second key would be a second deletion
//  request against an account that may already be gone.
//
//  It is removed only after a `204` **and** the local cleanup that follows. Any
//  other result keeps it, so the user can retry or ask for support.
//

import Foundation

nonisolated struct AccountDeletionAttempt: Codable, Equatable, Sendable {

    let schemaVersion: Int
    /// The stable `Idempotency-Key` presented on the first request and on every
    /// replay of it.
    let operationId: UUID
    /// The exact Bearer the first request carried. A credential: never logged,
    /// never printed, never sent anywhere but `DELETE /api/v1/account`.
    let presentedAccessToken: String
    /// Whose local meals and images the confirmed deletion may remove. Captured
    /// now because the session it came from is about to stop existing.
    let ownerUserID: String
    /// When the user tapped through the destructive confirmation.
    let confirmedAt: Date

    static let currentSchemaVersion = 1

    init(
        schemaVersion: Int = AccountDeletionAttempt.currentSchemaVersion,
        operationId: UUID,
        presentedAccessToken: String,
        ownerUserID: String,
        confirmedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.operationId = operationId
        self.presentedAccessToken = presentedAccessToken
        self.ownerUserID = ownerUserID
        self.confirmedAt = confirmedAt
    }

    var isValid: Bool { !presentedAccessToken.isEmpty && !ownerUserID.isEmpty }
}

/// Printing this value must never print the token it carries. Both descriptions
/// are overridden, not one: `print` reaches for `description` and the debugger
/// and string interpolation of `Any` reach for `debugDescription`, so leaving
/// either synthesised leaves a way for the Bearer to reach a log (FR-037).
nonisolated extension AccountDeletionAttempt: CustomStringConvertible, CustomDebugStringConvertible {
    var description: String { "AccountDeletionAttempt(operationId: \(operationId))" }
    var debugDescription: String { description }
}
