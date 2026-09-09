//
//  PendingOnboarding.swift
//  Kalorias
//
//  The finished onboarding, sealed on the device and waiting for an account
//  (feature 010, FR-005).
//
//  SEALED MEANS SEALED. The draft goes on changing while the user answers; this
//  does not. It is written once, atomically, *before* the access screen appears
//  — so a crash in that instant can never leave the app asking for a sign-in
//  with nothing behind it (spec, "Final-answer crash window").
//
//  THE CONSENT IS A SEPARATE FIELD, ADDED LATER, and `nil` is a hard gate: with
//  no receipt there is no upload, no matter how valid the session is. Modelling
//  it as an optional on the sealed payload rather than as a flag somewhere else
//  means the permission and the data it covers cannot be separated by a crash.
//
//  REVIEWING ANSWERS RESEALS; IT DOES NOT PATCH. Going back before the account
//  is committed produces a whole replacement snapshot under the *same*
//  `sessionId`, because that identifier is the idempotency key and a second key
//  is a second plan. Once an authenticated attempt has begun, the snapshot is
//  frozen (FR-007).
//
//  IT IS DELETED ONLY AFTER `complete` IS DURABLE. Removing it first and then
//  crashing loses answers the server may never have received; the other order
//  merely leaves a redundant file that bootstrap discards.
//

import Foundation

nonisolated struct PendingOnboarding: Codable, Equatable, Sendable {

    /// Migration version for the local envelope, independent of the
    /// questionnaire's own `schemaVersion` inside the submission.
    let schemaVersion: Int
    /// The complete, validated payload, exactly as it will go over the wire.
    let submission: OnboardingSubmission
    /// `nil` until the user accepts the separate health-data notice. While it is
    /// `nil`, no upload is permitted.
    let consent: ConsentReceipt?

    static let currentSchemaVersion = 1

    init(
        schemaVersion: Int = PendingOnboarding.currentSchemaVersion,
        submission: OnboardingSubmission,
        consent: ConsentReceipt? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.submission = submission
        self.consent = consent
    }

    /// Why a finished flow could not be sealed.
    enum SealError: Error, Equatable {
        /// A required question has no answer. Sealing an incomplete payload
        /// would send the server a plan request it cannot satisfy, and would do
        /// it under an idempotency key that then cannot be reused.
        case incomplete
    }

    /// Seal a completed flow into an immutable snapshot.
    ///
    /// `completedAt` is the moment the last required answer was accepted, not
    /// the moment it is eventually sent (FR-006). Those can be days apart if the
    /// user closes the app at the access screen, and the plan is built from when
    /// they answered.
    static func seal(
        flow: QuestionnaireFlow,
        sessionId: UUID,
        startedAt: Date,
        completedAt: Date
    ) throws -> PendingOnboarding {
        guard flow.isComplete else { throw SealError.incomplete }

        return PendingOnboarding(
            submission: OnboardingSubmission(
                sessionId: sessionId,
                onboardingId: flow.questionnaire.onboardingId,
                schemaVersion: flow.questionnaire.schemaVersion,
                contentVersion: flow.questionnaire.contentVersion,
                locale: flow.questionnaire.locale,
                startedAt: startedAt,
                completedAt: completedAt,
                answers: flow.submissionEntries()
            )
        )
    }

    /// The same sealed payload carrying the user's acceptance.
    ///
    /// Note it takes a receipt rather than making one: the receipt is minted by
    /// the affirmative tap, and nothing in the storage layer may invent one.
    func granting(_ receipt: ConsentReceipt) -> PendingOnboarding {
        PendingOnboarding(schemaVersion: schemaVersion, submission: submission, consent: receipt)
    }

    /// The idempotency key for every attempt at this payload, first and last.
    var idempotencyKey: UUID { submission.sessionId }

    /// Whether this payload may be sent: it has a receipt, and that receipt
    /// still names the copy this build shows.
    var isReadyToUpload: Bool { consent?.matchesCurrentVersions == true }
}
