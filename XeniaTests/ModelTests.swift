//
//  ModelTests.swift
//  XeniaTests
//
//  Exercises the SwiftData models, seeding, and per-place override behavior
//  against a real in-memory container.
//

import Testing
import Foundation
import SwiftData
import CoreLocation
@testable import Xenia

@MainActor
struct ModelTests {

    private func makeContext() throws -> ModelContext {
        let schema = Persistence.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    @Test func seedingPopulatesCategoriesOnceOnly() throws {
        let context = try makeContext()

        SeedData.installIfNeeded(in: context)
        let firstPass = try context.fetch(FetchDescriptor<TipCategory>())
        #expect(firstPass.count > 3)
        #expect(firstPass.allSatisfy { !$0.rules.isEmpty || $0.name.contains("Takeout") == false })

        SeedData.installIfNeeded(in: context)
        let secondPass = try context.fetch(FetchDescriptor<TipCategory>())
        #expect(secondPass.count == firstPass.count)
    }

    @Test func seededRulesAreOrderedPositivesFirst() throws {
        let context = try makeContext()
        SeedData.installIfNeeded(in: context)

        for category in try context.fetch(FetchDescriptor<TipCategory>()) where category.rules.count > 1 {
            let deltas = category.sortedRules.map(\.deltaPercent)
            #expect(deltas == deltas.sorted(by: >),
                    "\(category.name) rules should run from the biggest bump to the biggest penalty")
        }
    }

    @Test func seededCategoriesHaveRatingDimensions() throws {
        let context = try makeContext()
        SeedData.installIfNeeded(in: context)
        let categories = try context.fetch(FetchDescriptor<TipCategory>())

        let sitDown = try #require(categories.first { $0.name.contains("Sit-Down") })
        #expect(sitDown.sortedRatingDimensions.map(\.name) == ["Service", "Food", "Atmosphere"])
        #expect(sitDown.sortedRatingDimensions.allSatisfy { $0.maxScore == 5 && $0.neutralScore == 3 })

        let takeout = try #require(categories.first { $0.name.contains("Takeout") })
        #expect(takeout.ratingDimensions.isEmpty)
    }

    @Test func restaurantUsesCategoryBaseUnlessOverridden() throws {
        let category = TipCategory(name: "Sit-Down", baseTipPercent: 18)
        let place = Restaurant(name: "Test Diner", category: category)
        #expect(place.effectiveBaseTipPercent == 18)

        place.baseTipOverride = 25
        #expect(place.effectiveBaseTipPercent == 25)
    }

    @Test func disabledRulesAreFilteredFromActiveRules() throws {
        let category = TipCategory(name: "Bar")
        let keep = AdjustmentRule(title: "Craft cocktails", deltaPercent: 5, sortOrder: 0)
        let drop = AdjustmentRule(title: "Beer only", deltaPercent: -5, sortOrder: 1)
        keep.category = category
        drop.category = category
        category.rules = [keep, drop]

        let place = Restaurant(name: "Corner Pub", category: category)
        place.disabledRuleIDs = [drop.uuid]

        let active = place.activeRules
        #expect(active.count == 1)
        #expect(active.first?.title == "Craft cocktails")
    }

    @Test func seededCategoriesCarryArrivalReminderTiming() throws {
        let context = try makeContext()
        SeedData.installIfNeeded(in: context)
        let categories = try context.fetch(FetchDescriptor<TipCategory>())

        let sitDown = try #require(categories.first { $0.name.contains("Sit-Down") })
        let cafe = try #require(categories.first { $0.name.contains("Café") })
        let delivery = try #require(categories.first { $0.name.contains("Delivery") })

        #expect(sitDown.arrivalReminderMinutes > cafe.arrivalReminderMinutes)
        #expect(cafe.arrivalReminderMinutes > 0)
        #expect(delivery.arrivalReminderMinutes == 0)
    }

    @Test func clearHistoryLeavesPlacesAndRules() throws {
        let context = try makeContext()
        SeedData.installIfNeeded(in: context)
        context.insert(Restaurant(name: "Keep me"))
        context.insert(TipRecord(placeName: "A", categoryName: "B", billAmount: 10, tipPercent: 20, tipAmount: 2, total: 12))
        try context.save()

        DataReset.clearHistory(in: context)

        #expect(try context.fetch(FetchDescriptor<TipRecord>()).isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<Restaurant>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<TipCategory>()) > 0)
    }

