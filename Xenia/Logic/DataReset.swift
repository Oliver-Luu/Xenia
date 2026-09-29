//
//  DataReset.swift
//  Xenia
//
//  The destructive "start over" actions offered in Settings, kept out of the
//  view so they can be tested against a real context.
//

import Foundation
import SwiftData

enum DataReset {

    /// Deletes every saved tip. Places and categories are untouched.
    @MainActor
    static func clearHistory(in context: ModelContext) {
        deleteAll(TipRecord.self, in: context)
        try? context.save()
    }

    /// Deletes every saved place and every place group. History is untouched
    /// (records are denormalized), categories stay.
    @MainActor
    static func clearPlaces(in context: ModelContext) {
        deleteAll(Restaurant.self, in: context)
        deleteAll(PlaceGroup.self, in: context)
        try? context.save()
    }

    /// Deletes every category (cascading its rules and ratings) and re-seeds the
    /// starter set. Saved places lose their category link and fall back to "no
    /// category" until reassigned.
    @MainActor
    static func resetCategories(in context: ModelContext) {
        deleteAll(TipCategory.self, in: context)
        try? context.save()
        SeedData.installIfNeeded(in: context)
    }

    /// Wipes everything the user has built — places, groups, history, categories
    /// (re-seeded to the starter set), and the Recently Deleted archive. App
    /// preferences (currency, units, rounding, tip-entry mode) are left alone.
    @MainActor
    static func resetEverything(in context: ModelContext) {
        deleteAll(TipRecord.self, in: context)
        deleteAll(Restaurant.self, in: context)
        deleteAll(PlaceGroup.self, in: context)
        deleteAll(TipCategory.self, in: context)
        deleteAll(DeletedItem.self, in: context)
        try? context.save()
        SeedData.installIfNeeded(in: context)
    }

    /// Puts every starter category's arrival-reminder delay back to its default.
    /// Categories the user added themselves are left alone.
    @MainActor
    static func resetReminderTiming(in context: ModelContext) {
        let categories = (try? context.fetch(FetchDescriptor<TipCategory>())) ?? []
        for category in categories {
            if let minutes = SeedData.defaultReminderMinutes(forCategoryNamed: category.name) {
                category.arrivalReminderMinutes = minutes
            }
        }
        try? context.save()
    }

    @MainActor
    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<T>())) ?? []
        for item in all { context.delete(item) }
    }
}
