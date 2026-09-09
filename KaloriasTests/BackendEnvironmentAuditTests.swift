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

    // MARK: - One address, composed in one place (feature 010)

    /// Every file that builds a request must take its address from
    /// `BackendEnvironment`.
    ///
    /// The literal audit above catches a hardcoded host. This catches the other
    /// half of the same mistake: a service that quietly grows a *second* source
    /// of truth for where the backend is — a parameter with no default, an
    /// injected string, a copy of the URL passed down from somewhere else. Four
    /// services now send authenticated traffic, and a fifth pointing somewhere
    /// else would be found in production, not in review.
    func testEveryServiceThatBuildsARequestComposesItFromTheEnvironment() throws {
        var offenders: [String] = []

        for file in try Self.appSourceFiles() {
            let contents = try String(contentsOf: file, encoding: .utf8)
            guard contents.contains("URLRequest(url:") else { continue }
            guard !contents.contains("BackendEnvironment.") else { continue }
            offenders.append(file.lastPathComponent)
        }

        XCTAssertEqual(
            offenders, [],
            "these build requests without composing from the single validated base URL"
        )
    }

    /// Endpoint paths are relative, always. A constant holding a whole URL would
    /// pass the literal audit whenever the scheme sat in another file, and would
    /// point one route at a host the rest of the app never validated.
    func testEveryDeclaredEndpointPathIsRelative() throws {
        let declaration = #/static let \w*[Pp]ath = "([^"]*)"/#
        var offenders: [String] = []

        for file in try Self.appSourceFiles() {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for match in contents.matches(of: declaration) {
                let path = String(match.1)
                if !path.hasPrefix("/") || path.contains("://") {
                    offenders.append("\(file.lastPathComponent): \(path)")
                }
            }
        }

        XCTAssertEqual(offenders, [], "an endpoint path must be appended to the base URL, not replace it")
    }

    // MARK: - The example configuration holds an address and nothing else

    private static var exampleConfigURL: URL {
        appSourceRoot
            .deletingLastPathComponent()
            .appending(path: "Config/Secrets.example.xcconfig")
    }

    /// Every assignment in the example config, as `(key, value)`.
    private static func exampleSettings() throws -> [(key: String, value: String)] {
        let contents = try String(contentsOf: exampleConfigURL, encoding: .utf8)
        return contents.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//"), let separator = trimmed.firstIndex(of: "=") else {
                return nil
            }
            return (
                String(trimmed[trimmed.startIndex..<separator]).trimmingCharacters(in: .whitespaces),
                String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            )
        }
    }

    func testTheAuditActuallyReadsTheExampleConfiguration() throws {
        let settings = try Self.exampleSettings()

        XCTAssertTrue(
            settings.contains { $0.key == "KALORIAS_API_BASE_URL" },
            "expected the example config at \(Self.exampleConfigURL.path(percentEncoded: false))"
        )
    }

    /// The app holds an address. It does not hold a credential, and adding
    /// Apple to the feature is exactly the moment someone reaches for a client
    /// secret or a team key — both of which belong to the backend, which is the
    /// only party that can verify an Apple identity token at all.
    func testTheExampleConfigurationDeclaresNoCredential() throws {
        let forbidden = ["KEY", "SECRET", "TOKEN", "PASSWORD", "CREDENTIAL", "PRIVATE", "TEAM_ID"]
        var offenders: [String] = []

        for setting in try Self.exampleSettings() {
            let name = setting.key.uppercased()
            for term in forbidden where name.contains(term) {
                offenders.append(setting.key)
            }
        }

        XCTAssertEqual(offenders, [], "a credential in the app is a credential on every device")
    }

    /// And it holds no endpoint path either: routes live next to the code that
    /// calls them, so a deployment cannot silently repoint one of them.
    func testTheExampleConfigurationDeclaresNoEndpointPath() throws {
        var offenders: [String] = []

        for setting in try Self.exampleSettings() {
            let value = setting.value.replacingOccurrences(of: "$(SLASH)", with: "/")
            if value.contains("/api/") {
                offenders.append("\(setting.key) = \(setting.value)")
            }
            guard setting.key.contains("API_BASE_URL"),
                  !setting.value.contains("$(CONFIGURATION)"),
                  let url = URL(string: value)
            else { continue }
            if !url.path().isEmpty, url.path() != "/" {
                offenders.append("\(setting.key) carries the path \(url.path())")
            }
        }

        XCTAssertEqual(offenders, [], "the config says where the backend is, not what to ask it")
    }
}
