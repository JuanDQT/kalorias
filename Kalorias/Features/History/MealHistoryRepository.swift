//
//  MealHistoryRepository.swift
//  Kalorias
//
//  Write-side boundary for meal history (constitution Principle V). Owns the
//  SwiftData ModelContext and the ImageStore, and holds the title/mapping logic.
//  The list UI reads reactively via `@Query`; this type handles saves.
//
//  EVERY WRITE NEEDS AN OWNER, AND A MISSING ONE IS A REFUSAL (feature 010,
//  FR-042). Recording a meal with no `ownerUserID` would create exactly the
//  unowned row the model refuses to show anybody — data the user can never see
//  and can never delete. Better to record nothing and let the caller find out.
//
//  DELETION IS SCOPED TO ONE OWNER. `clearLocalData(ownedBy:)` removes that
//  account's rows and their image files and nothing else, so a second account on
//  the same phone survives the first one being deleted. It is idempotent,
//  because it runs inside a cleanup that a termination can interrupt.
//
//  ROWS FIRST, THEN FILES, AND THE FILE NAMES ARE CAPTURED BEFORE THE ROWS GO.
//  A file whose row is already gone is invisible garbage; a row whose file is
//  gone renders a broken thumbnail. Of the two orders, only one has a harmless
//  failure mode.
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

    /// The authenticated account rows are written for and read back under. Set
    /// by the journey whenever the active identity changes; `nil` outside a
    /// session, which makes recording impossible rather than anonymous.
    private(set) var activeUserID: String?

    init(
        context: ModelContext,
        imageStore: any ImageStoring = DiskImageStore(),
        activeUserID: String? = nil
    ) {
        self.context = context
        self.imageStore = imageStore
        self.activeUserID = activeUserID
    }

    /// Point the repository at an account. Called on sign-in, sign-out and after
    /// a confirmed deletion.
    func setActiveUser(_ userID: String?) {
        activeUserID = userID
    }

    func record(image: UIImage?, analysis: CalorieAnalysis, date: Date) async {
        // No owner, no row. An unowned meal is one nobody can see or delete.
        guard let ownerUserID = activeUserID else { return }

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
            imageFileName: imageFileName,
            ownerUserID: ownerUserID
        )
        context.insert(entry)
        try? context.save()
    }

    /// Newest-first fetch for the active account (the list UI uses `@Query`;
    /// this supports tests and other callers).
    ///
    /// With no active account this is empty rather than everything — the safe
    /// direction, and the same answer History and Progress give.
    func entries() -> [MealEntry] {
        guard let activeUserID else { return [] }
        return fetch(ownedBy: activeUserID)
    }

    private func fetch(ownedBy ownerUserID: String) -> [MealEntry] {
        // Filtered in the predicate, not after the fetch: the point is that the
        // other account's rows are never loaded.
        let descriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate { $0.ownerUserID == ownerUserID },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}

// MARK: - Account deletion

extension MealHistoryRepository: AccountLocalDataClearing {

    /// Remove one account's meals and their photos. Nothing else is touched —
    /// not another account's rows, and not the unowned legacy ones.
    func clearLocalData(ownedBy ownerUserID: String) async {
        let owned = fetch(ownedBy: ownerUserID)
        // Captured before the rows go: afterwards there is nothing left to ask.
        let imageNames = owned.map(\.imageFileName).filter { !$0.isEmpty }

        for entry in owned {
            context.delete(entry)
        }
        try? context.save()

        // Off the main actor, and safe to repeat: deleting a file that is
        // already gone is success.
        await imageStore.delete(named: imageNames)

        if activeUserID == ownerUserID {
            activeUserID = nil
        }
    }
}
