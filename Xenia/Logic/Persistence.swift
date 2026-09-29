//
//  Persistence.swift
//  Xenia
//
//  One shared SwiftData container. The app scene and the background arrival
//  monitor both read from it, so it can't live inside the App struct.
//

import Foundation
import SwiftData

enum Persistence {
    static let schema = Schema([
        TipCategory.self,
        AdjustmentRule.self,
        RatingDimension.self,
        PlaceGroup.self,
        Restaurant.self,
        TipRecord.self,
        DeletedItem.self,
    ])

    @MainActor
    static let container: ModelContainer = {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // A store left by an older build that can't be migrated would crash
            // every launch — including the headless CoreLocation relaunches that
            // arrival reminders depend on. Move the incompatible store aside and
            // start fresh rather than becoming permanently unlaunchable.
            relocateStore(at: configuration.url, reason: error)
            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("Could not create ModelContainer even after resetting the store: \(error)")
            }
        }
    }()

    /// Renames the on-disk store (and its `-wal` / `-shm` sidecars) out of the
    /// way so a fresh one can be created. Non-destructive — the old files stay on
    /// disk under an `incompatible-…` name for manual recovery.
    private static func relocateStore(at url: URL, reason: Error) {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        let name = url.lastPathComponent
        let stamp = Int(Date().timeIntervalSince1970)
        for suffix in ["", "-wal", "-shm"] {
            let source = directory.appendingPathComponent(name + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = directory.appendingPathComponent("incompatible-\(stamp)-\(name + suffix)")
            try? fileManager.moveItem(at: source, to: destination)
        }
        print("Xenia: relocated an incompatible SwiftData store — \(reason)")
    }
}
