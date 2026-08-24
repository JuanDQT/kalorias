//
//  AnalyzeMealResponse.swift
//  Kalorias
//
//  The wire shape of `POST /api/v1/kalorias/analyzeMeal`, and the one place it
//  becomes domain types. It replaced the AI-provider envelope and payload the app
//  used to decode: the prompt, the response schema and the 0–1000 box scale are
//  the server's business now.
//
//  FOUR THINGS ARE EASY TO GET WRONG HERE, and each one fails silently:
//
//  1. THE `data` ENVELOPE. The payload is not at the root. Decoding straight
//     into `Payload` fails every single response.
//  2. `region` IS ALREADY PROPORTIONS `0...1` FROM THE TOP-LEFT. Do NOT divide
//     by 1000 and do NOT reorder the axes. Swapping x and y raises no error —
//     it crops the wrong part of the photo and the result looks plausible.
//  3. `null` MACROS ARE NOT `0`. `null` means "not reported" and renders `—`;
//     `0` means the food has none. Defaulting one to the other lies to the user
//     in a nutrition app.
//  4. `region: null` IS NORMAL. It costs that food its thumbnail and nothing
//     else — never drop a food for lacking one.
//
//  STRICTNESS IS ASYMMETRIC, DELIBERATELY. `name` and `calories` are strict: a
//  food without them is meaningless, so the whole response is `.invalidResponse`
//  rather than a meal with a hole in it. Everything else is lenient and degrades
//  to `nil`, because a missing macro or an unusable box is worth less than the
//  meal it would otherwise discard.
//

import Foundation

nonisolated struct AnalyzeMealResponse: Decodable {

    /// The envelope. Its absence is `.invalidResponse` (rule D1).
    let data: Payload

    nonisolated struct Payload: Decodable {
        let foodDetected: Bool
        /// Taken as received, never recomputed (rule D3 / FR-012).
        let totalCalories: Int
        let foods: [Food]
    }

    nonisolated struct Food: Decodable {
        let name: String
        let calories: Int
        let protein: Double?
        let carbs: Double?
        let fat: Double?
        let region: Region?

        private enum CodingKeys: String, CodingKey {
            case name, calories, protein, carbs, fat, region
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Strict: these two decide whether the food means anything.
            name = try container.decode(String.self, forKey: .name)
            calories = try container.decode(Int.self, forKey: .calories)
            // Lenient: `try?` so a macro of the wrong type degrades to "not
            // reported" instead of costing the user their meal.
            protein = try? container.decodeIfPresent(Double.self, forKey: .protein)
            carbs = try? container.decodeIfPresent(Double.self, forKey: .carbs)
            fat = try? container.decodeIfPresent(Double.self, forKey: .fat)
            region = try? container.decodeIfPresent(Region.self, forKey: .region)
        }
    }

    /// Proportions in `0...1`, origin top-left — exactly what `FoodRegion`
    /// stores, which is why the mapping below scales nothing.
    nonisolated struct Region: Decodable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        /// `nil` when the rectangle has no usable area left after clamping
        /// (rule D6). The labels are spelled out at the call site so an axis
        /// swap has to be written on purpose to happen at all.
        var foodRegion: FoodRegion? {
            FoodRegion(clampingX: x, y: y, width: width, height: height)
        }
    }

    // MARK: Mapping to the domain

    /// Decode a `200` body and map it to an outcome.
    ///
    /// - Throws: `AnalysisError.invalidResponse` when the body is unreadable, is
    ///   missing its envelope, or carries a food without a usable name or a
    ///   sane calorie figure.
    static func parse(_ data: Data) throws -> AnalysisOutcome {
        let response: AnalyzeMealResponse
        do {
            response = try JSONDecoder().decode(AnalyzeMealResponse.self, from: data)
        } catch {
            // Unknown extra fields never reach here: `Decodable` ignores them by
            // default, so a `v1` server adding a field cannot break the app
            // (rule D8).
            throw AnalysisError.invalidResponse
        }

        let payload = response.data
        guard payload.foodDetected else { return .noFood }

        var items: [FoodItem] = []
        items.reserveCapacity(payload.foods.count)

        for food in payload.foods {
            guard food.calories >= 0 else { throw AnalysisError.invalidResponse }
            guard !food.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AnalysisError.invalidResponse
            }

            items.append(
                FoodItem(
                    name: food.name,
                    calories: food.calories,
                    proteinGrams: food.protein,
                    carbsGrams: food.carbs,
                    fatGrams: food.fat,
                    region: food.region?.foodRegion
                )
            )
        }

        // An empty `foods` is no-food too, even with the flag set (rule D7).
        return CalorieAggregator.make(from: items, reportedTotal: payload.totalCalories)
    }
}
