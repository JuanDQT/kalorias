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
        _history = State(initialValue: MealHistoryRepository(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(cameraPermission)
                .environment(history)
        }
        .modelContainer(container)
    }
}
