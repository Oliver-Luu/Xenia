//
//  DeletionArchiveTests.swift
//  XeniaTests
//
//  Archive → restore round-trips for every deletable type, plus purge and empty.
//

import Testing
import Foundation
import SwiftData
import CoreLocation
@testable import Xenia

@MainActor
struct DeletionArchiveTests {

    private func makeContext() throws -> ModelContext {
        let schema = Persistence.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func count<T: PersistentModel>(_ type: T.Type, in context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<T>())) ?? -1
    }

    // MARK: Place

    @Test func archivingAPlaceStoresOneItemAndRemovesTheRows() throws {
        let context = try makeContext()
        let category = TipCategory(name: "Bar")
        let group = PlaceGroup(name: "Downtown")
        context.insert(category); context.insert(group)
        let place = Restaurant(name: "The Half Step", category: category)
        place.group = group
        place.visitCount = 4
        context.insert(place)
        let rule = AdjustmentRule(title: "Regulars")
        rule.restaurant = place
        let dim = RatingDimension(name: "Vibe")
        dim.restaurant = place
        context.insert(rule); context.insert(dim)
        try context.save()

        DeletionArchive.archive(place, in: context)

        #expect(count(Restaurant.self, in: context) == 0)
        #expect(count(AdjustmentRule.self, in: context) == 0)   // cascade
        #expect(count(RatingDimension.self, in: context) == 0)  // cascade
        #expect(count(DeletedItem.self, in: context) == 1)
        #expect(count(TipCategory.self, in: context) == 1)      // untouched
        #expect(count(PlaceGroup.self, in: context) == 1)

        let item = try #require(try context.fetch(FetchDescriptor<DeletedItem>()).first)
        #expect(item.kind == .place)
        #expect(item.title == "The Half Step")
    }

    @Test func restoringAPlaceRebuildsScalarsLinksAndCustoms() throws {
        let context = try makeContext()
        let category = TipCategory(name: "Bar")
        let group = PlaceGroup(name: "Downtown")
        context.insert(category); context.insert(group)
        let place = Restaurant(name: "The Half Step", streetAddress: "76 Ludlow", city: "New York", category: category)
        place.group = group
        place.visitCount = 7
        place.isFavorite = true
        place.baseTipOverride = 22
        place.arrivalRemindersOn = false
        place.coordinate = .init(latitude: 40.7, longitude: -73.9)
        context.insert(place)
        let placeUUID = place.uuid
        let rule = AdjustmentRule(title: "Regulars", deltaPercent: 3, sortOrder: 1)
        rule.restaurant = place
        let dim = RatingDimension(name: "Vibe", sortOrder: 2)
        dim.restaurant = place
        context.insert(rule); context.insert(dim)
        try context.save()

        DeletionArchive.archive(place, in: context)
        let item = try #require(try context.fetch(FetchDescriptor<DeletedItem>()).first)
        #expect(DeletionArchive.restore(item, in: context) == .restored)

        #expect(count(DeletedItem.self, in: context) == 0)
        let restored = try #require(try context.fetch(FetchDescriptor<Restaurant>()).first)
        #expect(restored.uuid == placeUUID)
        #expect(restored.name == "The Half Step")
        #expect(restored.city == "New York")
        #expect(restored.visitCount == 7)
        #expect(restored.isFavorite)
        #expect(restored.baseTipOverride == 22)
        #expect(restored.arrivalRemindersOn == false)
        #expect(restored.hasCoordinate)
        #expect(restored.category?.name == "Bar")
        #expect(restored.group?.name == "Downtown")
        #expect(restored.sortedCustomRules.map(\.title) == ["Regulars"])
        #expect(restored.sortedCustomRatingDimensions.map(\.name) == ["Vibe"])
    }

    @Test func restoringAPlaceWhoseCategoryIsAlsoGoneLeavesItUncategorized() throws {
        let context = try makeContext()
        let category = TipCategory(name: "Bar")
        context.insert(category)
        let place = Restaurant(name: "The Half Step", category: category)
        context.insert(place)
        try context.save()

        DeletionArchive.archive(place, in: context)
        DeletionArchive.archive(category, in: context)

        let placeItem = try #require(
            try context.fetch(FetchDescriptor<DeletedItem>()).first { $0.kind == .place }
        )
        #expect(DeletionArchive.restore(placeItem, in: context) == .restored)
        let restored = try #require(try context.fetch(FetchDescriptor<Restaurant>()).first)
        #expect(restored.category == nil)
    }

    // MARK: Category

    @Test func archiveAndRestoreCategoryRebuildsChildrenAndRelinksFreeMembers() throws {
        let context = try makeContext()
        let category = TipCategory(name: "Sit-Down")
        context.insert(category)
        let rule = AdjustmentRule(title: "Great server", deltaPercent: 3)
        rule.category = category
        let dim = RatingDimension(name: "Food")
        dim.category = category
        context.insert(rule); context.insert(dim)

        let stillFree = Restaurant(name: "Lunetta", category: category)
        let reassigned = Restaurant(name: "Via Carota", category: category)
        context.insert(stillFree); context.insert(reassigned)
        try context.save()

        DeletionArchive.archive(category, in: context)
        // One member picks up a new category before the restore.
        let other = TipCategory(name: "Other")
        context.insert(other)
        try #require(try context.fetch(FetchDescriptor<Restaurant>()).first { $0.name == "Via Carota" })
            .category = other
        try context.save()

        let item = try #require(
            try context.fetch(FetchDescriptor<DeletedItem>()).first { $0.kind == .category }
        )
        #expect(DeletionArchive.restore(item, in: context) == .restored)

        let restored = try #require(
            try context.fetch(FetchDescriptor<TipCategory>()).first { $0.name == "Sit-Down" }
        )
        #expect(restored.sortedRules.map(\.title) == ["Great server"])
        #expect(restored.sortedRatingDimensions.map(\.name) == ["Food"])
        let lunetta = try #require(try context.fetch(FetchDescriptor<Restaurant>()).first { $0.name == "Lunetta" })
        let viaCarota = try #require(try context.fetch(FetchDescriptor<Restaurant>()).first { $0.name == "Via Carota" })
        #expect(lunetta.category?.name == "Sit-Down")   // was free → relinked
        #expect(viaCarota.category?.name == "Other")     // already had one → left alone
    }

    // MARK: Standalone rule / rating

    @Test func archiveAndRestoreACategoryRule() throws {
        let context = try makeContext()
        let category = TipCategory(name: "Café")
        context.insert(category)
        let rule = AdjustmentRule(title: "Latte art")
        rule.category = category
        context.insert(rule)
        try context.save()

        DeletionArchive.archive(rule, in: context)
        #expect(count(AdjustmentRule.self, in: context) == 0)

        let item = try #require(try context.fetch(FetchDescriptor<DeletedItem>()).first)
        #expect(item.kind == .rule)
        #expect(DeletionArchive.restore(item, in: context) == .restored)

        let restored = try #require(try context.fetch(FetchDescriptor<AdjustmentRule>()).first)
        #expect(restored.title == "Latte art")
        #expect(restored.category?.name == "Café")
    }

    @Test func restoringARuleWhoseOwnerIsGoneIsBlocked() throws {
        let context = try makeContext()
        let category = TipCategory(name: "Café")
        context.insert(category)
        let rule = AdjustmentRule(title: "Latte art")
        rule.category = category
        context.insert(rule)
        try context.save()

        DeletionArchive.archive(rule, in: context)
        DeletionArchive.archive(category, in: context)

        let ruleItem = try #require(
            try context.fetch(FetchDescriptor<DeletedItem>()).first { $0.kind == .rule }
        )
        let outcome = DeletionArchive.restore(ruleItem, in: context)
        guard case .blocked = outcome else {
            Issue.record("expected .blocked, got \(outcome)")
            return
        }
        #expect(count(AdjustmentRule.self, in: context) == 0)
        #expect(try context.fetch(FetchDescriptor<DeletedItem>()).contains { $0.kind == .rule })

        // Restoring the category first unblocks it.
        let catItem = try #require(
            try context.fetch(FetchDescriptor<DeletedItem>()).first { $0.kind == .category }
        )
        #expect(DeletionArchive.restore(catItem, in: context) == .restored)
        #expect(DeletionArchive.restore(ruleItem, in: context) == .restored)
        #expect(count(AdjustmentRule.self, in: context) == 1)
    }

    @Test func archiveAndRestoreAPlaceRating() throws {
        let context = try makeContext()
        let place = Restaurant(name: "Daily Grind")
        context.insert(place)
        let dim = RatingDimension(name: "Speed", weight: 3)
        dim.restaurant = place
        context.insert(dim)
        try context.save()

        DeletionArchive.archive(dim, in: context)
        let item = try #require(try context.fetch(FetchDescriptor<DeletedItem>()).first)
        #expect(item.kind == .rating)
        #expect(DeletionArchive.restore(item, in: context) == .restored)

        let restored = try #require(try context.fetch(FetchDescriptor<RatingDimension>()).first)
        #expect(restored.name == "Speed")
        #expect(restored.weight == 3)
        #expect(restored.restaurant?.name == "Daily Grind")
    }

    // MARK: History

    @Test func archiveAndRestoreHistoryPreservesRatingScores() throws {
        let context = try makeContext()
        let record = TipRecord(
            placeName: "Lunetta", categoryName: "Sit-Down",
            billAmount: 84.5, tipPercent: 20, tipAmount: 16.9, total: 101.4, partySize: 2,
            ratings: [RatingSnapshot(name: "Service", score: 4, outOf: 5)]
        )
        context.insert(record)
        try context.save()

        DeletionArchive.archive(record, in: context)
        #expect(count(TipRecord.self, in: context) == 0)

        let item = try #require(try context.fetch(FetchDescriptor<DeletedItem>()).first)
        #expect(DeletionArchive.restore(item, in: context) == .restored)

        let restored = try #require(try context.fetch(FetchDescriptor<TipRecord>()).first)
        #expect(restored.placeName == "Lunetta")
        #expect(restored.total == 101.4)
        #expect(restored.ratingScores == [RatingSnapshot(name: "Service", score: 4, outOf: 5)])
    }

    // MARK: Group

    @Test func archiveAndRestoreGroupRelinksOnlyUngroupedMembers() throws {
        let context = try makeContext()
        let group = PlaceGroup(name: "Date night")
        context.insert(group)
        let a = Restaurant(name: "A"); a.group = group
        let b = Restaurant(name: "B"); b.group = group
        context.insert(a); context.insert(b)
        try context.save()

        DeletionArchive.archive(group, in: context)
        #expect(a.group == nil && b.group == nil)   // nullify

        let other = PlaceGroup(name: "Other")
        context.insert(other)
        b.group = other
        try context.save()

        let item = try #require(try context.fetch(FetchDescriptor<DeletedItem>()).first { $0.kind == .group })
        #expect(DeletionArchive.restore(item, in: context) == .restored)

        #expect(a.group?.name == "Date night")
        #expect(b.group?.name == "Other")
    }

    // MARK: Purge / empty

    @Test func purgeExpiredDropsOnlyItemsPastRetention() throws {
        let context = try makeContext()
        for name in ["old", "fresh"] {
            let r = Restaurant(name: name)
            context.insert(r)
            DeletionArchive.archive(r, in: context)
        }
        let items = try context.fetch(FetchDescriptor<DeletedItem>())
        try #require(items.first { $0.title == "old" }).deletedAt = .now.addingTimeInterval(-31 * 24 * 3600)
        try context.save()

        DeletionArchive.purgeExpired(in: context)

        let remaining = try context.fetch(FetchDescriptor<DeletedItem>())
        #expect(remaining.map(\.title) == ["fresh"])
    }

    @Test func emptyRemovesEveryDeletedItem() throws {
        let context = try makeContext()
        for name in ["a", "b", "c"] {
            let r = Restaurant(name: name)
            context.insert(r)
            DeletionArchive.archive(r, in: context)
        }
        #expect(count(DeletedItem.self, in: context) == 3)

        DeletionArchive.empty(in: context)
        #expect(count(DeletedItem.self, in: context) == 0)
    }
}
