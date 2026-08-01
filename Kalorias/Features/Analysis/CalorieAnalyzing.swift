//
//  CalorieAnalyzing.swift
//  Kalorias
//
//  The boundary that hides the calorie-analysis service (Gemini) from the store
//  and UI (constitution Principle V). Injecting this makes the store and views
//  fully unit-testable with a mock.
//

import Foundation

protocol CalorieAnalyzing: Sendable {
    /// Analyze the given (JPEG) image data and return an outcome, or throw an
    /// `AnalysisError` on failure.
    func analyze(imageData: Data) async throws -> AnalysisOutcome
}
