//
//  CalorieAnalysisDecodingTests.swift
//  KaloriasTests
//
//  Decodes the structured payload from contracts/gemini-response.schema.md.
//

import XCTest
@testable import Kalorias

nonisolated final class CalorieAnalysisDecodingTests: XCTestCase {

    private func json(_ string: String) -> Data { Data(string.utf8) }

    func testDecodesSuccessWithMacros() throws {
        let payload = json("""
        {
          "foodDetected": true,
          "foods": [
            { "name": "Grilled chicken breast", "calories": 280, "protein": 52, "carbs": 0, "fat": 6 },
            { "name": "White rice", "calories": 240, "protein": 4, "carbs": 53, "fat": 0 },
            { "name": "Steamed broccoli", "calories": 55, "protein": 4, "carbs": 11, "fat": 1 }
          ]
        }
        """)
        let outcome = try GeminiCalorieService.parseOutcome(fromModelJSON: payload)
        guard case .success(let analysis) = outcome else { return XCTFail("expected success") }
        XCTAssertEqual(analysis.items.count, 3)
        XCTAssertEqual(analysis.totalCalories, 575)          // computed, not from wire
        XCTAssertEqual(analysis.items[0].proteinGrams, 52)   // macros decoded
    }

    // MARK: Request shape (feature 007 regression guards)
    //
    // These assert the REQUEST, not the parsing. Parsing was never the broken part,
    // so no parser test could have caught the outage: making `box` optional made the
    // model produce a runaway, unparseable reply and meals were lost. The leniency
    // tests further down are deliberately SEPARATE — together the two groups encode
    // FR-006, "ask firmly, fail softly", which feature 006 collapsed into one.

    /// The exact defect. If `box` ever leaves this list, analyses start failing.
    func testSchemaRequiresBoxForEveryFood() throws {
        let required = try foodItemSchema()["required"] as? [String]
        XCTAssertNotNil(required)
        XCTAssertTrue(
            required?.contains("box") == true,
            "`box` must stay required — optional caused a MAX_TOKENS runaway that lost meals"
        )
        // The pre-existing requirements must survive too.
        XCTAssertTrue(required?.contains("name") == true)
        XCTAssertTrue(required?.contains("calories") == true)
    }

    func testSchemaBoxDeclaresFourRequiredIntegerEdges() throws {
        let box = try XCTUnwrap(
            foodItemSchema()["properties"] as? [String: Any],
            "food properties missing"
        )["box"] as? [String: Any]
        let boxSchema = try XCTUnwrap(box, "`box` property missing from the schema")

        XCTAssertEqual(boxSchema["type"] as? String, "OBJECT")

        let properties = try XCTUnwrap(boxSchema["properties"] as? [String: Any])
        for edge in ["ymin", "xmin", "ymax", "xmax"] {
            let edgeSchema = properties[edge] as? [String: Any]
            XCTAssertEqual(
                edgeSchema?["type"] as? String, "INTEGER",
                "`\(edge)` must be an integer edge"
            )
        }

        let boxRequired = boxSchema["required"] as? [String]
        XCTAssertEqual(boxRequired.map(Set.init), Set(["ymin", "xmin", "ymax", "xmax"]))
    }

    func testOutputTokenCeilingIsSetAndGenerous() {
        // A ceiling, not a target: healthy replies are a few hundred characters, so
        // this must sit far above them while still bounding a runaway reply.
        XCTAssertGreaterThanOrEqual(GeminiCalorieService.maxOutputTokens, 1_024)
    }

    /// Walks into `foods.items` so the assertions above read clearly.
    private func foodItemSchema() throws -> [String: Any] {
        let root = GeminiCalorieService.responseSchema
        let properties = try XCTUnwrap(root["properties"] as? [String: Any])
        let foods = try XCTUnwrap(properties["foods"] as? [String: Any])
        return try XCTUnwrap(foods["items"] as? [String: Any])
    }

    // MARK: Bounding boxes — parser leniency (feature 006, kept independent)

    /// The shape the app produced before boxes existed. Must still decode, and the
    /// nutrition must be untouched (FR-020).
    func testPayloadWithoutBoxesDecodesWithNilRegions() throws {
        let payload = json("""
        { "foodDetected": true, "foods": [ { "name": "Pollo", "calories": 320, "protein": 31 } ] }
        """)
        let outcome = try GeminiCalorieService.parseOutcome(fromModelJSON: payload)
        guard case .success(let analysis) = outcome else { return XCTFail("expected success") }

        XCTAssertEqual(analysis.items.count, 1)
        XCTAssertNil(analysis.items[0].region)
        XCTAssertEqual(analysis.items[0].calories, 320)
        XCTAssertEqual(analysis.items[0].proteinGrams, 31)
    }

    /// Boxes must land the right way round: `ymin` is the TOP edge, `xmin` the LEFT.
    func testBoxesMapToRegionsWithTopAsYAndLeftAsX() throws {
        let payload = json("""
        {
          "foodDetected": true,
          "foods": [
            { "name": "Pollo", "calories": 320,
              "box": { "ymin": 100, "xmin": 500, "ymax": 300, "xmax": 900 } }
          ]
        }
        """)
        let outcome = try GeminiCalorieService.parseOutcome(fromModelJSON: payload)
        guard case .success(let analysis) = outcome else { return XCTFail("expected success") }
        guard let region = analysis.items[0].region else { return XCTFail("expected a region") }

        XCTAssertEqual(region.y, 0.1, accuracy: 0.000_001, "ymin is the top edge")
        XCTAssertEqual(region.x, 0.5, accuracy: 0.000_001, "xmin is the left edge")
        XCTAssertEqual(region.height, 0.2, accuracy: 0.000_001)
        XCTAssertEqual(region.width, 0.4, accuracy: 0.000_001)
    }

    func testBoxesOnSomeFoodsOnlyStillDecodesEveryFood() throws {
        let payload = json("""
        {
          "foodDetected": true,
          "foods": [
            { "name": "Pollo", "calories": 320,
              "box": { "ymin": 0, "xmin": 0, "ymax": 500, "xmax": 500 } },
            { "name": "Arroz", "calories": 210 }
          ]
        }
        """)
        let outcome = try GeminiCalorieService.parseOutcome(fromModelJSON: payload)
        guard case .success(let analysis) = outcome else { return XCTFail("expected success") }

        XCTAssertEqual(analysis.items.count, 2)
        XCTAssertNotNil(analysis.items[0].region)
        XCTAssertNil(analysis.items[1].region)
        XCTAssertEqual(analysis.totalCalories, 530)
    }

    /// A bad box must cost only that food's thumbnail — never the whole meal
    /// (FR-021). This is the guardrail that keeps a decorative feature from
    /// blocking a calorie record.
    func testBoxMissingAnEdgeStillParsesTheMeal() throws {
        let payload = json("""
        {
          "foodDetected": true,
          "foods": [
            { "name": "Pollo", "calories": 320, "box": { "ymin": 100, "xmin": 200, "ymax": 400 } }
          ]
        }
        """)
        let outcome = try GeminiCalorieService.parseOutcome(fromModelJSON: payload)
        guard case .success(let analysis) = outcome else { return XCTFail("expected success") }

        XCTAssertEqual(analysis.items[0].calories, 320)
        XCTAssertNil(analysis.items[0].region, "an incomplete box degrades to no region")
    }

    func testBoxWithWrongTypesStillParsesTheMeal() throws {
        let payload = json("""
        {
          "foodDetected": true,
          "foods": [
            { "name": "Pollo", "calories": 320,
              "box": { "ymin": "top", "xmin": 200, "ymax": 400, "xmax": 600 } }
          ]
        }
        """)
        let outcome = try GeminiCalorieService.parseOutcome(fromModelJSON: payload)
        guard case .success(let analysis) = outcome else { return XCTFail("expected success") }

        XCTAssertEqual(analysis.items[0].calories, 320)
        XCTAssertNil(analysis.items[0].region)
    }

    func testBoxOutOfRangeIsClampedRatherThanDropped() throws {
        let payload = json("""
        {
          "foodDetected": true,
          "foods": [
            { "name": "Pollo", "calories": 320,
              "box": { "ymin": 900, "xmin": 100, "ymax": 1005, "xmax": 400 } }
          ]
        }
        """)
        let outcome = try GeminiCalorieService.parseOutcome(fromModelJSON: payload)
        guard case .success(let analysis) = outcome else { return XCTFail("expected success") }
        guard let region = analysis.items[0].region else {
            return XCTFail("an overhanging box should clamp, not drop")
        }
        XCTAssertEqual(region.height, 0.1, accuracy: 0.000_001)
    }

    func testDegenerateBoxYieldsNoRegionButKeepsTheFood() throws {
        let payload = json("""
        {
          "foodDetected": true,
          "foods": [
            { "name": "Pollo", "calories": 320,
              "box": { "ymin": 300, "xmin": 300, "ymax": 300, "xmax": 700 } }
          ]
        }
        """)
        let outcome = try GeminiCalorieService.parseOutcome(fromModelJSON: payload)
        guard case .success(let analysis) = outcome else { return XCTFail("expected success") }

        XCTAssertEqual(analysis.items.count, 1)
        XCTAssertNil(analysis.items[0].region)
    }

    func testDecodesNoFood() throws {
        let outcome = try GeminiCalorieService.parseOutcome(
            fromModelJSON: json(#"{ "foodDetected": false, "foods": [] }"#)
        )
        XCTAssertEqual(outcome, .noFood)
    }

    func testEmptyFoodsIsNoFoodEvenIfFlagTrue() throws {
        let outcome = try GeminiCalorieService.parseOutcome(
            fromModelJSON: json(#"{ "foodDetected": true, "foods": [] }"#)
        )
        XCTAssertEqual(outcome, .noFood)
    }

    func testMissingRequiredFieldIsInvalidResponse() {
        // "calories" missing.
        let payload = json(#"{ "foodDetected": true, "foods": [ { "name": "Mystery" } ] }"#)
        XCTAssertThrowsError(try GeminiCalorieService.parseOutcome(fromModelJSON: payload)) {
            XCTAssertEqual($0 as? AnalysisError, .invalidResponse)
        }
    }

    func testNegativeCaloriesIsInvalidResponse() {
        let payload = json(#"{ "foodDetected": true, "foods": [ { "name": "Bad", "calories": -10 } ] }"#)
        XCTAssertThrowsError(try GeminiCalorieService.parseOutcome(fromModelJSON: payload)) {
            XCTAssertEqual($0 as? AnalysisError, .invalidResponse)
        }
    }

    func testGarbageIsInvalidResponse() {
        XCTAssertThrowsError(try GeminiCalorieService.parseOutcome(fromModelJSON: json("not json"))) {
            XCTAssertEqual($0 as? AnalysisError, .invalidResponse)
        }
    }
}
