//
//  PlaceGeocoder.swift
//  Xenia
//
//  Best-effort reverse geocoding to fill in a saved place's city. Fire-and-forget
//  from a save site; it does nothing if the lookup fails, the place is gone, or a
//  city is already set (so a hand-typed value is never clobbered).
//

import Foundation
import CoreLocation
import MapKit
import SwiftData

enum PlaceGeocoder {

    /// Reverse-geocodes `coordinate` and, if it resolves to a city, writes it
    /// onto the still-saved `Restaurant` with that `uuid`.
    @MainActor
    static func backfillCity(
        placeID uuid: UUID,
        coordinate: CLLocationCoordinate2D,
        in context: ModelContext
    ) async {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { return }
        guard
            let mapItems = try? await request.mapItems,
            let city = mapItems.first?.addressRepresentations?.cityName?
                .trimmingCharacters(in: .whitespaces),
            !city.isEmpty
        else { return }

        var descriptor = FetchDescriptor<Restaurant>(predicate: #Predicate { $0.uuid == uuid })
        descriptor.fetchLimit = 1
        guard let place = try? context.fetch(descriptor).first, place.city.isEmpty else { return }
        place.city = city
        try? context.save()
    }
}
