//
//  MultipartFormDataTests.swift
//  KaloriasTests
//
//  Contract A1 / rules M1–M5.
//

import XCTest
@testable import Kalorias

nonisolated final class MultipartFormDataTests: XCTestCase {

    /// A fixed boundary keeps the assertions readable; `testBoundaryIsUniquePerRequest`
    /// covers the generated one.
    private let boundary = "TESTBOUNDARY"
    private let imageBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46])

    private func makeBody() -> (form: MultipartFormData, body: Data, text: String) {
        let form = MultipartFormData(boundary: boundary)
        let body = form.body(imageData: imageBytes)
        // `.isoLatin1` maps every byte 1:1, so the raw JPEG bytes cannot make
        // the whole body undecodable the way `.utf8` would.
        return (form, body, String(data: body, encoding: .isoLatin1) ?? "")
    }

    // MARK: M1 — one part, named `photo`

    func testFieldIsNamedPhotoWithAJPEGFilename() {
        let (_, _, text) = makeBody()
        XCTAssertTrue(
            text.contains("Content-Disposition: form-data; name=\"photo\"; filename=\"meal.jpg\""),
            "the server matches on the field name `photo` exactly"
        )
        XCTAssertTrue(text.contains("Content-Type: image/jpeg"))
    }

    /// FR-002: no prompt, model, schema or token limit travels with the photo —
    /// the server owns all of it. Counting the disposition headers is how an
    /// accidentally added second field would show up.
    func testBodyContainsExactlyOnePart() {
        let (_, _, text) = makeBody()

        let parts = text.components(separatedBy: "Content-Disposition:").count - 1
        XCTAssertEqual(parts, 1, "exactly one part must be sent")

        // Two delimiters only: the opening one and the closing one.
        let delimiters = text.components(separatedBy: "--\(boundary)").count - 1
        XCTAssertEqual(delimiters, 2)
    }

    // MARK: M2 — header and body agree

    func testContentTypeHeaderCarriesTheSameBoundaryAsTheBody() {
        let (form, _, text) = makeBody()

        XCTAssertEqual(form.contentTypeHeaderValue, "multipart/form-data; boundary=\(boundary)")
        XCTAssertTrue(text.hasPrefix("--\(boundary)\r\n"))
    }

    /// The classic failure: a hardcoded header whose boundary is not the body's.
    /// It surfaces as a `422` about a *missing photo*, which points at the wrong
    /// layer entirely.
    func testGeneratedBoundaryFlowsIntoBothHeaderAndBody() throws {
        let form = MultipartFormData()
        let generated = try XCTUnwrap(
            form.contentTypeHeaderValue.components(separatedBy: "boundary=").last
        )
        let text = String(data: form.body(imageData: imageBytes), encoding: .isoLatin1) ?? ""

        XCTAssertEqual(generated, form.boundary)
        XCTAssertTrue(text.hasPrefix("--\(generated)\r\n"))
        XCTAssertTrue(text.hasSuffix("--\(generated)--\r\n"))
    }

    // MARK: M3 — CRLF and the closing delimiter

    func testEveryLineEndingIsCRLF() {
        let (_, _, text) = makeBody()

        // Every `\n` in the structural text must be preceded by `\r`. A lone
        // one is parsed as part of the previous header's value.
        let bareNewlines = text.components(separatedBy: "\n").count - 1
        let crlfs = text.components(separatedBy: "\r\n").count - 1
        XCTAssertEqual(bareNewlines, crlfs, "found a line ending that is not CRLF")
    }

    func testBodyEndsWithTheClosingDelimiter() {
        let (_, _, text) = makeBody()
        XCTAssertTrue(text.hasSuffix("--\(boundary)--\r\n"))
    }

    func testHeadersAreSeparatedFromTheContentByABlankLine() {
        let (_, _, text) = makeBody()
        XCTAssertTrue(text.contains("Content-Type: image/jpeg\r\n\r\n"))
    }

    // MARK: M4 — the image survives unaltered

    func testImageBytesAppearUnmodified() throws {
        let (_, body, _) = makeBody()
        let range = try XCTUnwrap(body.range(of: imageBytes), "the JPEG bytes must appear verbatim")

        // And they are the only copy: nothing re-encoded or escaped them.
        XCTAssertNil(body[range.upperBound...].range(of: imageBytes))
    }

    func testEmptyImageDataStillProducesAWellFormedBody() {
        let form = MultipartFormData(boundary: boundary)
        let text = String(data: form.body(imageData: Data()), encoding: .isoLatin1) ?? ""

        XCTAssertTrue(text.hasPrefix("--\(boundary)\r\n"))
        XCTAssertTrue(text.hasSuffix("--\(boundary)--\r\n"))
    }

    // MARK: M5 — a unique boundary per request

    func testBoundaryIsUniquePerRequest() {
        let boundaries = Set((0..<50).map { _ in MultipartFormData().boundary })
        XCTAssertEqual(boundaries.count, 50, "each request must generate its own boundary")
    }

    /// A boundary that could occur inside JPEG data would truncate the upload.
    /// The generated form is dashes plus a UUID, which cannot.
    func testGeneratedBoundaryCannotOccurInBinaryData() {
        let generated = MultipartFormData().boundary
        XCTAssertTrue(generated.allSatisfy { $0.isHexDigit || $0 == "-" })
        XCTAssertGreaterThan(generated.count, 32)
    }
}
