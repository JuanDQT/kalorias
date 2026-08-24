//
//  MealHistoryRepositoryTests.swift
//  KaloriasTests
//

import XCTest
import SwiftData
@testable import Kalorias

nonisolated final class MealHistoryRepositoryTests: XCTestCase {

    /// Returns the repository AND its container; the caller MUST keep the
    /// container alive for the duration of the test (the context is invalid
    /// once its container deallocates).
    @MainActor
    private func makeRepository() throws -> (MealHistoryRepository, ModelContainer) {
        let container = try ModelContainer(
            for: MealEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return (MealHistoryRepository(context: container.mainContext), container)
    }

    private func analysis(_ foods: [FoodItem]) -> CalorieAnalysis {
        CalorieAnalysis(items: foods, totalCalories: CalorieAggregator.total(of: foods))
    }

    @MainActor
    func testRecordInsertsEntryWithFoodsTotalAndTitle() async throws {
        let (repo, container) = try makeRepository()
        await repo.record(
            image: nil,
            analysis: analysis([FoodItem(name: "Apple", calories: 95, proteinGrams: 0.5)]),
            date: Date()
        )
        let entries = repo.entries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].totalCalories, 95)
        XCTAssertEqual(entries[0].title, "Apple")
        XCTAssertEqual(entries[0].foods.count, 1)
        XCTAssertEqual(entries[0].foods[0].protein, 0.5)
        _ = container
    }

    @MainActor
    func testSecondRecordCreatesDistinctEntry() async throws {
        let (repo, container) = try makeRepository()
        await repo.record(image: nil, analysis: analysis([FoodItem(name: "A", calories: 100)]), date: Date())
        await repo.record(image: nil, analysis: analysis([FoodItem(name: "B", calories: 200)]), date: Date())
        XCTAssertEqual(repo.entries().count, 2)
        _ = container
    }

    @MainActor
    func testEntriesAreNewestFirst() async throws {
        let (repo, container) = try makeRepository()
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        await repo.record(image: nil, analysis: analysis([FoodItem(name: "Older", calories: 100)]), date: older)
        await repo.record(image: nil, analysis: analysis([FoodItem(name: "Newer", calories: 200)]), date: newer)

        let entries = repo.entries()
        XCTAssertEqual(entries.first?.title, "Newer")
        XCTAssertEqual(entries.last?.title, "Older")
        _ = container
    }

    // MARK: Food regions (feature 006)

    @MainActor
    func testRegionsSurviveSaveAndFetch() async throws {
        let (repo, container) = try makeRepository()
        guard let region = FoodRegion(clampingX: 0.25, y: 0.5, width: 0.25, height: 0.2) else {
            return XCTFail("expected a valid region")
        }
        await repo.record(
            image: nil,
            analysis: analysis([FoodItem(name: "Pollo", calories: 320, region: region)]),
            date: Date()
        )

        let stored = repo.entries().first?.foods.first
        XCTAssertEqual(stored?.region, region)
        _ = container
    }

    /// A meal must save completely even when the analysis reported no boxes —
    /// regions are an enhancement, never a precondition (FR-021).
    @MainActor
    func testMealWithoutRegionsSavesNormally() async throws {
        let (repo, container) = try makeRepository()
        await repo.record(
            image: nil,
            analysis: analysis([FoodItem(name: "Arroz", calories: 210, proteinGrams: 4)]),
            date: Date()
        )

        let entry = repo.entries().first
        XCTAssertEqual(entry?.totalCalories, 210)
        XCTAssertEqual(entry?.foods.count, 1)
        XCTAssertNil(entry?.foods.first?.region)
        XCTAssertEqual(entry?.foods.first?.protein, 4)
        _ = container
    }

    /// The backward-compatibility guarantee that removed the need for a migration:
    /// JSON written before `region` existed must still decode (FR-017).
    func testFoodsJSONWrittenWithoutARegionKeyStillDecodes() throws {
        let legacy = Data("""
        [{"id":"7B7A0B62-1C6D-4B7B-9F1E-2A0E5F6C1D33","name":"Pollo","calories":320,"protein":31.5}]
        """.utf8)

        let decoded = try JSONDecoder().decode([StoredFood].self, from: legacy)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].name, "Pollo")
        XCTAssertEqual(decoded[0].calories, 320)
        XCTAssertNil(decoded[0].region, "a payload with no region key decodes as nil")
    }
}
