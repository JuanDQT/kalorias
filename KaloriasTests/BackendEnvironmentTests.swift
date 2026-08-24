//
//  BackendEnvironmentTests.swift
//  KaloriasTests
//

import XCTest
@testable import Kalorias

nonisolated final class BackendEnvironmentTests: XCTestCase {

    // MARK: The xcconfig `//` guard (contract C3)

    /// **This is the test the whole entry exists for.** In an xcconfig file
    /// `//` starts a comment *inside a value*, so `https://www.quispe.com`
    /// written literally becomes `https:` — which `URL(string:)` accepts, and
    /// which resolves to nothing. Reading the address the build actually
    /// produced and demanding a host is what turns that into a build-time
    /// failure instead of a generic service error on every analysis.
    func testConfiguredAddressIsAnAbsoluteURLWithSchemeAndHost() throws {
        let url = try XCTUnwrap(
            BackendEnvironment.analysisBaseURL,
            "KaloriasAPIBaseURL is missing or unparseable. Check Config/Secrets.xcconfig — a literal `//` in a value starts a comment; use $(SLASH)."
        )

        XCTAssertFalse(url.scheme?.isEmpty ?? true, "the address must carry a scheme")
        XCTAssertFalse(url.host()?.isEmpty ?? true, "the address must carry a host — `https:` is what `//` truncation leaves behind")
        XCTAssertTrue(BackendEnvironment.isConfigured)
    }

    /// The same truncation, asserted directly rather than via the build, so the
    /// rule is pinned even if the configured value is later changed.
    func testSchemeWithoutAHostIsRejected() {
        XCTAssertNil(BackendEnvironment.baseURL { _ in "https:" })
        XCTAssertNil(BackendEnvironment.baseURL { _ in "http:" })
    }

    // MARK: Absent / blank

    func testAbsentValueYieldsNil() {
        XCTAssertNil(BackendEnvironment.baseURL { _ in nil })
    }

    func testBlankValueYieldsNil() {
        XCTAssertNil(BackendEnvironment.baseURL { _ in "" })
    }

    func testWhitespaceOnlyValueYieldsNil() {
        XCTAssertNil(BackendEnvironment.baseURL { _ in "   \n\t " })
    }

    func testGarbageValueYieldsNil() {
        XCTAssertNil(BackendEnvironment.baseURL { _ in "not a url at all" })
    }

    // MARK: Well-formed addresses

    func testHTTPSAddressParses() throws {
        let url = try XCTUnwrap(BackendEnvironment.baseURL { _ in "https://www.example.com" })
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host(), "www.example.com")
    }

    func testLocalhostWithPortParses() throws {
        let url = try XCTUnwrap(BackendEnvironment.baseURL { _ in "http://localhost:8000" })
        XCTAssertEqual(url.scheme, "http")
        XCTAssertEqual(url.host(), "localhost")
        XCTAssertEqual(url.port, 8000)
    }

    func testSurroundingWhitespaceIsTrimmed() throws {
        let url = try XCTUnwrap(BackendEnvironment.baseURL { _ in "  https://www.example.com  " })
        XCTAssertEqual(url.absoluteString, "https://www.example.com")
    }

    // MARK: The location it names

    /// Naming the key is only worth anything if it is the key actually looked
    /// up: asserting the constant alone would pass against an implementation
    /// that read some other one.
    func testAddressIsReadFromTheKeyTheEnvironmentNames() {
        var requestedKeys: [String] = []

        _ = BackendEnvironment.baseURL { key in
            requestedKeys.append(key)
            return "https://www.example.com"
        }

        XCTAssertEqual(requestedKeys, [BackendEnvironment.baseURLInfoDictionaryKey])
        XCTAssertEqual(requestedKeys, ["KaloriasAPIBaseURL"])
    }
}