    @Test func clearPlacesLeavesHistoryAndCategories() throws {
        let context = try makeContext()
        SeedData.installIfNeeded(in: context)
        let group = PlaceGroup(name: "G")
        context.insert(group)
        let place = Restaurant(name: "Bye")
        place.group = group
        context.insert(place)
        context.insert(TipRecord(placeName: "A", categoryName: "B", billAmount: 10, tipPercent: 20, tipAmount: 2, total: 12))
        try context.save()

        DataReset.clearPlaces(in: context)

        #expect(try context.fetch(FetchDescriptor<Restaurant>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PlaceGroup>()).isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<TipRecord>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<TipCategory>()) > 0)
    }

    @Test func resetEverythingWipesDataAndReseedsCategories() throws {
        let context = try makeContext()
        SeedData.installIfNeeded(in: context)
        let seededCount = try context.fetchCount(FetchDescriptor<TipCategory>())

        let group = PlaceGroup(name: "G")
        context.insert(group)
        let place = Restaurant(name: "Bye")
        place.group = group
        context.insert(place)
        context.insert(TipRecord(placeName: "A", categoryName: "B", billAmount: 10, tipPercent: 20, tipAmount: 2, total: 12))
        context.insert(TipCategory(name: "My Speakeasy"))
        context.insert(DeletedItem(kind: .place, title: "Old", subtitle: "", payload: Data()))
        try context.save()

        DataReset.resetEverything(in: context)

        #expect(try context.fetch(FetchDescriptor<Restaurant>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PlaceGroup>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TipRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<DeletedItem>()).isEmpty)
        // Categories are wiped then re-seeded back to exactly the starter set.
        #expect(try context.fetchCount(FetchDescriptor<TipCategory>()) == seededCount)
        #expect(try !context.fetch(FetchDescriptor<TipCategory>()).contains { $0.name == "My Speakeasy" })
    }

    @Test func resetReminderTimingRestoresSeedDefaultsOnly() throws {
        let context = try makeContext()
        SeedData.installIfNeeded(in: context)

        let cafe = try #require(
            try context.fetch(FetchDescriptor<TipCategory>()).first { $0.name.contains("Café") }
        )
        let seededCafe = cafe.arrivalReminderMinutes
        cafe.arrivalReminderMinutes = 99

        let custom = TipCategory(name: "My Speakeasy")
        custom.arrivalReminderMinutes = 33
        context.insert(custom)
        try context.save()

        DataReset.resetReminderTiming(in: context)

