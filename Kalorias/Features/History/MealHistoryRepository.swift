//
//  MealHistoryRepository.swift
//  Kalorias
//
//  Write-side boundary for meal history (constitution Principle V). Owns the
//  SwiftData ModelContext and the ImageStore, and holds the title/mapping logic.
//  The list UI reads reactively via `@Query`; this type handles saves.
//

import Foundation
import SwiftData
import UIKit

/// Called on a successful analysis to persist a meal (feature 002 → 003).
@MainActor
protocol MealRecording {
    func record(image: UIImage?, analysis: CalorieAnalysis, date: Date) async
}

@MainActor
@Observable
final class MealHistoryRepository: MealRecording {
    private let context: ModelContext
    private let imageStore: any ImageStoring

    init(context: ModelContext, imageStore: any ImageStoring = DiskImageStore()) {
        self.context = context
        self.imageStore = imageStore
    }

    func record(image: UIImage?, analysis: CalorieAnalysis, date: Date) async {
        let id = UUID()
        var imageFileName = ""
        if let image {
            imageFileName = (try? await imageStore.save(image, id: id)) ?? ""
        }

        let entry = MealEntry(
            id: id,
            capturedAt: date,
            title: MealTitle.make(from: analysis.items),
            totalCalories: analysis.totalCalories,
            foods: analysis.items.map(StoredFood.init(from:)),
            imageFileName: imageFileName
        )
        context.insert(entry)
        try? context.save()
    }

    /// Newest-first fetch (the list UI uses `@Query`; this supports tests/other callers).
    func entries() -> [MealEntry] {
        let descriptor = FetchDescriptor<MealEntry>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
