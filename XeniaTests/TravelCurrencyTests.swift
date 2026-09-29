//
//  TravelCurrencyTests.swift
//  XeniaTests
//
//  Currency is meant to follow where the user is; distance units are meant to
//  follow where they live. This covers the travelling half: what arriving
//  somewhere new should do, what it must never do, and what happens to money
//  already written down.
//
//  The decision is a pure function because the interesting sequences — land,
//  decline, fly on, fly home — are ones you cannot stage on a desk.
//

import Testing
import Foundation
import CoreLocation
import SwiftData
@testable import Xenia

struct CurrencySuggestionTests {

    private func suggestion(
        region: String?,
        override: String? = nil,
        travel: String? = nil,
        device: String? = "USD",
        declined: Set<String> = []
    ) -> Preferences.CurrencySuggestion {
        Preferences.currencySuggestion(
            forRegion: region,
            override: override,
            travelCurrency: travel,
            deviceCurrency: device,
            declinedRegions: declined
        )
    }

    // MARK: - Arriving somewhere new

    @Test func landingSomewhereThatSpendsDifferentMoneyAsksOnce() {
        #expect(suggestion(region: "JP") == .ask(region: "JP", currency: "JPY"))
        #expect(suggestion(region: "FR") == .ask(region: "FR", currency: "EUR"))
        #expect(suggestion(region: "GB") == .ask(region: "GB", currency: "GBP"))
    }

    @Test func beingHomeAsksNothing() {
        #expect(suggestion(region: "US") == .none)
    }

    @Test func aCountryOnTheSameMoneyAsksNothing() {
        // Home is France; Germany spends the same euros.
        #expect(suggestion(region: "DE", device: "EUR") == .none)
    }

    @Test func alreadySwitchedMeansNothingToSay() {
        #expect(suggestion(region: "JP", travel: "JPY") == .none)
    }

    // MARK: - Coming home

    @Test func comingHomeDropsTheTravelCurrencyWithoutAsking() {
        // Going back to the currency they never had to opt into isn't news.
        #expect(suggestion(region: "US", travel: "JPY") == .revertToHome)
    }

    @Test func comingHomeWithNothingToUndoIsSilent() {
        #expect(suggestion(region: "US", travel: nil) == .none)
    }

    // MARK: - Respecting an answer

    @Test func aDeclinedCountryIsNotAskedAgain() {
        #expect(suggestion(region: "JP", declined: ["JP"]) == .none)
    }

    @Test func decliningOneCountryDoesNotSilenceTheNext() {
        #expect(suggestion(region: "FR", declined: ["JP"]) == .ask(region: "FR", currency: "EUR"))
    }

    @Test func anExplicitChoiceStopsTravelFromAskingAtAll() {
        // Picking a currency by hand is a standing instruction, not a default.
        #expect(suggestion(region: "JP", override: "USD") == .none)
        #expect(suggestion(region: "JP", override: "USD", travel: "EUR") == .none)
        #expect(suggestion(region: "US", override: "JPY", travel: "EUR") == .none)
    }

    // MARK: - Not knowing where we are

    @Test func anUnknownLocationChangesNothing() {
        #expect(suggestion(region: nil) == .none)
        #expect(suggestion(region: nil, travel: "JPY") == .none,
                "a failed lookup must not strand or reset anyone")
    }

    @Test func aRegionWithNoCurrencyChangesNothing() {
        // Antarctica has no currency of its own.
        #expect(suggestion(region: "AQ") == .none)
        #expect(suggestion(region: "ZZ") == .none)
    }

    // MARK: - The mapping itself

    @Test func countriesMapToTheMoneySpentThere() {
        #expect(Preferences.currencyCode(forRegion: "US") == "USD")
        #expect(Preferences.currencyCode(forRegion: "JP") == "JPY")
        #expect(Preferences.currencyCode(forRegion: "FR") == "EUR")
        #expect(Preferences.currencyCode(forRegion: "DE") == "EUR")
        #expect(Preferences.currencyCode(forRegion: "GB") == "GBP")
        #expect(Preferences.currencyCode(forRegion: "CH") == "CHF")
        #expect(Preferences.currencyCode(forRegion: "KW") == "KWD")
    }
}

// MARK: - Which currency wins

struct CurrencyPrecedenceTests {

