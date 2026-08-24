//
//  CalorieAnalysisStore.swift
//  Kalorias
//
//  Owns the photo-analysis state machine (constitution Principle V). It runs the
//  injected `CalorieAnalyzing` in a cancelable Task; only one analysis runs at a
//  time (single-flight, FR-014). All network/decoding happens inside the
//  injected analyzer (off the main thread); this store only holds UI state.
//
//  THE RETRY GATE LIVES HERE, NOT IN THE BUTTON. After a rate limit, `retry()`
//  refuses until the cooldown expires — so the rule holds however the view is
//  driven, and a `disabled` modifier that gets refactored away cannot silently
//  reopen a path back to the same `429` (rule S2 / FR-020).
//
//  TIME IS INJECTED. The `now` seam is what lets the cooldown's behaviour be
//  asserted without a test that sleeps (Principle II). The `Task` that ticks
//  contains no logic — all of it is in `RetryCooldown`.
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

    /// Seconds left before retrying is allowed again; `0` when it already is.
    /// Drives the countdown on the retry button.
    private(set) var secondsUntilRetry: Int = 0

    /// Whether the user may retry right now.
    ///
    /// `false` while a rate-limit cooldown runs, and `false` for a rejected
    /// photo, whose bytes cannot succeed however many times they are sent
    /// (rule E3 / FR-019).
    var canRetry: Bool {
        if case .failed(.photoRejected) = state { return false }
        return secondsUntilRetry == 0
    }

    private let imageData: Data
    /// `nil` only for a photo rejected before it left the device — there is
    /// nothing to analyze, so there is no analyzer (see `init(rejectedPhoto:)`).
    private let analyzer: (any CalorieAnalyzing)?
    private let recorder: (any MealRecording)?
    private var task: Task<Void, Never>?
    private var cooldownTask: Task<Void, Never>?
    private let now: () -> Date

    init(
        imageData: Data,
        image: UIImage?,
        analyzer: any CalorieAnalyzing,
        recorder: (any MealRecording)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.imageData = imageData
        self.image = image
        self.analyzer = analyzer
        self.recorder = recorder
        self.now = now
    }

    /// A photo that never left the device: `AnalysisPhotoEncoder` could not fit
    /// it under the size cap even at its lowest quality.
    ///
    /// There is nothing to send, so no request happens — but the user deserves
    /// the same answer they would have got had the server refused it, and the
    /// same way out (Retake). The alternative the capture site used to take was
    /// to dismiss silently, which loses the user's photo with no explanation
    /// (FR-023).
    ///
    /// Constructed already failed, with no analyzer, so `start()` from
    /// `.onAppear` cannot overwrite the state and `retry()` cannot re-send bytes
    /// that were never sendable (rules S7–S9).
    init(rejectedPhoto image: UIImage?) {
        self.imageData = Data()
        self.image = image
        self.analyzer = nil
        self.recorder = nil
        self.now = Date.init
        self.state = .failed(.photoRejected)
    }

    /// Begin analysis. Single-flight: ignored (returns nil) while one is running.
    @discardableResult
    func start() -> Task<Void, Never>? {
        // No analyzer means the photo never left the device: the state is
        // already `.failed(.photoRejected)` and nothing may overwrite it.
        guard analyzer != nil else { return nil }
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
    ///
    /// A no-op while a cooldown runs. The gate is here rather than only on the
    /// button so it cannot be bypassed by any other route into this method.
    @discardableResult
    func retry() -> Task<Void, Never>? {
        guard canRetry else { return nil }
        task?.cancel()
        task = nil
        return start()
    }

    /// Cancel any in-flight analysis and end the flow (FR-002 / FR-015).
    func cancel() {
        task?.cancel()
        task = nil
        endCooldown()
    }

    private func run() async {
        guard let analyzer else { return }
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

        if case .failed(.rateLimited(let retryAfter)) = newState {
            beginCooldown(seconds: retryAfter)
        } else {
            // Any other outcome ends a cooldown that was still running — a
            // successful retry must not leave a countdown ticking behind the
            // result.
            endCooldown()
        }
    }

    // MARK: Cooldown (rules S1–S6)

    /// Start counting down; the button re-enables in place at zero, with no
    /// navigation (rule S3 / FR-020).
    private func beginCooldown(seconds: TimeInterval) {
        cooldownTask?.cancel()

        let cooldown = RetryCooldown(seconds: seconds, now: now())
        secondsUntilRetry = cooldown.secondsRemaining(at: now())

        // `[weak self]` is what makes this safe to leave running: the loop holds
        // no strong reference, so a store the user navigated away from
        // deallocates on schedule and the next tick ends the task on its own.
        // (A `deinit` cannot cancel it — `deinit` is nonisolated and this store
        // is `@MainActor`.)
        cooldownTask = Task { [weak self] in
            while !Task.isCancelled {
                // One second per tick, and one `Int` written per tick — the loop
                // holds no logic of its own, which is what keeps `RetryCooldown`
                // the only thing that needs testing.
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }

                let remaining = cooldown.secondsRemaining(at: self.now())
                self.secondsUntilRetry = remaining
                if remaining == 0 { return }
            }
        }
    }

    private func endCooldown() {
        cooldownTask?.cancel()
        cooldownTask = nil
        secondsUntilRetry = 0
    }
}
