//
//  CalorieAnalysisStore.swift
//  Kalorias
//
//  Owns the photo-analysis state machine (constitution Principle V). It runs the
//  injected `CalorieAnalyzing` in a cancelable Task; only one analysis runs at a
//  time (single-flight, FR-014). All network/decoding happens inside the
//  injected analyzer (off the main thread); this store only holds UI state.
//

import Observation
import UIKit

/// Drives `AnalysisResultView`.
nonisolated enum AnalysisState: Equatable {
    case analyzing
    case result(CalorieAnalysis)
    case noFood
    case failed(AnalysisError)
}

@MainActor
@Observable
final class CalorieAnalysisStore: Identifiable {
    nonisolated let id = UUID()
    private(set) var state: AnalysisState = .analyzing

    /// The captured photo, for the result thumbnail (nil in tests).
    let image: UIImage?

    private let imageData: Data
    private let analyzer: any CalorieAnalyzing
    private let recorder: (any MealRecording)?
    private var task: Task<Void, Never>?

    init(
        imageData: Data,
        image: UIImage?,
        analyzer: any CalorieAnalyzing,
        recorder: (any MealRecording)? = nil
    ) {
        self.imageData = imageData
        self.image = image
        self.analyzer = analyzer
        self.recorder = recorder
    }

    /// Begin analysis. Single-flight: ignored (returns nil) while one is running.
    @discardableResult
    func start() -> Task<Void, Never>? {
        guard task == nil else { return nil }
        state = .analyzing
        let task = Task { [weak self] in
            guard let self else { return }
            await self.run()
        }
        self.task = task
        return task
    }

    /// Re-analyze the same photo (FR-013).
    @discardableResult
    func retry() -> Task<Void, Never>? {
        task?.cancel()
        task = nil
        return start()
    }

    /// Cancel any in-flight analysis and end the flow (FR-002 / FR-015).
    func cancel() {
        task?.cancel()
        task = nil
    }

    private func run() async {
        do {
            let outcome = try await analyzer.analyze(imageData: imageData)
            if Task.isCancelled { return }
            switch outcome {
            case .success(let analysis):
                finish(.result(analysis))
                // Persist the meal on success (feature 003); never on no-food/failed.
                await recorder?.record(image: image, analysis: analysis, date: Date())
            case .noFood:
                finish(.noFood)
            }
        } catch {
            if Task.isCancelled { return }
            finish(.failed(AnalysisError.from(error)))
        }
    }

    private func finish(_ newState: AnalysisState) {
        state = newState
        task = nil
    }
}
