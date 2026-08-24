//
//  AnalysisLog.swift
//  Kalorias
//
//  What a reported problem leaves behind. One `os.Logger`, category `analysis`,
//  so a user's "it said the service had a problem" can be matched to the entry
//  in the server's own log that says why.
//
//  THE REQUEST ID IS INTERPOLATED `privacy: .public`, DELIBERATELY. `os.Logger`
//  redacts interpolated values by default in release builds, and an id that
//  reads `<private>` when you finally have the device in your hand is a log
//  entry that cost effort and answers nothing. The id is server-generated and
//  identifies nothing about the user, so making it public is correct — and it is
//  the only thing that can identify a `503`.
//
//  EVERYTHING ELSE STAYS DEFAULT-REDACTED, which is what keeps FR-026 true. The
//  photo, the image bytes and the food names are never logged at all: not
//  redacted, not passed in, absent.
//
//  NOTHING HERE REACHES THE UI (FR-027). There is no crash reporter, no
//  analytics, no on-screen id and no persisted log file — the system log is the
//  whole mechanism.
//

import Foundation
import os

nonisolated enum AnalysisLog {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.quispe.kalorias.Kalorias",
        category: "analysis"
    )

    /// A finished analysis that produced foods or a no-food answer.
    static func success(outcome: String, duration: TimeInterval, foodCount: Int, requestId: String?) {
        logger.info(
            """
            analyze ok outcome=\(outcome, privacy: .public) \
            duration=\(String(format: "%.2f", duration), privacy: .public)s \
            foods=\(foodCount, privacy: .public) \
            requestId=\(requestId ?? "none", privacy: .public)
            """
        )
    }

    /// A failed analysis. `serverMessage` carries the server's own text for a
    /// rejected photo — the one place that text goes, since the app shows its
    /// own localized copy instead (FR-021a).
    static func failure(
        outcome: String,
        duration: TimeInterval,
        status: Int?,
        requestId: String?,
        serverMessage: String? = nil
    ) {
        logger.error(
            """
            analyze failed outcome=\(outcome, privacy: .public) \
            duration=\(String(format: "%.2f", duration), privacy: .public)s \
            status=\(status.map(String.init) ?? "none", privacy: .public) \
            requestId=\(requestId ?? "none", privacy: .public) \
            serverMessage=\(serverMessage ?? "none")
            """
        )
    }
}
