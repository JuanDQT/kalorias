//
//  GeminiCalorieService.swift
//  Kalorias
//
//  The real `CalorieAnalyzing` implementation: sends the photo to Gemini's
//  `generateContent` with a response schema and decodes the structured JSON
//  result. Networking/decoding run in the async context (off the main thread);
//  the type is a `Sendable` value type holding no mutable state.
//
//  Confined to this service boundary per the constitution — never called from
//  views. The API key comes from `AppSecrets` (git-ignored config).
//

import Foundation

nonisolated struct GeminiCalorieService: CalorieAnalyzing {
    let apiKey: String
    let model: String
    let session: URLSession
    let timeout: TimeInterval

    init(
        apiKey: String = AppSecrets.geminiAPIKey,
        model: String = AppSecrets.geminiModel,
        session: URLSession = .shared,
        timeout: TimeInterval = 30
    ) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
        self.timeout = timeout
    }

    func analyze(imageData: Data) async throws -> AnalysisOutcome {
        guard !apiKey.isEmpty else { throw AnalysisError.serviceError }

        let request: URLRequest
        do {
            request = try makeRequest(imageData: imageData)
        } catch {
            throw AnalysisError.serviceError
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AnalysisError.from(error)
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            #if DEBUG
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[GeminiCalorieService] HTTP \(status): \(body.prefix(500))")
            #endif
            throw AnalysisError.serviceError
        }

        let modelJSON = try Self.extractModelJSON(from: data)
        return try Self.parseOutcome(fromModelJSON: modelJSON)
    }

    // MARK: Request

    private func makeRequest(imageData: Data) throws -> URLRequest {
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        guard let url = URL(string: endpoint) else { throw AnalysisError.serviceError }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["inline_data": ["mime_type": "image/jpeg", "data": imageData.base64EncodedString()]],
                    ["text": Self.prompt]
                ]
            ]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": Self.responseSchema,
                // A ceiling, not a target. Healthy replies measure a few hundred
                // characters, so this cannot truncate a legitimate answer even for a
                // plate with dozens of foods — it exists so a degenerate reply fails
                // fast and cheaply rather than consuming the whole default budget
                // (FR-003). A truncated reply is malformed and takes the existing
                // error path, which saves nothing (FR-004).
                "maxOutputTokens": Self.maxOutputTokens
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static let prompt = """
    You are a nutrition assistant. Identify each distinct food in the image and \
    estimate its calories and macros (grams). For each food, also report `box`: \
    the bounding box of the region it occupies, as integers on a 0-1000 scale \
    normalized to the image, where `ymin`/`ymax` are measured from the TOP edge \
    and `xmin`/`xmax` from the LEFT edge. Omit `box` for a food you cannot \
    localize. If the image contains no identifiable food, return \
    foodDetected=false and an empty foods array. Respond ONLY with JSON matching \
    the provided schema.
    """

    /// Upper bound on model output. Exposed for unit testing.
    static let maxOutputTokens = 4096

    /// The response schema sent with every request. Exposed for unit testing so a
    /// regression test can assert `box` stays required — the exact property whose
    /// absence caused an outage.
    static var responseSchema: [String: Any] {[
        "type": "OBJECT",
        "properties": [
            "foodDetected": ["type": "BOOLEAN"],
            "foods": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "name": ["type": "STRING"],
                        "calories": ["type": "INTEGER"],
                        "protein": ["type": "NUMBER"],
                        "carbs": ["type": "NUMBER"],
                        "fat": ["type": "NUMBER"],
                        "box": [
                            "type": "OBJECT",
                            "properties": [
                                "ymin": ["type": "INTEGER"],
                                "xmin": ["type": "INTEGER"],
                                "ymax": ["type": "INTEGER"],
                                "xmax": ["type": "INTEGER"]
                            ],
                            "required": ["ymin", "xmin", "ymax", "xmax"]
                        ]
                    ],
                    // `box` MUST stay in this list. Making it optional (feature 006)
                    // destabilised generation badly enough to lose meals: measured
                    // against the live model, an optional `box` produced a runaway
                    // reply that hit `MAX_TOKENS` and returned ~65,000 characters of
                    // malformed digits, unparseable, so nothing was saved. Required,
                    // the same request replies cleanly with a box for every food.
                    //
                    // This does NOT make regions mandatory for the app: the parser
                    // below tolerates a missing or malformed box and simply drops
                    // that food's thumbnail. Asking firmly and failing softly are
                    // separate concerns — feature 006 conflated them and caused an
                    // outage (FR-001 / FR-006).
                    "required": ["name", "calories", "box"]
                ]
            ]
        ],
        "required": ["foodDetected", "foods"]
    ]}

    // MARK: Response decoding (testable)

    /// Pull the model's JSON text out of the Gemini envelope.
    static func extractModelJSON(from data: Data) throws -> Data {
        let envelope = try JSONDecoder().decode(GeminiEnvelope.self, from: data)
        guard
            let text = envelope.candidates.first?.content.parts.compactMap(\.text).first,
            let json = text.data(using: .utf8)
        else {
            throw AnalysisError.invalidResponse
        }
        return json
    }

    /// Decode + validate the structured payload and map it to a domain outcome.
    /// Exposed for unit testing with fixtures.
    static func parseOutcome(fromModelJSON json: Data) throws -> AnalysisOutcome {
        let payload: FoodPayload
        do {
            payload = try JSONDecoder().decode(FoodPayload.self, from: json)
        } catch {
            throw AnalysisError.invalidResponse
        }

        guard payload.foodDetected else { return .noFood }

        var items: [FoodItem] = []
        for food in payload.foods {
            guard food.calories >= 0 else { throw AnalysisError.invalidResponse }
            items.append(
                FoodItem(
                    name: food.name,
                    calories: food.calories,
                    proteinGrams: food.protein,
                    carbsGrams: food.carbs,
                    fatGrams: food.fat,
                    region: food.region
                )
            )
        }
        return CalorieAggregator.make(from: items)
    }
}

