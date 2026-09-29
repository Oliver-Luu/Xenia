//
//  PreviewData.swift
//  Xenia
//
//  In-memory SwiftData container with sample content for Xcode Previews.
//

import Foundation
import SwiftData
import CoreLocation

@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let schema = Persistence.schema
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        SeedData.installIfNeeded(in: context)

        let categories = (try? context.fetch(FetchDescriptor<TipCategory>())) ?? []
        let sitDown = categories.first { $0.name.contains("Sit-Down") }
        let cafe = categories.first { $0.name.contains("Café") }
        let bar = categories.first { $0.name.contains("Bar") }

        let dateNight = PlaceGroup(name: "Date night", sortOrder: 0)
        context.insert(dateNight)

        let lunetta = Restaurant(
            name: "Lunetta Trattoria",
            streetAddress: "412 Mercer St",
            city: "New York",
            coordinate: CLLocationCoordinate2D(latitude: 40.7295, longitude: -73.9965),
            category: sitDown,
            note: "Ask for the window table"
        )
        lunetta.group = dateNight
        lunetta.isFavorite = true
        lunetta.visitCount = 5
        context.insert(lunetta)

        let wineRating = RatingDimension(name: "Wine list", maxScore: 5, neutralScore: 3, weight: 3, sortOrder: 0)
        wineRating.restaurant = lunetta
        lunetta.customRatingDimensions.append(wineRating)
        context.insert(wineRating)

        let regularBump = AdjustmentRule(title: "They know us", detail: "Regulars' thank-you", deltaPercent: 2, sortOrder: 0)
        regularBump.restaurant = lunetta
        lunetta.customRules.append(regularBump)
        context.insert(regularBump)

        let daily = Restaurant(
            name: "Daily Grind",
            streetAddress: "88 Bleecker St",
            city: "New York",
            coordinate: CLLocationCoordinate2D(latitude: 40.7268, longitude: -73.9990),
            category: cafe
        )
        daily.visitCount = 3
        daily.arrivalRemindersOn = false   // regular here, no need for a nudge
        context.insert(daily)

        let tavern = Restaurant(name: "The Half Step", streetAddress: "76 Ludlow St", category: bar)
        context.insert(tavern)

        context.insert(TipRecord(
            date: .now.addingTimeInterval(-86_400),
            placeName: "Lunetta Trattoria",
            categoryName: sitDown?.name ?? "Sit-Down Restaurant",
            billAmount: 84.50,
            tipPercent: 20,
            tipAmount: 16.90,
            total: 101.40,
            partySize: 2,
            ratings: [
                RatingSnapshot(name: "Service", score: 4, outOf: 5),
                RatingSnapshot(name: "Food", score: 5, outOf: 5),
                RatingSnapshot(name: "Atmosphere", score: 4, outOf: 5),
            ]
        ))
        context.insert(TipRecord(
            date: .now.addingTimeInterval(-3 * 86_400),
            placeName: "Daily Grind",
            categoryName: cafe?.name ?? "Café / Coffee Shop",
            billAmount: 11.25,
            tipPercent: 15,
            tipAmount: 1.70,
            total: 12.95
        ))

        try? context.save()
        return container
    }()
}
