//
//  PendingOnboardingStorage.swift
//  Kalorias
//
//  Where the sealed onboarding waits for an account (feature 010, FR-005).
//
//  A SEPARATE FILE FROM THE DRAFT, ON PURPOSE. The draft is what "Review
//  answers" reopens on the access screen; the sealed payload is what gets sent.
//  Keeping them apart is what lets the user go back and edit without touching
//  the snapshot an upload may already be retrying, and what lets the two be
//  cleaned up on different schedules after a confirmed submission.
//
//  THE WRITE IS THE TRANSITION. `OnboardingStore` shows the access screen only
//  after this write returns, so the crash window between "the user answered the
//  last question" and "there is something to sign in for" does not exist.
//
//  CONSENT IS ADDED IN PLACE, BEFORE ANY NETWORK WORK. `grantConsent` rewrites
//  the whole envelope with the receipt attached and must succeed before the
//  first upload is attempted — otherwise a crash mid-request would leave data on
//  the server with no local record of the permission that allowed it.
//
//  CLEARING IS IDEMPOTENT AND LAST. It runs only after `complete` is durable in
//  the Keychain, and running it twice is success, so an interrupted cleanup
//  resumes without special handling.
//

import Foundation

nonisolated struct PendingOnboardingStorage: Sendable {

    typealias StorageError = ProtectedFileStore.StoreError

    static let fileName = "pending-onboarding.json"

    let protected: ProtectedFileStore

    init(protected: ProtectedFileStore) {
        self.protected = protected
    }

    init(directory: URL = OnboardingStorage.defaultProtectedDirectory()) {
        self.init(protected: ProtectedFileStore(directory: directory))
    }

    /// The protection class the payload is written with, so a test can assert
    /// it on a simulator that does not preserve the on-disk attribute.
    var protection: FileProtectionType { protected.protection }

    /// The sealed payload, or `nil` when there genuinely is none.
    ///
    /// Throws `.unavailableWhileLocked` on a locked device and `.corrupted` on
    /// undecodable bytes; neither is reported as absence, because bootstrap
    /// would then send a user who already answered back to question one.
    func load() async throws -> PendingOnboarding? {
        try await protected.read(PendingOnboarding.self, from: Self.fileName)
    }

    /// Write the sealed payload. The caller must not advance until this returns.
    func save(_ pending: PendingOnboarding) async throws {
        try await protected.write(pending, to: Self.fileName)
    }

    /// Attach the user's acceptance to the stored payload and persist it.
    ///
    /// Returns the updated value so the caller uses exactly what is on disk
    /// rather than its own copy of it.
    @discardableResult
    func grantConsent(_ receipt: ConsentReceipt) async throws -> PendingOnboarding {
        // Nothing sealed is a programming error, not a storage one: consent can
        // only be reached from a phase that requires a payload.
        guard let pending = try await load() else { throw StorageError.corrupted }
        let consented = pending.granting(receipt)
        try await save(consented)
        return consented
    }

    /// Remove the payload. Safe to call when there is nothing to remove.
    func clear() async {
        await protected.delete(Self.fileName)
    }
}
