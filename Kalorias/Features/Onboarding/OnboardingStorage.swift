//
//  OnboardingStorage.swift
//  Kalorias
//
//  Everything the onboarding keeps on disk, split by what it is worth to an
//  attacker: the questionnaire the server sent, and the answers the user gave.
//
//  THERE ARE THREE SOURCES FOR THE QUESTIONNAIRE, in this order: the server, the
//  last good response cached here, and the copy inside the app bundle. The
//  bundled copy is not belt-and-braces — without it, a first launch with no
//  signal cannot even begin, and "install the app on the train home" is a
//  perfectly ordinary thing to do.
//
//  THE CACHE IS PUBLIC CONTENT AND STAYS THAT WAY. It is the same questionnaire
//  every user downloads; encrypting it would only mean a locked phone cannot
//  open the chat. The draft is the opposite — it holds a date of birth, a
//  weight, and whatever the user typed about their health — so feature 010 moved
//  it, and the sealed pending submission, into `ProtectedFileStore`: a separate
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

    /// Where the cached questionnaire lives. Application Support rather than
    /// Caches: content the system may delete to reclaim space is not a fallback.
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
    let bundle: Bundle

    init(
        directory: URL = OnboardingStorage.defaultDirectory(),
        protectedDirectory: URL? = nil,
        bundle: Bundle = .main
    ) {
        self.directory = directory
        self.protected = ProtectedFileStore(
            directory: protectedDirectory
                ?? directory.appending(path: "Protected", directoryHint: .isDirectory)
        )
        self.bundle = bundle
    }

    private var cachedQuestionnaireURL: URL { directory.appending(path: "questionnaire.json") }

    // MARK: Questionnaire (public content)

    /// Keep the raw bytes, not the decoded value: a future build with a wider
    /// decoder can read a payload this one only partly understood.
    func cacheQuestionnaire(_ data: Data) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: cachedQuestionnaireURL, options: .atomic)
    }

    func cachedQuestionnaire() -> Questionnaire? {
        guard let data = try? Data(contentsOf: cachedQuestionnaireURL) else { return nil }
        return Self.decode(data)
    }

    /// The copy shipped in the app, for the language given.
    ///
    /// Falls back to Spanish, not to nothing: half a questionnaire in the wrong
    /// language still gets the user a plan, and an empty screen does not.
    func bundledQuestionnaire(languageCode: String) -> Questionnaire? {
        let candidates = [languageCode, "es"]
        for code in candidates {
            guard let url = bundle.url(forResource: "onboarding.\(code)", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let questionnaire = Self.decode(data)
            else { continue }
            return questionnaire
        }
        return nil
    }

    private static func decode(_ data: Data) -> Questionnaire? {
        guard let questionnaire = try? JSONDecoder().decode(QuestionnaireEnvelope.self, from: data).data
        else { return nil }
        // A cached or bundled payload gets the same version gate as a fresh
        // one. A cache written by a newer build is exactly the case this
        // catches.
        guard questionnaire.schemaVersion <= Questionnaire.supportedSchemaVersion else { return nil }
        return questionnaire
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
