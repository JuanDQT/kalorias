//
//  AppSecrets.swift
//  Kalorias
//
//  Runtime access to secrets injected from the git-ignored
//  `Config/Secrets.xcconfig` via the app's Info.plist. The real key is never
//  committed (constitution Tech Constraints).
//

import Foundation

nonisolated enum AppSecrets {
    /// The Gemini API key, or an empty string when not configured.
    static var geminiAPIKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "GeminiAPIKey") as? String) ?? ""
    }

    /// The Gemini model id, defaulting to a sensible fast multimodal model.
    static var geminiModel: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "GeminiModel") as? String
        if let value, !value.isEmpty { return value }
        return "gemini-flash-latest"
    }

    /// Whether a non-empty API key is available.
    static var isConfigured: Bool { !geminiAPIKey.isEmpty }
}
