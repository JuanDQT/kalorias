//
//  OnboardingStorage.swift
//  Kalorias
//
//  Stores the user's answers, never a questionnaire. The draft holds health
//  data, so feature 010 moved it and the sealed pending submission into
//  `ProtectedFileStore`: a separate
//  subdirectory, written atomically with complete file protection (FR-036).
//
//  THE DRAFT IS WRITTEN AFTER EVERY ANSWER, not at the end, and the next
//  question waits for that write. An onboarding is two minutes of typing that a
//  phone call can interrupt, and starting again from question one is the point
//  at which people stop. Saving after the fact would make the last answer the
//  one always at risk.
//
//  A DRAFT IS PINNED TO ITS `contentVersion`. If the server has moved on while
//  the user was away, the draft is dropped rather than replayed against
//  questions that may have changed underneath it. Losing two minutes of answers
//  is recoverable; a plan built from answers to questions nobody asked is not.
//
//  THE SHADOW STORE IS SAVED BUT NEVER SUBMITTED. It exists so that toggling a
//  gate back and forth does not lose what was typed behind it, and it survives a
//  relaunch for the same reason.
//
//  "COULD NOT READ" IS NOT "NOT THERE". A protected draft is unreadable while
//  the device is locked, and the error travels up rather than being flattened to
//  `nil` — a caller that reads a locked file as "no draft" restarts the
//  onboarding from question one.
//

import Foundation

// MARK: - Draft

/// A half-finished onboarding, as written to disk.
nonisolated struct OnboardingDraft: Codable, Equatable, Sendable {
    /// Migration version for this envelope. Absent in drafts written before
    /// feature 010, which decode as version 0 and are still perfectly usable.
    var schemaVersion: Int = OnboardingDraft.currentSchemaVersion
    let sessionId: UUID
    let onboardingId: String
    /// The version the draft was started against. A mismatch discards it.
    let contentVersion: Int
    /// The questionnaire language the answers were given in.
    var locale: String = ""
    let startedAt: Date
    /// Last durable change, for diagnostics and recovery ordering.
    var updatedAt: Date = .distantPast
    let answers: [String: OnboardingAnswer]
    let shadowed: [String: OnboardingAnswer]

    static let currentSchemaVersion = 1

    init(
        schemaVersion: Int = OnboardingDraft.currentSchemaVersion,
        sessionId: UUID,
        onboardingId: String,
        contentVersion: Int,
        locale: String = "",
        startedAt: Date,
        updatedAt: Date = .distantPast,
        answers: [String: OnboardingAnswer],
        shadowed: [String: OnboardingAnswer]
    ) {
        self.schemaVersion = schemaVersion
        self.sessionId = sessionId
        self.onboardingId = onboardingId
        self.contentVersion = contentVersion
        self.locale = locale
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.answers = answers
        self.shadowed = shadowed
    }
}

// MARK: - Storage

nonisolated struct OnboardingStorage: Sendable {

    /// Why a draft could not be read or written.
    ///
    /// Deliberately the same vocabulary as `ProtectedFileStore.StoreError`: the
    /// distinction between "locked", "corrupt" and "the write did not land" is
    /// the whole reason the protected store exists, and flattening it here would
    /// throw it away one layer above where it was made.
    typealias DraftError = ProtectedFileStore.StoreError

    /// Base directory for onboarding's protected answers.
    static func defaultDirectory() -> URL {
        let base = URL.applicationSupportDirectory.appending(path: "Onboarding", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Where the answers live: a subdirectory of the above, so the protection
    /// class applies to the sensitive files and only to them.
    static func defaultProtectedDirectory() -> URL {
        defaultDirectory().appending(path: "Protected", directoryHint: .isDirectory)
    }

    static let draftFileName = "draft.json"

    let directory: URL
    let protected: ProtectedFileStore
    init(
        directory: URL = OnboardingStorage.defaultDirectory(),
        protectedDirectory: URL? = nil
    ) {
        self.directory = directory
        self.protected = ProtectedFileStore(
            directory: protectedDirectory
                ?? directory.appending(path: "Protected", directoryHint: .isDirectory)
        )
        // Previous versions kept public questionnaire bytes here. Retire that
        // fallback on upgrade; the protected answer draft is left untouched.
        try? FileManager.default.removeItem(at: directory.appending(path: "questionnaire.json"))
    }

    // MARK: Draft (health data)

    /// Write the draft, protected and atomically.
    ///
    /// Throwing rather than silently succeeding is the point: the caller must
    /// not show the next question until this has landed (FR-002), and it cannot
    /// know that if the failure is swallowed here.
    func save(_ draft: OnboardingDraft) async throws {
        try await protected.write(draft, to: Self.draftFileName)
    }

    /// The saved draft, but only if it still belongs to `questionnaire`.
    ///
    /// A version mismatch returns `nil` — that draft is deliberately abandoned.
    /// A locked device or corrupt file throws, so the caller can wait or report
    /// instead of concluding there is nothing saved.
    func draft(matching questionnaire: Questionnaire) async throws -> OnboardingDraft? {
        guard let draft = try await protected.read(OnboardingDraft.self, from: Self.draftFileName)
        else { return nil }
        guard draft.onboardingId == questionnaire.onboardingId,
              draft.contentVersion == questionnaire.contentVersion
        else { return nil }
        return draft
    }

    /// The saved draft whatever questionnaire it belongs to. Bootstrap uses this
    /// to answer "is an onboarding in progress?" before any questionnaire has
    /// been loaded.
    func draft() async throws -> OnboardingDraft? {
        try await protected.read(OnboardingDraft.self, from: Self.draftFileName)
    }

    func clearDraft() async {
        await protected.delete(Self.draftFileName)
    }
}