    @Test func anExplicitChoiceOutranksEverything() {
        #expect(Preferences.resolveCurrencyCode(
            override: "CHF", travelCurrency: "JPY", deviceCurrency: "USD"
        ) == "CHF")
    }

    @Test func anAcceptedTravelCurrencyOutranksTheDevice() {
        #expect(Preferences.resolveCurrencyCode(
            override: nil, travelCurrency: "JPY", deviceCurrency: "USD"
        ) == "JPY", "the whole point: abroad, prices read in local money")
    }

    @Test func theDeviceIsTheRestingState() {
        #expect(Preferences.resolveCurrencyCode(
            override: nil, travelCurrency: nil, deviceCurrency: "EUR"
        ) == "EUR")
        #expect(Preferences.resolveCurrencyCode(
            override: nil, travelCurrency: nil, deviceCurrency: nil
        ) == "USD")
    }
}

// MARK: - Answering the prompt

@MainActor
@Suite(.serialized)
struct TravelCurrencyPreferenceTests {

    private func withCleanPreferences(_ body: () throws -> Void) rethrows {
        let preferences = Preferences.shared
        let savedTravel = preferences.travelCurrencyCode
        let savedDeclined = preferences.declinedCurrencyRegions
        defer {
            preferences.travelCurrencyCode = savedTravel
            preferences.declinedCurrencyRegions = savedDeclined
        }
        preferences.travelCurrencyCode = nil
        preferences.declinedCurrencyRegions = []
        try body()
    }

    @Test func acceptingSwitchesTheCurrencyInEffect() throws {
        try withCleanPreferences {
            let preferences = Preferences.shared
            let savedOverride = preferences.currencyCode
            defer { preferences.currencyCode = savedOverride }
            preferences.currencyCode = nil

            preferences.acceptTravelCurrency("JPY", forRegion: "JP")
            #expect(preferences.travelCurrencyCode == "JPY")
            #expect(preferences.resolvedCurrencyCode == "JPY")
            #expect(Format.currencySymbol() == "¥")
        }
    }

    @Test func decliningIsRememberedForThatCountryOnly() throws {
        try withCleanPreferences {
            let preferences = Preferences.shared
            preferences.declineTravelCurrency(forRegion: "JP")

            #expect(preferences.declinedCurrencyRegions.contains("JP"))
            #expect(preferences.travelCurrencyCode == nil, "declining changes nothing on screen")
            #expect(!preferences.declinedCurrencyRegions.contains("FR"))
        }
    }

    @Test func acceptingAfterDecliningForgetsTheDecline() throws {
        try withCleanPreferences {
            let preferences = Preferences.shared
            preferences.declineTravelCurrency(forRegion: "JP")
            preferences.acceptTravelCurrency("JPY", forRegion: "JP")

            #expect(!preferences.declinedCurrencyRegions.contains("JP"),
                    "a later yes shouldn't leave a stale no behind")
        }
    }

    @Test func comingHomeClearsTheTravelCurrency() throws {
        try withCleanPreferences {
            let preferences = Preferences.shared
            preferences.acceptTravelCurrency("JPY", forRegion: "JP")
            preferences.revertToHomeCurrency()
            #expect(preferences.travelCurrencyCode == nil)
        }
    }

    @Test func declinesSurviveARelaunch() throws {
        try withCleanPreferences {
            Preferences.shared.declineTravelCurrency(forRegion: "JP")
            // Preferences mirrors to UserDefaults so the answer outlives the run.
            let stored = UserDefaults.standard.stringArray(forKey: "prefDeclinedCurrencyRegions")
            #expect(stored?.contains("JP") == true)
        }
    }
}

// MARK: - Money already written down

@MainActor
@Suite(.serialized)
struct RecordedCurrencyTests {

