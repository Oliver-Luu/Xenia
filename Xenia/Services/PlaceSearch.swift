//
//  PlaceSearch.swift
//  Xenia
//
//  Nearby restaurant lookup via MapKit, plus helpers for matching a live
//  location against the user's saved places.
//

import Foundation
import CoreLocation
import MapKit

/// A restaurant found nearby via MapKit, before it's saved to Places.
struct NearbyPlace: Identifiable, Hashable {
    let id: String
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    /// Distance from the user in meters when known.
    var distance: CLLocationDistance?

    static func == (lhs: NearbyPlace, rhs: NearbyPlace) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init?(mapItem: MKMapItem, from userLocation: CLLocation?) {
        guard let name = mapItem.name else { return nil }
        let location = mapItem.location
        let coordinate = location.coordinate
        self.id = "\(coordinate.latitude),\(coordinate.longitude)-\(name)"
        self.name = name
        self.address = mapItem.address?.shortAddress ?? mapItem.address?.fullAddress ?? ""
        self.coordinate = coordinate
        if let userLocation {
            self.distance = location.distance(from: userLocation)
        } else {
            self.distance = nil
        }
    }
}

@Observable
final class PlaceSearchService {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var results: [NearbyPlace] = []
    private(set) var loadState: LoadState = .idle

    private var activeSearch: MKLocalSearch?
    private var generation = 0

    private static let poiFilter = MKPointOfInterestFilter(including: [
        .restaurant, .cafe, .bakery, .brewery, .winery, .nightlife,
    ])

    /// Point-of-interest search around a coordinate.
    func loadNearby(around coordinate: CLLocationCoordinate2D,
                    userLocation: CLLocation?,
                    radius: CLLocationDistance = 500) async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "restaurant"
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )
        request.pointOfInterestFilter = Self.poiFilter
        await run(request, userLocation: userLocation)
    }

    /// Free-text search, biased toward the given coordinate when available.
    func search(_ query: String,
                near coordinate: CLLocationCoordinate2D?,
                userLocation: CLLocation?) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            loadState = .idle
            return
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        if let coordinate {
            request.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 8000,
                longitudinalMeters: 8000
            )
        }
        await run(request, userLocation: userLocation)
    }

    private func run(_ request: MKLocalSearch.Request, userLocation: CLLocation?) async {
        activeSearch?.cancel()
        generation += 1
        let token = generation
        loadState = .loading
        let search = MKLocalSearch(request: request)
        activeSearch = search
        do {
            let response = try await search.start()
            guard token == generation else { return }
            results = response.mapItems
                .compactMap { NearbyPlace(mapItem: $0, from: userLocation) }
                .sorted { ($0.distance ?? .greatestFiniteMagnitude) < ($1.distance ?? .greatestFiniteMagnitude) }
            loadState = .loaded
        } catch {
            // Ignore errors from a search that has since been superseded or cancelled.
            guard token == generation else { return }
            results = []
            loadState = .failed(error.localizedDescription)
        }
    }
}

enum RestaurantMatcher {
    /// Closest saved restaurant to `location` within `threshold` meters, if any.
    static func closest(to location: CLLocation,
                        among restaurants: [Restaurant],
                        threshold: CLLocationDistance = 120) -> (restaurant: Restaurant, distance: CLLocationDistance)? {
        var best: (restaurant: Restaurant, distance: CLLocationDistance)?
        for restaurant in restaurants {
            guard let distance = restaurant.distance(from: location), distance <= threshold else { continue }
            if best == nil || distance < best!.distance {
                best = (restaurant, distance)
            }
        }
        return best
    }
}
