//
//  KaloriasApp.swift
//  Kalorias
//
//  Created by Juan Quispe Ticona on 24/07/2026.
//

import SwiftData
import SwiftUI

@main
struct KaloriasApp: App {
    @State private var router = Router()
    @State private var cameraPermission = CameraPermissionStore()
    @State private var history: MealHistoryRepository

    /// Composed here and owned for the process lifetime: the phase it resolves
    /// decides whether the authenticated shell is built at all, so it cannot be
    /// created by a view inside that shell (feature 010).
    ///
    /// It is handed the meal repository as its local-data boundary, so a
    /// confirmed account deletion can remove that account's rows and photos
    /// without the journey ever importing SwiftData (Principle V).
    @State private var journey: AppJourneyStore

    private let container: ModelContainer

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: MealEntry.self)
        } catch {
            // Unrecoverable: the local store could not be created.
            fatalError("Failed to create the SwiftData container: \(error)")
        }
        self.container = container
        let history = MealHistoryRepository(context: container.mainContext)
        _history = State(initialValue: history)
#if DEBUG
        // A launch argument can compose the journey over in-process doubles, so
        // any phase can be opened and reviewed. The type does not exist outside
        // a DEBUG build, so neither does this branch.
        let fixture = JourneyLaunchFixture.current()
        self.fixture = fixture
        _journey = State(
            initialValue: fixture?.makeStore(localData: history)
                ?? AppJourneyStore(localData: history)
        )
#else
        _journey = State(initialValue: AppJourneyStore(localData: history))
#endif
    }

#if DEBUG
    private let fixture: JourneyLaunchFixture?
#endif

    var body: some Scene {
        WindowGroup {
            content
        }
        .modelContainer(container)
    }

    private var content: some View {
        let root = RootView()
            .environment(router)
            .environment(cameraPermission)
            .environment(history)
            .environment(journey)
#if DEBUG
        return root.task {
            // The two failed states exist only after an attempt was refused.
            await fixture?.settle(journey)
        }
#else
        return root
#endif
    }
}
