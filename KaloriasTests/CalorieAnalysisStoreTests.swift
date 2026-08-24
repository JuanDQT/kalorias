//
//  CalorieAnalysisStoreTests.swift
//  KaloriasTests
//

import XCTest
import UIKit
@testable import Kalorias

/// Counts what reached persistence. `@MainActor` because `MealRecording` is —
/// the store calls it from the main actor, so the count is read there too.
@MainActor
private final class SpyRecorder: MealRecording {
    private(set) var recordedCount = 0
    private(set) var recorded: CalorieAnalysis?

    func record(image: UIImage?, analysis: CalorieAnalysis, date: Date) async {
        recordedCount += 1
        recorded = analysis
    }
}

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

    // MARK: The photo that never left the device (rules S7–S9)

    /// S7. Constructed already failed, so the screen has its message before
    /// anything runs.
    @MainActor
    func testRejectedPhotoStoreStartsAlreadyFailed() {
        let store = CalorieAnalysisStore(rejectedPhoto: nil)
        XCTAssertEqual(store.state, .failed(.photoRejected))
    }

    /// S7. `AnalysisResultView` calls `start()` from `.onAppear`, so a store
    /// that let that through would flash the message and then replace it with a
    /// spinner that never resolves.
    @MainActor
    func testStartDoesNotOverwriteARejectedPhotoState() async {
        let store = CalorieAnalysisStore(rejectedPhoto: nil)

        XCTAssertNil(store.start(), "no analysis may begin — there is nothing to send")
        XCTAssertEqual(store.state, .failed(.photoRejected))
    }

    /// S8. Retrying bytes that were never sendable cannot succeed; the only way
    /// out is Retake, which is what the screen offers.
    @MainActor
    func testRetryIsANoOpForARejectedPhoto() async {
        let store = CalorieAnalysisStore(rejectedPhoto: nil)

        XCTAssertNil(store.retry())
        XCTAssertEqual(store.state, .failed(.photoRejected))
    }

    /// S9. Nothing is recorded and no request is made — the failure is entirely
    /// local.
    @MainActor
    func testRejectedPhotoRecordsNothing() async {
        let recorder = SpyRecorder()
        let store = CalorieAnalysisStore(rejectedPhoto: nil)

        store.start()
        store.retry()

        XCTAssertEqual(recorder.recordedCount, 0)
        XCTAssertEqual(store.state, .failed(.photoRejected))
    }

    /// The photo is still shown: it is the thing the user is being asked to
    /// replace.
    @MainActor
    func testRejectedPhotoStoreKeepsTheImageForTheThumbnail() {
        let image = UIImage()
        XCTAssertNotNil(CalorieAnalysisStore(rejectedPhoto: image).image)
    }

    /// Cancelling out of the rejected state must behave like every other
    /// failure — no crash, no lingering task.
    @MainActor
    func testCancelFromARejectedPhotoStateIsSafe() {
        let store = CalorieAnalysisStore(rejectedPhoto: nil)
        store.cancel()
        XCTAssertEqual(store.state, .failed(.photoRejected))
    }

    // MARK: Persistence is untouched by the backend move (T031 / SC-009)

    /// The whole claim of this feature is that only the *source* of an analysis
    /// changed. This walks a real server payload through the decoder, the store
    /// and into `MealRecording` and asserts that what arrives at persistence is
    /// what the server sent — names, the reported total, an absent macro still
    /// absent, and a region still carrying its own unswapped coordinates.
    @MainActor
    func testASuccessfulAnalysisReachesPersistenceIntact() async throws {
        let payload = Data("""
        { "data": { "foodDetected": true, "totalCalories": 615, "foods": [
            { "name": "Arroz blanco", "calories": 205, "protein": 4.3, "carbs": 44.5, "fat": 0.4,
              "region": { "x": 0.12, "y": 0.31, "width": 0.4, "height": 0.28 } },
            { "name": "Pechuga de pollo", "calories": 410, "protein": 62.0, "carbs": 0,
              "region": null } ] } }
        """.utf8)

        let outcome = try AnalyzeMealResponse.parse(payload)
        let recorder = SpyRecorder()
        let store = CalorieAnalysisStore(
            imageData: Data([0x1]),
            image: nil,
            analyzer: MockAnalyzer(.outcome(outcome)),
            recorder: recorder
        )

        await store.start()?.value

        XCTAssertEqual(recorder.recordedCount, 1)
        let recorded = try XCTUnwrap(recorder.recorded)

        XCTAssertEqual(recorded.totalCalories, 615)
        XCTAssertEqual(recorded.items.map(\.name), ["Arroz blanco", "Pechuga de pollo"])
        XCTAssertEqual(recorded.items[0].proteinGrams, 4.3)
        XCTAssertEqual(recorded.items[1].carbsGrams, 0, "an explicit 0 must persist as 0")
        XCTAssertNil(recorded.items[1].fatGrams, "an absent macro must persist as absent")

        let region = try XCTUnwrap(recorded.items[0].region)
        XCTAssertEqual(region.x, 0.12, accuracy: 0.0001)
        XCTAssertEqual(region.y, 0.31, accuracy: 0.0001)
        XCTAssertNil(recorded.items[1].region)
    }

    /// FR-024, restated for the two states this feature adds: nothing but a
    /// success may reach History.
    @MainActor
    func testNoFoodAndFailuresRecordNothing() async {
        for response in [
            MockAnalyzer.Response.outcome(.noFood),
            .failure(.photoRejected),
            .failure(.rateLimited(retryAfter: 20)),
            .failure(.serviceError)
        ] {
            let recorder = SpyRecorder()
            let store = CalorieAnalysisStore(
                imageData: Data([0x1]), image: nil,
                analyzer: MockAnalyzer(response), recorder: recorder
            )

            await store.start()?.value
            XCTAssertEqual(recorder.recordedCount, 0, "\(response) must save nothing")
        }
    }

    // MARK: Rate-limit cooldown (rules S1–S6 / FR-020)

    /// A movable clock, so every assertion below is exact and nothing sleeps
    /// waiting for a real second to pass (Principle II).
    @MainActor
    private final class TestClock {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
    }

    @MainActor
    private func makeRateLimitedStore(
        retryAfter: TimeInterval = 20,
        clock: TestClock
    ) -> CalorieAnalysisStore {
        CalorieAnalysisStore(
            imageData: Data([0x1]),
            image: nil,
            analyzer: MockAnalyzer(.failure(.rateLimited(retryAfter: retryAfter))),
            now: { clock.now }
        )
    }

    /// S1. The wait the server asked for becomes the number on the button.
    @MainActor
    func testRateLimitStartsACooldown() async {
        let clock = TestClock()
        let store = makeRateLimitedStore(retryAfter: 20, clock: clock)

        await store.start()?.value

        XCTAssertEqual(store.state, .failed(.rateLimited(retryAfter: 20)))
        XCTAssertEqual(store.secondsUntilRetry, 20)
        XCTAssertFalse(store.canRetry)
    }

    /// **S2, and the reason the gate is in the store.** A `disabled` modifier
    /// can be refactored away; this cannot. Calling `retry()` directly while
    /// cooling must do nothing at all — no request, no state change.
    @MainActor
    func testRetryIsANoOpWhileCoolingDown() async {
        let clock = TestClock()
        let store = makeRateLimitedStore(clock: clock)

        await store.start()?.value

        XCTAssertNil(store.retry(), "the store itself must refuse, not just the button")
        XCTAssertEqual(store.state, .failed(.rateLimited(retryAfter: 20)))
        XCTAssertEqual(store.secondsUntilRetry, 20)
    }

    /// S3. Reaching zero re-enables retry in place — no navigation, no new
    /// screen.
    @MainActor
    func testReachingZeroReEnablesRetryInPlace() async {
        let clock = TestClock()
        let store = makeRateLimitedStore(retryAfter: 2, clock: clock)

        await store.start()?.value
        XCTAssertFalse(store.canRetry)

        // The countdown reads the injected clock, so moving it is all it takes.
        clock.now = clock.now.addingTimeInterval(2)
        try? await Task.sleep(for: .milliseconds(1200))

        XCTAssertEqual(store.secondsUntilRetry, 0)
        XCTAssertTrue(store.canRetry)
        XCTAssertEqual(store.state, .failed(.rateLimited(retryAfter: 2)), "the message stays until the user acts")
    }

    /// S4. Cancel ends the analysis *and* the countdown; a store the user walked
    /// away from must not keep a task ticking.
    @MainActor
    func testCancelEndsTheCooldownAsWellAsTheAnalysis() async {
        let clock = TestClock()
        let store = makeRateLimitedStore(clock: clock)

        await store.start()?.value
        XCTAssertEqual(store.secondsUntilRetry, 20)

        store.cancel()

        XCTAssertEqual(store.secondsUntilRetry, 0)
        XCTAssertTrue(store.canRetry)
    }

    /// A successful retry must not leave a countdown running behind the result.
    @MainActor
    func testASuccessfulRetryClearsTheCooldown() async {
        let clock = TestClock()
        let mock = MockAnalyzer(.failure(.rateLimited(retryAfter: 1)))
        let store = CalorieAnalysisStore(
            imageData: Data([0x1]), image: nil, analyzer: mock, now: { clock.now }
        )

        await store.start()?.value
        XCTAssertEqual(store.secondsUntilRetry, 1)

        clock.now = clock.now.addingTimeInterval(1)
        let analysis = CalorieAnalysis(items: [FoodItem(name: "A", calories: 100)], totalCalories: 100)
        await mock.set(.outcome(.success(analysis)))

        try? await Task.sleep(for: .milliseconds(1200))
        XCTAssertTrue(store.canRetry)

        await store.retry()?.value

        XCTAssertEqual(store.state, .result(analysis))
        XCTAssertEqual(store.secondsUntilRetry, 0)
        XCTAssertTrue(store.canRetry)
    }

    /// Every other failure stays immediately retryable — the cooldown belongs to
    /// the rate limit alone.
    @MainActor
    func testOtherFailuresStartNoCooldown() async {
        for error in [AnalysisError.serviceError, .timeout, .noConnection, .invalidResponse] {
            let store = CalorieAnalysisStore(
                imageData: Data([0x1]), image: nil, analyzer: MockAnalyzer(.failure(error))
            )
            await store.start()?.value

            XCTAssertEqual(store.secondsUntilRetry, 0, "\(error)")
            XCTAssertTrue(store.canRetry, "\(error)")
        }
    }

    /// FR-022a. Nothing anywhere retries on the user's behalf: after a failure
    /// the analyzer has been called exactly once and stays there.
    @MainActor
    func testNoFailureEverRetriesWithoutTheUserAsking() async {
        let clock = TestClock()
        let mock = MockAnalyzer(.failure(.rateLimited(retryAfter: 1)))
        let store = CalorieAnalysisStore(
            imageData: Data([0x1]), image: nil, analyzer: mock, now: { clock.now }
        )

        await store.start()?.value
        clock.now = clock.now.addingTimeInterval(1)
        try? await Task.sleep(for: .milliseconds(1500))

        let callCount = await mock.callCount
        XCTAssertEqual(callCount, 1, "the cooldown expiring must not re-send anything")
        XCTAssertEqual(store.state, .failed(.rateLimited(retryAfter: 1)))
    }

    /// FR-020a end to end: a `429` with no usable header still produces a
    /// definite, bounded wait rather than an unusable button.
    @MainActor
    func testAnAbsentServerWaitStillProducesAUsableCountdown() async {
        let clock = TestClock()
        let store = makeRateLimitedStore(
            retryAfter: RetryCooldown.parseRetryAfter(nil, now: clock.now), clock: clock
        )

        await store.start()?.value

        XCTAssertEqual(store.secondsUntilRetry, 60)
        XCTAssertFalse(store.canRetry)
    }
}