        #expect(cafe.arrivalReminderMinutes == seededCafe)
        #expect(custom.arrivalReminderMinutes == 33)   // user-made category untouched
    }

    @Test func resetCategoriesRestoresDefaultsAndUnlinksPlaces() throws {
        let context = try makeContext()
        SeedData.installIfNeeded(in: context)
        let firstCount = try context.fetchCount(FetchDescriptor<TipCategory>())
        let category = try #require(try context.fetch(FetchDescriptor<TipCategory>()).first)
        let place = Restaurant(name: "Linked", category: category)
        context.insert(place)
        try context.save()

        DataReset.resetCategories(in: context)

        #expect(try context.fetchCount(FetchDescriptor<TipCategory>()) == firstCount)
        let survivor = try #require(try context.fetch(FetchDescriptor<Restaurant>()).first)
        #expect(survivor.category == nil)
    }

    @Test func customRatingsAndRulesFollowThePlace() throws {
        let context = try makeContext()

        let category = TipCategory(name: "Sit-Down", baseTipPercent: 18)
        let service = RatingDimension(name: "Service", sortOrder: 0)
        service.category = category
        category.ratingDimensions = [service]
        let houseRule = AdjustmentRule(title: "Weekend", deltaPercent: 3, sortOrder: 0)
        houseRule.category = category
        category.rules = [houseRule]
        context.insert(category)

        let place = Restaurant(name: "Jang Su Jang", category: category)
        context.insert(place)

        let wine = RatingDimension(name: "Banchan", sortOrder: 0)
        wine.restaurant = place
        place.customRatingDimensions.append(wine)
        context.insert(wine)

        let regulars = AdjustmentRule(title: "They know us", deltaPercent: 2, sortOrder: 0)
        regulars.restaurant = place
        place.customRules.append(regulars)
        context.insert(regulars)
        try context.save()

        #expect(place.allRatingDimensions.map(\.name) == ["Service", "Banchan"])
        #expect(place.activeRules.map(\.title) == ["Weekend", "They know us"])

        // Skipping a category rule still leaves the custom one.
        place.disabledRuleIDs = [houseRule.uuid]
        #expect(place.activeRules.map(\.title) == ["They know us"])
    }

    @Test func deletingAPlaceRemovesItsCustomRatingsAndRules() throws {
        let context = try makeContext()

        let place = Restaurant(name: "Corner Spot")
        context.insert(place)
        let dim = RatingDimension(name: "Parking")
        dim.restaurant = place
        place.customRatingDimensions.append(dim)
        context.insert(dim)
        let rule = AdjustmentRule(title: "Cash discount", deltaPercent: -1)
        rule.restaurant = place
        place.customRules.append(rule)
        context.insert(rule)
        try context.save()

        context.delete(place)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<RatingDimension>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<AdjustmentRule>()).isEmpty)
    }

    @Test func deletingACategoryKeepsAPlacesOwnCustomRules() throws {
        let context = try makeContext()

        let category = TipCategory(name: "Bar")
        context.insert(category)
        let place = Restaurant(name: "The Snug", category: category)
        context.insert(place)
        let rule = AdjustmentRule(title: "Bartender's pick", deltaPercent: 4)
        rule.restaurant = place
        place.customRules.append(rule)
        context.insert(rule)
        try context.save()

        context.delete(category)
        try context.save()

        let survivor = try #require(try context.fetch(FetchDescriptor<Restaurant>()).first)
        #expect(survivor.sortedCustomRules.map(\.title) == ["Bartender's pick"])
    }

    @Test func matcherPicksClosestPlaceWithinThreshold() throws {
        let here = CLLocation(latitude: 40.7295, longitude: -73.9965)

        let onSite = Restaurant(name: "On Site",
                                coordinate: CLLocationCoordinate2D(latitude: 40.7295, longitude: -73.9965))
        let blockAway = Restaurant(name: "Block Away",
                                   coordinate: CLLocationCoordinate2D(latitude: 40.7305, longitude: -73.9965))
        let noCoord = Restaurant(name: "Unknown")

        let match = RestaurantMatcher.closest(to: here, among: [blockAway, onSite, noCoord])
        #expect(match?.restaurant.name == "On Site")

        let farOnly = RestaurantMatcher.closest(to: here, among: [blockAway], threshold: 50)
        #expect(farOnly == nil)
    }

    @Test func deletingAGroupLeavesItsPlaces() throws {
        let context = try makeContext()
        let group = PlaceGroup(name: "Downtown")
        context.insert(group)
        let place = Restaurant(name: "Corner Bistro")
        place.group = group
        context.insert(place)
        try context.save()

        context.delete(group)
        try context.save()

        let survivor = try #require(try context.fetch(FetchDescriptor<Restaurant>()).first)
        #expect(survivor.name == "Corner Bistro")
        #expect(survivor.group == nil)
    }

    @Test func restaurantFavoriteAndVisitCountDefaults() throws {
        let place = Restaurant(name: "New Spot")
        #expect(place.isFavorite == false)
        #expect(place.visitCount == 0)
        place.isFavorite = true
        place.visitCount += 1
        #expect(place.isFavorite && place.visitCount == 1)
    }

    @Test func tipRecordKeepsRatingOrder() throws {
        let record = TipRecord(
            placeName: "Lunetta", categoryName: "Sit-Down",
            billAmount: 80, tipPercent: 20, tipAmount: 16, total: 96,
            partySize: 2,
            ratings: [
                RatingSnapshot(name: "Service", score: 5, outOf: 5),
                RatingSnapshot(name: "Food", score: 4, outOf: 5),
            ]
        )
        #expect(record.perPersonTotal == 48)
        #expect(record.ratingScores.map(\.name) == ["Service", "Food"])
        #expect(record.ratingScores.first?.outOf == 5)
    }
}