// MARK: - Wire DTOs

private nonisolated struct GeminiEnvelope: Decodable {
    let candidates: [Candidate]
    struct Candidate: Decodable { let content: Content }
    struct Content: Decodable { let parts: [Part] }
    struct Part: Decodable { let text: String? }
}

/// The structured payload the model returns (see contracts/gemini-response.schema.md).
nonisolated struct FoodPayload: Decodable {
    let foodDetected: Bool
    let foods: [Food]

    struct Food: Decodable {
        let name: String
        let calories: Int
        let protein: Double?
        let carbs: Double?
        let fat: Double?
        /// Optional, and decoded leniently: a malformed box must cost only that
        /// food's thumbnail, never the whole meal (FR-015 / FR-021).
        let box: Box?

        /// Edges on Gemini's 0-1000 normalized scale. Named rather than an array
        /// because the native form is `[ymin, xmin, ymax, xmax]` — y first — and
        /// reading that pair-swapped crops the wrong region silently.
        struct Box: Decodable {
            let ymin: Int
            let xmin: Int
            let ymax: Int
            let xmax: Int
        }

        /// nil when no box was reported, or when the reported one is unusable.
        var region: FoodRegion? {
            guard let box else { return nil }
            return FoodRegion(
                geminiTop: box.ymin, left: box.xmin, bottom: box.ymax, right: box.xmax
            )
        }

        private enum CodingKeys: String, CodingKey {
            case name, calories, protein, carbs, fat, box
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            calories = try container.decode(Int.self, forKey: .calories)
            protein = try? container.decodeIfPresent(Double.self, forKey: .protein)
            carbs = try? container.decodeIfPresent(Double.self, forKey: .carbs)
            fat = try? container.decodeIfPresent(Double.self, forKey: .fat)
            // `try?` on purpose: a box missing an edge or carrying the wrong type
            // degrades to no thumbnail rather than failing the whole response.
            box = try? container.decodeIfPresent(Box.self, forKey: .box)
        }
    }
}
