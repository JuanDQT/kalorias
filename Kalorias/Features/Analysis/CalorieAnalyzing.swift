//
//  CalorieAnalyzing.swift
//  Kalorias
//
//  The boundary that hides the calorie-analysis service from the store and the
//  UI (constitution Principle V). Injecting this makes both fully unit-testable
//  with a mock.
//
//  THIS PROTOCOL DID NOT CHANGE when the analysis moved from a direct AI-provider
//  call to the Kalorias backend, and that is the measure of whether the boundary
//  was drawn in the right place: the store, the views, persistence and every
//  store test carried on unmodified while the implementation behind it was
//  replaced wholesale.
//

import Foundation

protocol CalorieAnalyzing: Sendable {
    /// Analyze the given (JPEG) image data and return an outcome, or throw an
    /// `AnalysisError` on failure.
    func analyze(imageData: Data) async throws -> AnalysisOutcome
}
