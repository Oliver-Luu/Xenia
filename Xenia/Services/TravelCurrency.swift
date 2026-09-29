//
//  TravelCurrency.swift
//  Xenia
//
//  Currency follows where the user *is*, so a bill in Tokyo reads in yen. That's
//  the opposite of distance units, which follow where the user *lives* — see
//  `Format.usesMetric`. Someone from California in Paris wants euros on screen
//  and still thinks in feet.
//
//  The switch is never silent going out: landing somewhere new raises one prompt,
//  and a "not now" is remembered for that country so it isn't asked again.
//  Coming home is the exception — dropping a travel currency puts the user back
//  on the default they never opted into, which isn't worth a modal.
//

import Foundation
import CoreLocation
import MapKit

@MainActor
@Observable
final class TravelCurrency {

    static let shared = TravelCurrency()

    /// How far the user must move before it's worth asking the network where
    /// they are again. Countries are big; reverse geocoding on every fix would
    /// be a lot of traffic to learn nothing.
    static let recheckDistance: CLLocationDistance = 10_000

    /// The question owed to the user, if any. `RootView` presents it.
    private(set) var pendingPrompt: (region: String, currency: String)?

    private var lastCheckedCoordinate: CLLocation?

    private var preferences: Preferences { .shared }

    /// Looks up the country for a fix and acts on it: reverting quietly if the
    /// user is home again, or raising a prompt if they've arrived somewhere that
    /// spends different money.
    func check(_ location: CLLocation, force: Bool = false) async {
        if !force, let last = lastCheckedCoordinate,
           location.distance(from: last) < Self.recheckDistance {
            return
        }

        guard let region = await Self.regionCode(at: location) else { return }
        lastCheckedCoordinate = location

        switch Preferences.currencySuggestion(
            forRegion: region,
            override: preferences.currencyCode,
            travelCurrency: preferences.travelCurrencyCode,
            deviceCurrency: Locale.current.currency?.identifier,
            declinedRegions: preferences.declinedCurrencyRegions
        ) {
        case .none:
            pendingPrompt = nil
        case .revertToHome:
            preferences.revertToHomeCurrency()
            pendingPrompt = nil
        case let .ask(region, currency):
            pendingPrompt = (region: region, currency: currency)
        }
    }

    func acceptPending() {
        guard let prompt = pendingPrompt else { return }
        preferences.acceptTravelCurrency(prompt.currency, forRegion: prompt.region)
        pendingPrompt = nil
    }

    func declinePending() {
        guard let prompt = pendingPrompt else { return }
        preferences.declineTravelCurrency(forRegion: prompt.region)
        pendingPrompt = nil
    }

    /// The ISO country code a coordinate falls in, or `nil` if the lookup fails —
    /// offline, mid-ocean, or simply refused. Every caller treats that as "leave
    /// the currency alone".
    static func regionCode(at location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        guard let items = try? await request.mapItems, let first = items.first else { return nil }
        // `regionCode` is NS_REFINED_FOR_SWIFT with no Swift wrapper shipped, so
        // the underscored name is the only way to reach it. If Apple adds the
        // refined property this becomes `addressRepresentations?.regionCode`.
        return first.addressRepresentations?.__regionCode
    }

    /// "Japan", for the prompt. Falls back to the raw code.
    static func regionName(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }
}
