//
//  CalorieAnalysisErrorMappingTests.swift
//  KaloriasTests
//

import XCTest
@testable import Kalorias

nonisolated final class CalorieAnalysisErrorMappingTests: XCTestCase {

    func testNoConnectionMapping() {
        XCTAssertEqual(AnalysisError.from(URLError(.notConnectedToInternet)), .noConnection)
        XCTAssertEqual(AnalysisError.from(URLError(.networkConnectionLost)), .noConnection)
        XCTAssertEqual(AnalysisError.from(URLError(.dataNotAllowed)), .noConnection)
    }

    func testTimeoutMapping() {
        XCTAssertEqual(AnalysisError.from(URLError(.timedOut)), .timeout)
    }

    func testOtherURLErrorsMapToServiceError() {
        XCTAssertEqual(AnalysisError.from(URLError(.badServerResponse)), .serviceError)
    }

    func testDecodingErrorMapsToInvalidResponse() {
        let decodingError = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "x"))
        XCTAssertEqual(AnalysisError.from(decodingError), .invalidResponse)
    }

    func testExistingAnalysisErrorPassesThrough() {
        XCTAssertEqual(AnalysisError.from(AnalysisError.invalidResponse), .invalidResponse)
    }
}
