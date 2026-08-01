//
//  CalorieAnalysisStoreTests.swift
//  KaloriasTests
//

import XCTest
@testable import Kalorias

/// Configurable mock analyzer (actor for safe call counting across suspensions).
private actor MockAnalyzer: CalorieAnalyzing {
    enum Response { case outcome(AnalysisOutcome), failure(AnalysisError) }
    private var response: Response
    private(set) var callCount = 0

    init(_ response: Response) { self.response = response }
    func set(_ response: Response) { self.response = response }

    func analyze(imageData: Data) async throws -> AnalysisOutcome {
        callCount += 1
        switch response {
        case .outcome(let outcome): return outcome
        case .failure(let error): throw error
        }
    }
}

nonisolated final class CalorieAnalysisStoreTests: XCTestCase {

    @MainActor
    private func makeStore(_ response: MockAnalyzer.Response) -> CalorieAnalysisStore {
        CalorieAnalysisStore(imageData: Data([0x1]), image: nil, analyzer: MockAnalyzer(response))
    }

    @MainActor
    func testAnalyzingToResult() async {
        let analysis = CalorieAnalysis(items: [FoodItem(name: "A", calories: 100)], totalCalories: 100)
        let store = makeStore(.outcome(.success(analysis)))
        await store.start()?.value
        XCTAssertEqual(store.state, .result(analysis))
    }

    @MainActor
    func testSingleFlightIgnoresSecondStart() {
        let store = makeStore(.outcome(.noFood))
        let first = store.start()
        let second = store.start()   // task still set → no concurrent analysis
        XCTAssertNotNil(first)
        XCTAssertNil(second, "a second start() while analyzing must not launch a concurrent analysis")
    }

    @MainActor
    func testCancelEndsFlowAndAllowsRestart() {
        let store = makeStore(.outcome(.noFood))
        store.start()
        store.cancel()
        // Task was cleared, so a fresh start is allowed.
        XCTAssertNotNil(store.start())
    }

    @MainActor
    func testNoFoodOutcomeSetsNoFoodState() async {
        let store = makeStore(.outcome(.noFood))
        await store.start()?.value
        XCTAssertEqual(store.state, .noFood)
    }

    @MainActor
    func testThrownErrorSetsFailedState() async {
        let store = makeStore(.failure(.serviceError))
        await store.start()?.value
        XCTAssertEqual(store.state, .failed(.serviceError))
    }

    @MainActor
    func testRetryReanalyzesTheSamePhoto() async {
        let mock = MockAnalyzer(.failure(.timeout))
        let store = CalorieAnalysisStore(imageData: Data([0x1]), image: nil, analyzer: mock)
        await store.start()?.value
        XCTAssertEqual(store.state, .failed(.timeout))

        // Now the service recovers; retry must re-run and succeed.
        let analysis = CalorieAnalysis(items: [FoodItem(name: "A", calories: 100)], totalCalories: 100)
        await mock.set(.outcome(.success(analysis)))
        await store.retry()?.value
        XCTAssertEqual(store.state, .result(analysis))
    }
}
