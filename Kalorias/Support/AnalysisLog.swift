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
//  THE SIGNATURES ACCEPT NO USER CONTENT. The photo, image bytes, food names,
//  calorie values, food count and server prose are not redacted values here;
//  they are absent and cannot be passed by a call site.
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
    static func success(outcome: String, duration: TimeInterval, requestId: String?) {
        logger.info(
            """
            analyze ok outcome=\(outcome, privacy: .public) \
            duration=\(String(format: "%.2f", duration), privacy: .public)s \
            requestId=\(requestId ?? "none", privacy: .public)
            """
        )
    }

    /// A failed analysis. Only operational categories are accepted; server
    /// prose can never quote user content into the device log.
    static func failure(
        outcome: String,
        duration: TimeInterval,
        status: Int?,
        requestId: String?
    ) {
        logger.error(
            """
            analyze failed outcome=\(outcome, privacy: .public) \
            duration=\(String(format: "%.2f", duration), privacy: .public)s \
            status=\(status.map(String.init) ?? "none", privacy: .public) \
            requestId=\(requestId ?? "none", privacy: .public)
            """
        )
    }
}
