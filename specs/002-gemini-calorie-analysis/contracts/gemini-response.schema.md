# Contract: Gemini structured response

The single external contract in this feature. `GeminiCalorieService` sends the
photo to Gemini's `generateContent` with a **response schema**, so the model must
return JSON matching this shape. The app decodes it into wire DTOs, then maps to
domain types (see data-model.md). If the payload does not conform, it is an
`AnalysisError.invalidResponse` (FR-004) — never shown as a total.

## Request (shape, not literal code)

- Endpoint: `POST /v1beta/models/gemini-2.5-flash:generateContent?key=<GEMINI_API_KEY>`
- Body:
  - `contents[0].parts`: `{ inline_data: { mime_type: "image/jpeg", data: <base64 image> } }`
    and a text part prompting: identify each food and estimate calories and
    macros; return an empty `foods` array with `foodDetected=false` if no food is
    visible.
  - `generationConfig.responseMimeType`: `"application/json"`
  - `generationConfig.responseSchema`: the schema below.

## Response JSON schema (what Gemini returns)

```json
{
  "type": "object",
  "properties": {
    "foodDetected": { "type": "boolean" },
    "foods": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "name":     { "type": "string" },
          "calories": { "type": "integer", "minimum": 0 },
          "protein":  { "type": "number", "minimum": 0 },
          "carbs":    { "type": "number", "minimum": 0 },
          "fat":      { "type": "number", "minimum": 0 }
        },
        "required": ["name", "calories"],
        "propertyOrdering": ["name", "calories", "protein", "carbs", "fat"]
      }
    }
  },
  "required": ["foodDetected", "foods"],
  "propertyOrdering": ["foodDetected", "foods"]
}
```

## Example — success

```json
{
  "foodDetected": true,
  "foods": [
    { "name": "Grilled chicken breast", "calories": 280, "protein": 52, "carbs": 0, "fat": 6 },
    { "name": "White rice", "calories": 240, "protein": 4, "carbs": 53, "fat": 0 },
    { "name": "Steamed broccoli", "calories": 55, "protein": 4, "carbs": 11, "fat": 1 }
  ]
}
```

App-derived total = 280 + 240 + 55 = **575 kcal** (computed, not taken from the wire).

## Example — no food

```json
{ "foodDetected": false, "foods": [] }
```

→ `AnalysisOutcome.noFood` (FR-012), shown as "no food detected", not 0 kcal.

## Decoding & validation rules

- `name` and `calories` are required per food; `protein`/`carbs`/`fat` optional
  (map to `nil` when absent — FR-008).
- Negative `calories` or a missing required field ⇒ `invalidResponse`.
- The displayed total is **always** `Σ foods.calories` (FR-006); any wire-level
  total is ignored.
- An empty `foods` (or `foodDetected=false`) ⇒ `noFood`, regardless of any other
  field.