    private func makeContext() throws -> ModelContext {
        let schema = Persistence.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func record(
        _ place: String,
        tip: Double,
        currency: String,
        daysAgo: Double = 0
    ) -> TipRecord {
        TipRecord(
            date: Date().addingTimeInterval(-daysAgo * 86_400),
            placeName: place,
            categoryName: "Sit-Down",
            billAmount: tip * 5,
            tipPercent: 20,
            tipAmount: tip,
            total: tip * 6,
            currencyCode: currency
        )
    }

    @Test func aSavedTipRemembersWhatItWasPaidIn() throws {
        let preferences = Preferences.shared
        let saved = preferences.currencyCode
        defer { preferences.currencyCode = saved }

        preferences.currencyCode = "JPY"
        let tokyo = TipRecord(
            placeName: "寿司 さいとう", categoryName: "Sit-Down",
            billAmount: 30_000, tipPercent: 10, tipAmount: 3_000, total: 33_000
        )
        #expect(tokyo.currencyCode == "JPY", "a tip stamps the money it was paid in")

        // Flying home must not rewrite history.
        preferences.currencyCode = "USD"
        #expect(tokyo.currency == "JPY")
        #expect(Format.currency(tokyo.tipAmount, code: tokyo.currency).contains("3,000"))
        #expect(!Format.currency(tokyo.tipAmount, code: tokyo.currency).contains("$"))
    }

    @Test func aRecordFromBeforeTheStampFallsBackToHome() {
        let legacy = record("Old Diner", tip: 5, currency: "")
        #expect(legacy.currency == (Locale.current.currency?.identifier ?? "USD"),
                "unknown is better guessed as home than as wherever the user stands today")
    }

    @Test func totalsAreKeptApartByCurrency() {
        let records = [
            record("Cafe", tip: 4, currency: "USD", daysAgo: 1),
            record("Diner", tip: 6, currency: "USD", daysAgo: 2),
            record("寿司", tip: 3_000, currency: "JPY", daysAgo: 5),
        ]
        let totals = TipRecord.totalsByCurrency(records)

        #expect(totals.count == 2)
        #expect(totals.first(where: { $0.currency == "USD" })?.total == 10)
        #expect(totals.first(where: { $0.currency == "JPY" })?.total == 3_000)
        // Adding them would produce 3010 of nothing at all.
        #expect(!totals.contains { $0.total == 3_010 })
    }

    @Test func theMostRecentlyUsedCurrencyLeads() {
        let records = [
            record("寿司", tip: 3_000, currency: "JPY", daysAgo: 10),
            record("Cafe", tip: 4, currency: "USD", daysAgo: 1),
        ]
        #expect(TipRecord.totalsByCurrency(records).first?.currency == "USD")
    }

    @Test func anEmptyHistoryTotalsNothing() {
        #expect(TipRecord.totalsByCurrency([]).isEmpty)
    }

    @Test func deletingAndRestoringATipKeepsItsCurrency() throws {
        let context = try makeContext()
        let tokyo = record("寿司 さいとう", tip: 3_000, currency: "JPY")
        context.insert(tokyo)
        try context.save()

        let archived = try #require(DeletionArchive.archive(tokyo, in: context))
        context.delete(tokyo)
        try context.save()

        _ = DeletionArchive.restore(archived, in: context)
        try context.save()

        let restored = try #require(
            try context.fetch(FetchDescriptor<TipRecord>()).first
        )
        #expect(restored.currency == "JPY",
                "a trip through the bin must not re-price a tip in today's money")
    }
}

// MARK: - Turning a fix into a country

/// The one part that talks to Apple's servers. Needs a network connection; a
/// failure here is either a genuine regression or an offline machine, and the
/// messages say which to check.
@MainActor
@Suite(.serialized)
struct ReverseGeocodingTests {

    private func region(_ latitude: Double, _ longitude: Double) async -> String? {
        await TravelCurrency.regionCode(
            at: CLLocation(latitude: latitude, longitude: longitude)
        )
    }

    @Test func wellKnownPlacesResolveToTheirCountry() async {
        #expect(await region(35.6812, 139.7671) == "JP", "Tokyo — or the network is down")
        #expect(await region(48.8566, 2.3522) == "FR", "Paris — or the network is down")
        #expect(await region(40.7580, -73.9855) == "US", "New York — or the network is down")
    }

    @Test func aCoordinateInTheOceanResolvesToNothingRatherThanGuessing() async {
        // Middle of the South Pacific. A wrong guess here would switch someone's
        // currency on a flight.
        #expect(await region(-40, -140) == nil)
    }

    @Test func theWholeChainTurnsAFixIntoTheRightPrompt() async {
        // Tokyo, for a user who lives in the US and has chosen nothing by hand.
        let tokyo = try? await region(35.6812, 139.7671)
        let suggestion = Preferences.currencySuggestion(
            forRegion: tokyo ?? nil,
            override: nil,
            travelCurrency: nil,
            deviceCurrency: "USD",
            declinedRegions: []
        )
        #expect(suggestion == .ask(region: "JP", currency: "JPY"))
    }
}
