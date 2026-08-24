//
//  AnalyzeMealResponseTests.swift
//  KaloriasTests
//
//  Contracts A2–A9, A12 / decoding rules D1–D8. Replaces
//  `CalorieAnalysisDecodingTests`, which covered the same behaviours against the
//  provider payload the app no longer receives.
//

import XCTest
@testable import Kalorias

nonisolated final class AnalyzeMealResponseTests: XCTestCase {

    private func parse(_ json: String) throws -> AnalysisOutcome {
        try AnalyzeMealResponse.parse(Data(json.utf8))
    }

    private func items(_ json: String) throws -> [FoodItem] {
        guard case .success(let analysis) = try parse(json) else {
            XCTFail("expected a food-bearing success")
            return []
        }
        return analysis.items
    }

    // MARK: A2 — the full success payload

    private let fullPayload = """
    {
      "data": {
        "foodDetected": true,
        "totalCalories": 615,
        "foods": [
          { "name": "Arroz blanco", "calories": 205, "protein": 4.3, "carbs": 44.5, "fat": 0.4,
            "region": { "x": 0.12, "y": 0.31, "width": 0.4, "height": 0.28 } },
          { "name": "Pechuga de pollo", "calories": 410, "protein": 62.0, "carbs": 0, "fat": 16.2,
            "region": null }
        ]
      }
    }
    """

    func testDecodesTheFullSuccessPayload() throws {
        guard case .success(let analysis) = try parse(fullPayload) else {
            return XCTFail("expected success")
        }

        XCTAssertEqual(analysis.totalCalories, 615)
        XCTAssertEqual(analysis.items.count, 2)

        XCTAssertEqual(analysis.items[0].name, "Arroz blanco")
        XCTAssertEqual(analysis.items[0].calories, 205)
        XCTAssertEqual(analysis.items[0].proteinGrams, 4.3)
        XCTAssertEqual(analysis.items[0].carbsGrams, 44.5)
        XCTAssertEqual(analysis.items[0].fatGrams, 0.4)

        XCTAssertEqual(analysis.items[1].name, "Pechuga de pollo")
        XCTAssertEqual(analysis.items[1].calories, 410)
        XCTAssertEqual(analysis.items[1].carbsGrams, 0)
    }

    // MARK: A4 — regions map unscaled, x→x and y→y

    /// **The axis-swap guard.** The server sends proportions in `0...1` from the
    /// top-left, which is exactly what `FoodRegion` stores. Dividing by 1000 or
    /// swapping the pair raises no error anywhere — it crops the wrong part of a
    /// plausible-looking photo — so the numbers are asserted individually rather
    /// than as a rect.
    func testRegionMapsUnscaledWithXAsXAndYAsY() throws {
        let region = try XCTUnwrap(items(fullPayload)[0].region)

        XCTAssertEqual(region.x, 0.12, accuracy: 0.0001, "x must stay x — not the y value")
        XCTAssertEqual(region.y, 0.31, accuracy: 0.0001, "y must stay y — not the x value")
        XCTAssertEqual(region.width, 0.4, accuracy: 0.0001)
        XCTAssertEqual(region.height, 0.28, accuracy: 0.0001)
    }

    /// An asymmetric region is the only shape that can catch a swap: a square
    /// one at the origin passes whichever way round it is read.
    func testAsymmetricRegionIsNotTransposed() throws {
        let items = try items("""
        { "data": { "foodDetected": true, "totalCalories": 100, "foods": [
            { "name": "Corner", "calories": 100,
              "region": { "x": 0.05, "y": 0.7, "width": 0.2, "height": 0.25 } } ] } }
        """)
        let region = try XCTUnwrap(items[0].region)

        XCTAssertEqual(region.x, 0.05, accuracy: 0.0001)
        XCTAssertEqual(region.y, 0.7, accuracy: 0.0001)
        XCTAssertLessThan(region.x, region.y, "a transposed read would invert this")
    }

    func testFullFrameRegionIsTheWholeImage() throws {
        let items = try items("""
        { "data": { "foodDetected": true, "totalCalories": 50, "foods": [
            { "name": "Whole", "calories": 50,
              "region": { "x": 0, "y": 0, "width": 1, "height": 1 } } ] } }
        """)
        let region = try XCTUnwrap(items[0].region)

        XCTAssertEqual(region.x, 0)
        XCTAssertEqual(region.y, 0)
        XCTAssertEqual(region.width, 1)
        XCTAssertEqual(region.height, 1)
    }

    // MARK: A3 — the `data` envelope is required

    /// Rule D1. Decoding straight into the payload fails *every* response, so
    /// this is the assertion that catches a refactor away from the envelope.
    func testRootLevelPayloadWithoutTheEnvelopeIsInvalid() {
        XCTAssertThrowsError(
            try parse("""
            { "foodDetected": true, "totalCalories": 205,
              "foods": [ { "name": "Arroz", "calories": 205 } ] }
            """)
        ) { XCTAssertEqual($0 as? AnalysisError, .invalidResponse) }
    }

    func testEmptyEnvelopeIsInvalid() {
        XCTAssertThrowsError(try parse("{ \"data\": {} }")) {
            XCTAssertEqual($0 as? AnalysisError, .invalidResponse)
        }
    }

    // MARK: A12 — unknown fields are ignored

    /// A `v1` server adding a field must not break the app.
    func testUnknownFieldsAreIgnored() throws {
        guard case .success(let analysis) = try parse("""
        { "data": { "foodDetected": true, "totalCalories": 300, "servingSize": "large",
          "confidence": 0.91,
          "foods": [ { "name": "Sopa", "calories": 300, "fiber": 3.2, "glycemicIndex": 40 } ] },
          "meta": { "version": "1.4" } }
        """) else {
            return XCTFail("expected success")
        }

        XCTAssertEqual(analysis.totalCalories, 300)
        XCTAssertEqual(analysis.items.first?.name, "Sopa")
    }

    // MARK: A5 — a missing or unusable region costs only the thumbnail

    func testNullRegionKeepsTheFood() throws {
        let items = try items(fullPayload)
        XCTAssertNil(items[1].region)
        XCTAssertEqual(items[1].name, "Pechuga de pollo", "a food is never dropped for lacking a region")
        XCTAssertEqual(items[1].calories, 410)
    }

    func testAbsentRegionKeyKeepsTheFood() throws {
        let items = try items("""
        { "data": { "foodDetected": true, "totalCalories": 90, "foods": [
            { "name": "Manzana", "calories": 90, "protein": 0.5 } ] } }
        """)
        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items[0].region)
        XCTAssertEqual(items[0].proteinGrams, 0.5)
    }

    func testMalformedRegionKeepsTheFoodAndDropsTheRegion() throws {
        let items = try items("""
        { "data": { "foodDetected": true, "totalCalories": 120, "foods": [
            { "name": "Tostada", "calories": 120,
              "region": { "x": "left", "y": null, "width": 0.3 } } ] } }
        """)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].calories, 120)
        XCTAssertNil(items[0].region)
    }

    func testDegenerateRegionKeepsTheFoodAndDropsTheRegion() throws {
        let items = try items("""
        { "data": { "foodDetected": true, "totalCalories": 200, "foods": [
            { "name": "Huevo", "calories": 200,
              "region": { "x": 0.3, "y": 0.3, "width": 0, "height": 0.4 } } ] } }
        """)
        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items[0].region, "a zero-area rect has nothing to crop")
    }

    func testRegionSlightlyPastTheEdgeIsClampedNotDropped() throws {
        let items = try items("""
        { "data": { "foodDetected": true, "totalCalories": 200, "foods": [
            { "name": "Borde", "calories": 200,
              "region": { "x": 0.9, "y": 0.1, "width": 0.3, "height": 0.2 } } ] } }
        """)
        let region = try XCTUnwrap(items[0].region)

        XCTAssertEqual(region.x, 0.9, accuracy: 0.0001)
        XCTAssertEqual(region.width, 0.1, accuracy: 0.0001, "clamped to the frame, not discarded")
    }

    // MARK: A6 — `null` macros stay `nil`, distinct from `0`

    /// In a nutrition app the difference is not cosmetic: `0 g` says the food
    /// has none, `—` says the analysis did not report it.
    func testNullMacrosStayNilAndAreDistinctFromZero() throws {
        let items = try items("""
        { "data": { "foodDetected": true, "totalCalories": 300, "foods": [
            { "name": "Plato sin macros", "calories": 300,
              "protein": null, "carbs": 0, "fat": null, "region": null } ] } }
        """)

        XCTAssertNil(items[0].proteinGrams, "null must not become 0")
        XCTAssertEqual(items[0].carbsGrams, 0, "an explicit 0 must survive as 0")
        XCTAssertNil(items[0].fatGrams)
        XCTAssertTrue(items[0].hasMacros, "the explicit 0 is a reported macro")
    }

    func testAbsentMacroKeysStayNil() throws {
        let items = try items("""
        { "data": { "foodDetected": true, "totalCalories": 150, "foods": [
            { "name": "Solo calorías", "calories": 150 } ] } }
        """)

        XCTAssertNil(items[0].proteinGrams)
        XCTAssertNil(items[0].carbsGrams)
        XCTAssertNil(items[0].fatGrams)
        XCTAssertFalse(items[0].hasMacros)
    }

    func testMacroOfTheWrongTypeDegradesToNilWithoutLosingTheMeal() throws {
        let items = try items("""
        { "data": { "foodDetected": true, "totalCalories": 210, "foods": [
            { "name": "Pasta", "calories": 210, "protein": "mucha", "carbs": 40 } ] } }
        """)

        XCTAssertEqual(items[0].calories, 210)
        XCTAssertNil(items[0].proteinGrams)
        XCTAssertEqual(items[0].carbsGrams, 40)
    }

    // MARK: A9 — the reported total is used verbatim

    /// FR-012. The server guarantees the invariant; when it breaks it, the user
    /// still sees the number the server sent rather than a figure the app made
    /// up that contradicts the list beneath it.
    func testReportedTotalWinsWhenItDiffersFromTheSum() throws {
        guard case .success(let analysis) = try parse("""
        { "data": { "foodDetected": true, "totalCalories": 999, "foods": [
            { "name": "A", "calories": 100 }, { "name": "B", "calories": 50 } ] } }
        """) else {
            return XCTFail("expected success")
        }

        XCTAssertEqual(analysis.totalCalories, 999, "the reported total is taken, not computed")
        XCTAssertEqual(CalorieAggregator.total(of: analysis.items), 150)
    }

    func testReportedTotalIsUsedEvenWhenItIsZero() throws {
        guard case .success(let analysis) = try parse("""
        { "data": { "foodDetected": true, "totalCalories": 0, "foods": [
            { "name": "Agua", "calories": 0 } ] } }
        """) else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(analysis.totalCalories, 0)
    }

    // MARK: A8 — what makes a response invalid

    func testMissingNameIsInvalidResponse() {
        XCTAssertThrowsError(
            try parse("""
            { "data": { "foodDetected": true, "totalCalories": 100, "foods": [
                { "calories": 100 } ] } }
            """)
        ) { XCTAssertEqual($0 as? AnalysisError, .invalidResponse) }
    }

    func testEmptyNameIsInvalidResponse() {
        XCTAssertThrowsError(
            try parse("""
            { "data": { "foodDetected": true, "totalCalories": 100, "foods": [
                { "name": "   ", "calories": 100 } ] } }
            """)
        ) { XCTAssertEqual($0 as? AnalysisError, .invalidResponse) }
    }

    func testMissingCaloriesIsInvalidResponse() {
        XCTAssertThrowsError(
            try parse("""
            { "data": { "foodDetected": true, "totalCalories": 100, "foods": [
                { "name": "Arroz" } ] } }
            """)
        ) { XCTAssertEqual($0 as? AnalysisError, .invalidResponse) }
    }

    func testNegativeCaloriesIsInvalidResponse() {
        XCTAssertThrowsError(
            try parse("""
            { "data": { "foodDetected": true, "totalCalories": 100, "foods": [
                { "name": "Arroz", "calories": -5 } ] } }
            """)
        ) { XCTAssertEqual($0 as? AnalysisError, .invalidResponse) }
    }

    func testMissingTotalIsInvalidResponse() {
        XCTAssertThrowsError(
            try parse("""
            { "data": { "foodDetected": true, "foods": [ { "name": "Arroz", "calories": 205 } ] } }
            """)
        ) { XCTAssertEqual($0 as? AnalysisError, .invalidResponse) }
    }

    func testGarbageIsInvalidResponse() {
        XCTAssertThrowsError(try parse("{ \"nope\": true }")) {
            XCTAssertEqual($0 as? AnalysisError, .invalidResponse)
        }
        XCTAssertThrowsError(try parse("not json at all")) {
            XCTAssertEqual($0 as? AnalysisError, .invalidResponse)
        }
        XCTAssertThrowsError(try AnalyzeMealResponse.parse(Data())) {
            XCTAssertEqual($0 as? AnalysisError, .invalidResponse)
        }
    }

    // MARK: A7 / D7 — no food is a success, not a failure

    /// FR-011. The user gets the no-food screen and its Retake action, and
    /// History gains nothing — the same behaviour as before this feature, which
    /// is the point.
    func testFoodDetectedFalseIsNoFood() throws {
        XCTAssertEqual(
            try parse(#"{ "data": { "foodDetected": false, "totalCalories": 0, "foods": [] } }"#),
            .noFood
        )
    }

    /// **Both shapes, because the server can send either.** An empty `foods`
    /// with the flag still set is the one a decoder written against the flag
    /// alone would turn into an empty success — a meal of nothing, saved to
    /// History.
    func testFoodDetectedTrueWithAnEmptyFoodsArrayIsAlsoNoFood() throws {
        XCTAssertEqual(
            try parse(#"{ "data": { "foodDetected": true, "totalCalories": 0, "foods": [] } }"#),
            .noFood
        )
    }

    /// Not even a non-zero reported total rescues an empty list: there is
    /// nothing to show a breakdown of.
    func testAnEmptyFoodsArrayIsNoFoodEvenWithAReportedTotal() throws {
        XCTAssertEqual(
            try parse(#"{ "data": { "foodDetected": true, "totalCalories": 450, "foods": [] } }"#),
            .noFood
        )
    }

    /// A `false` flag wins over a populated list — the server has said there is
    /// no food, and the app does not second-guess it.
    func testFoodDetectedFalseWinsOverAPopulatedList() throws {
        XCTAssertEqual(
            try parse("""
            { "data": { "foodDetected": false, "totalCalories": 0, "foods": [
                { "name": "Sombra", "calories": 10 } ] } }
            """),
            .noFood
        )
    }
}
