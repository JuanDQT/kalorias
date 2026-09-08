//
//  OnboardingStorage.swift
//  Kalorias
//
//  Everything the onboarding keeps on disk: the last questionnaire the server
//  sent, and the answers given so far.
//
//  THERE ARE THREE SOURCES FOR THE QUESTIONNAIRE, in this order: the server, the
//  last good response cached here, and the copy inside the app bundle. The
//  bundled copy is not belt-and-braces — without it, a first launch with no
//  signal cannot even begin, and "install the app on the train home" is a
//  perfectly ordinary thing to do.
//
//  THE DRAFT IS WRITTEN AFTER EVERY ANSWER, not at the end. An onboarding is
//  two minutes of typing that a phone call can interrupt, and starting again
//  from question one is the point at which people stop.
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

import Foundation

// MARK: - Draft

/// A half-finished onboarding, as written to disk.
nonisolated struct OnboardingDraft: Codable, Equatable, Sendable {
    let sessionId: UUID
    let onboardingId: String
    /// The version the draft was started against. A mismatch discards it.
    let contentVersion: Int
    let startedAt: Date
    let answers: [String: OnboardingAnswer]
    let shadowed: [String: OnboardingAnswer]
}

// MARK: - Storage

nonisolated struct OnboardingStorage: Sendable {

    /// Where the cached questionnaire and the draft live. Application Support
    /// rather than Caches: a draft the system may delete at any moment to
    /// reclaim space is not a draft.
    static func defaultDirectory() -> URL {
        let base = URL.applicationSupportDirectory.appending(path: "Onboarding", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    let directory: URL
    let bundle: Bundle

    init(directory: URL = OnboardingStorage.defaultDirectory(), bundle: Bundle = .main) {
        self.directory = directory
        self.bundle = bundle
    }

    private var cachedQuestionnaireURL: URL { directory.appending(path: "questionnaire.json") }
    private var draftURL: URL { directory.appending(path: "draft.json") }

    // MARK: Questionnaire

    /// Keep the raw bytes, not the decoded value: a future build with a wider
    /// decoder can read a payload this one only partly understood.
    func cacheQuestionnaire(_ data: Data) {
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

    // MARK: Draft

    func save(_ draft: OnboardingDraft) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        try? data.write(to: draftURL, options: .atomic)
    }

    /// The saved draft, but only if it still belongs to `questionnaire`.
    func draft(matching questionnaire: Questionnaire) -> OnboardingDraft? {
        guard let data = try? Data(contentsOf: draftURL),
              let draft = try? JSONDecoder().decode(OnboardingDraft.self, from: data),
              draft.onboardingId == questionnaire.onboardingId,
              draft.contentVersion == questionnaire.contentVersion
        else { return nil }
        return draft
    }

    func clearDraft() {
        try? FileManager.default.removeItem(at: draftURL)
    }
}
