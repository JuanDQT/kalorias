//
//  MultipartFormData.swift
//  Kalorias
//
//  Builds the `multipart/form-data` body the Kalorias backend expects: exactly
//  one part, the photo. Foundation ships no multipart encoder, and the whole
//  body is a boundary line, three headers, the JPEG and a closing delimiter —
//  well under the bar a third-party networking dependency would have to clear
//  (constitution, Technology Constraints).
//
//  PURE ON PURPOSE. `Data` in, `Data` plus a header value out, no URLSession
//  anywhere near it, so the two things most likely to be wrong — the exact CRLF
//  placement and the closing `--boundary--` — are assertable in a unit test
//  rather than debuggable against a live server.
//
//  THE BOUNDARY IS OWNED HERE, AND THE HEADER COMES FROM THE SAME VALUE. A
//  hardcoded `Content-Type`, or a header whose boundary differs from the body's,
//  makes the server answer `422` complaining the photo is *missing* — a message
//  that points at the wrong layer entirely and costs an afternoon.
//

import Foundation

nonisolated struct MultipartFormData: Sendable {

    /// The generated delimiter. A UUID prefixed with dashes: it cannot occur in
    /// JPEG data by accident, and it is different for every request.
    let boundary: String

    /// The value to set on the request's `Content-Type` header. Carries the
    /// same boundary as `body`, because both read it from this instance.
    var contentTypeHeaderValue: String { "multipart/form-data; boundary=\(boundary)" }

    init(boundary: String = "--------------------------\(UUID().uuidString)") {
        self.boundary = boundary
    }

    /// A one-part body carrying `imageData` as the field the contract names.
    ///
    /// The field name, the filename and the part's own content type are fixed:
    /// the server matches on `photo` exactly, and rejects anything that is not
    /// declared JPEG.
    func body(
        imageData: Data,
        fieldName: String = "photo",
        fileName: String = "meal.jpg",
        mimeType: String = "image/jpeg"
    ) -> Data {
        var body = Data()

        // CRLF throughout — multipart is an RFC-2046 format, not a text file.
        // A lone `\n` anywhere here is parsed as part of the previous value.
        append(&body, "--\(boundary)\r\n")
        append(&body, "Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n")
        append(&body, "Content-Type: \(mimeType)\r\n")
        append(&body, "\r\n")
        body.append(imageData)
        append(&body, "\r\n")
        append(&body, "--\(boundary)--\r\n")

        return body
    }

    /// `String.data(using: .utf8)` on ASCII-only structural text cannot fail, so
    /// there is no error path to model here — the alternative would be a
    /// throwing initializer whose error nothing could ever produce.
    private func append(_ data: inout Data, _ string: String) {
        data.append(Data(string.utf8))
    }
}
