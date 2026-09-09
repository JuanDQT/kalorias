//
//  ProtectedFileStore.swift
//  Kalorias
//
//  Reads and writes the files that hold health data: the onboarding draft and
//  the sealed pending submission (feature 010, FR-036).
//
//  ATOMIC AND `.completeFileProtection` TOGETHER, ALWAYS. Atomic alone survives
//  a crash but leaves the bytes readable while the phone is in a stranger's
//  pocket; protection alone can leave half a file behind. The onboarding holds a
//  date of birth, a weight and whatever the user typed about their health, so
//  neither half is optional — and putting both in one place is the only way a
//  future call site cannot forget one.
//
//  "LOCKED" IS NOT "MISSING", and confusing the two is the bug this type exists
//  to prevent. A `.completeFileProtection` file is unreadable while the device
//  is locked; a caller that reads that as "no draft" restarts the onboarding
//  from question one, or — far worse — reads "no session" and offers to create a
//  second account. So the error is distinguished at the boundary and the journey
//  store waits in `restoring` instead of guessing.
//
//  CORRUPTION IS SURFACED, NEVER SWALLOWED. Undecodable bytes are reported as
//  `.corrupted`; the file is not deleted and nothing is sent. Silently dropping
//  a payload that failed to decode is how a user's two minutes of answers
//  disappear without anyone noticing.
//
//  `nonisolated` and `async` so the I/O runs off the main actor: the project
//  builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and a synchronous
//  protected write on the main thread is a hitch on the answer that triggered it.
//

import Foundation

nonisolated struct ProtectedFileStore: Sendable {

    /// Why a protected file could not be read or written.
    enum StoreError: Error, Equatable {
        /// The device is locked and the file's protection class forbids reading.
        /// The caller must wait, not conclude the file is absent.
        case unavailableWhileLocked
        /// The bytes exist but do not decode. The file is left in place.
        case corrupted
        /// The write did not land. The caller must not advance past it.
        case writeFailed
    }

    let directory: URL

    /// The protection class every file here is written with. A stored property
    /// rather than a literal at each write, so "what protection did this get?"
    /// has one answer that a test can read back — the iOS Simulator does not
    /// preserve the on-disk attribute, and asserting only against the file
    /// system would silently test nothing there.
    let protection: FileProtectionType

    init(directory: URL, protection: FileProtectionType = .complete) {
        self.directory = directory
        self.protection = protection
    }

    /// Application Support, not Caches: the system may evict Caches at any
    /// moment, and a draft the OS can delete to reclaim space is not a draft.
    static func defaultDirectory(named subdirectory: String) -> URL {
        URL.applicationSupportDirectory.appending(path: subdirectory, directoryHint: .isDirectory)
    }

    private func url(for name: String) -> URL {
        directory.appending(path: name)
    }

    // MARK: Writing

    /// Encode and write `value`, atomically and with complete file protection.
    ///
    /// The protection attribute is set twice on purpose: in the write options so
    /// the bytes are never briefly unprotected, and again on the finished file,
    /// because an atomic write replaces the item and a previously-set attribute
    /// does not necessarily survive the swap.
    func write(_ value: some Encodable, to name: String) async throws {
        let data: Data
        do {
            data = try Self.makeEncoder().encode(value)
        } catch {
            throw StoreError.writeFailed
        }

        let destination = url(for: name)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: protection]
            )
            try data.write(to: destination, options: [.atomic, .completeFileProtection])
            try FileManager.default.setAttributes(
                [.protectionKey: protection],
                ofItemAtPath: destination.path
            )
        } catch {
            throw StoreError.writeFailed
        }
    }

    // MARK: Reading

    /// The decoded value, or `nil` when the file genuinely does not exist.
    ///
    /// Throws `.unavailableWhileLocked` rather than returning `nil` when the
    /// file is present but unreadable, and `.corrupted` when it is present and
    /// undecodable.
    func read<Value: Decodable>(_ type: Value.Type, from name: String) async throws -> Value? {
        let data: Data
        do {
            data = try Data(contentsOf: url(for: name))
        } catch let error as NSError {
            if Self.isMissing(error) { return nil }
            // Anything that is not definitively "there is no such file" is
            // reported as unreadable, not as absent. Erring the other way sends
            // a user who already answered back to question one, or offers to
            // create a second account for one that exists.
            throw StoreError.unavailableWhileLocked
        }

        do {
            return try Self.makeDecoder().decode(Value.self, from: data)
        } catch {
            throw StoreError.corrupted
        }
    }

    /// Whether the file exists at all, without decoding it. Reports `false` only
    /// for a genuine absence; a locked device throws instead.
    func exists(_ name: String) async throws -> Bool {
        let path = url(for: name).path
        guard FileManager.default.fileExists(atPath: path) else { return false }
        return true
    }

    // MARK: Deleting

    /// Remove the file. Idempotent: deleting what is not there is success, which
    /// is what makes an interrupted cleanup safe to resume.
    func delete(_ name: String) async {
        try? FileManager.default.removeItem(at: url(for: name))
    }

    // MARK: Error classification

    /// Definitively "there is no such file".
    ///
    /// **Both Cocoa codes are needed.** `NSFileReadNoSuchFileError` (260) is what
    /// a *read* throws and is the one that actually occurs here;
    /// `NSFileNoSuchFileError` (4) comes from `FileManager` operations. Checking
    /// only the latter — an easy mistake, the names differ by one word — makes
    /// every missing file look unreadable, which parks the app in `restoring`
    /// forever on a perfectly ordinary first launch.
    static func isMissing(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain,
           error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError {
            return true
        }
        if error.domain == NSPOSIXErrorDomain, error.code == Int(ENOENT) { return true }
        return false
    }

    /// `NSFileReadNoPermissionError` (257) / `EPERM`: the item exists but data
    /// protection is denying the read, which on iOS means the device is locked.
    static func isLocked(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoPermissionError { return true }
        if error.domain == NSPOSIXErrorDomain, error.code == Int(EPERM) { return true }
        return false
    }

    // MARK: Coding

    /// ISO-8601 dates, matching the wire contract the sealed submission is
    /// eventually encoded into. One strategy across disk and network means a
    /// round trip cannot shift an instant.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
