//
//  BackendEnvironmentAuditTests.swift
//  KaloriasTests
//
//  Guards the constitution's Backend Environments clause: "This is auditable by
//  grep, and that is the point: a review MUST be able to confirm zero
//  `URL(string: "http...")` and zero base-URL literals outside
//  `BackendEnvironment`."
//
//  DOING IT HERE RATHER THAN IN REVIEW IS THE POINT. The debt this feature pays
//  off — a provider host hardcoded in a service — survived review after review
//  precisely because the audit was run by hand and from memory. A check that
//  only runs when someone remembers to run it does not close that.
//  `PaletteContrastTests` makes the same move for Principle III's contrast rule.
//

import XCTest
@testable import Kalorias

nonisolated final class BackendEnvironmentAuditTests: XCTestCase {

    /// The app target's sources. The test target is deliberately out of scope:
    /// the suites here pin addresses as literals on purpose, and a literal in a
    /// bundle that never ships is not the risk this rule addresses.
    private static let appSourceRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()   // KaloriasTests/
        .deletingLastPathComponent()   // repository root
        .appending(path: "Kalorias")

    /// The one file permitted to hold a base-URL literal.
    private static let environmentFileName = "BackendEnvironment.swift"

    /// Any double-quoted literal carrying a scheme separator. Catches
    /// `URL(string: "https://…")` and a bare `let host = "https://…"` alike,
    /// which is the point — the second is the sneakier of the two.
    /// Computed rather than stored: `Regex` is not `Sendable`, so a static
    /// constant would not compile under strict concurrency.
    private static var schemeBearingLiteral: Regex<Substring> { #/"[^"\n]*://[^"\n]*"/# }

    func testNoBaseURLLiteralExistsOutsideTheEnvironment() throws {
        let violations = try Self.violations()

        XCTAssertTrue(
            violations.isEmpty,
            """
            Base-URL literal(s) found outside \(Self.environmentFileName). Every \
            address must come from BackendEnvironment; call sites append a path \
            to it.

            \(violations.joined(separator: "\n"))
            """
        )
    }

    /// Without this, a broken `#filePath` would make the audit above pass while
    /// checking nothing at all — the most expensive kind of green test.
    func testTheAuditActuallyReachesTheAppSources() throws {
        let files = try Self.appSourceFiles()

        XCTAssertGreaterThan(
            files.count, 10,
            "expected the app's Swift sources at \(Self.appSourceRoot.path(percentEncoded: false))"
        )
        XCTAssertTrue(
            files.contains { $0.lastPathComponent == Self.environmentFileName },
            "the one file the audit exempts must itself be among the files it walked"
        )
    }

    /// And that the matcher still matches — an audit whose regex silently
    /// stopped working looks identical to a clean codebase.
    func testTheMatcherStillRecognisesAViolation() {
        let sample = #"let endpoint = "https://api.example.com/v1/analyze""#
        XCTAssertNotNil(sample.firstMatch(of: Self.schemeBearingLiteral))
        XCTAssertNil(#"let path = "/api/v1/kalorias/analyzeMeal""#.firstMatch(of: Self.schemeBearingLiteral))
    }

    // MARK: - Implementation

    private static func appSourceFiles() throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: appSourceRoot,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
    }

    private static func violations() throws -> [String] {
        var found: [String] = []

        for file in try appSourceFiles() where file.lastPathComponent != environmentFileName {
            let contents = try String(contentsOf: file, encoding: .utf8)

            for (offset, line) in contents.components(separatedBy: .newlines).enumerated() {
                guard !isComment(line) else { continue }
                guard line.firstMatch(of: schemeBearingLiteral) != nil else { continue }

                let relativePath = file.path(percentEncoded: false).replacingOccurrences(
                    of: appSourceRoot.deletingLastPathComponent().path(percentEncoded: false),
                    with: ""
                )
                found.append("\(relativePath):\(offset + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }

        return found
    }

    /// A URL cited in a doc comment is documentation, not configuration. The
    /// rule governs what the app *calls*, and a comment calls nothing.
    private static func isComment(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*")
    }
}
