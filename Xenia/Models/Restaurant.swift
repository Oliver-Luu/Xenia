//
//  Restaurant.swift
//  Xenia
//
//  A place the user has saved. It belongs to a `TipCategory` and can override
//  the category's base tip, skip some of its rules, or add its own ratings and
//  rules. GPS matching uses the stored coordinate.
//

import Foundation
import CoreLocation
import SwiftData

@Model
final class Restaurant {
    var uuid: UUID = UUID()

    var name: String = ""
    var streetAddress: String = ""
    /// The town/city this place is in. Filled in by reverse-geocoding the saved
    /// coordinate when the place is saved; the user can also edit it by hand.
    var city: String = ""

    var latitude: Double = 0
    var longitude: Double = 0
    var hasCoordinate: Bool = false

    var category: TipCategory?

    /// User-made organizing bucket. `nil` → grouped by `category` in the list.
    var group: PlaceGroup?

    /// Pinned to the top of the Places list.
    var isFavorite: Bool = false
    /// How many tips have been saved here — drives "Most visited".
    var visitCount: Int = 0

    /// When set, replaces the category's `baseTipPercent` for this place.
    var baseTipOverride: Double?

    /// `uuid`s of the category's rules that should be hidden for this place.
    var disabledRuleIDs: [UUID] = []

    /// Per-place arrival-reminder override. `nil` = follow the category, `true` =
    /// always remind here, `false` = never remind here.
    var arrivalRemindersOn: Bool?

    /// Ratings asked only when tipping here, on top of the category's.
    @Relationship(deleteRule: .cascade, inverse: \RatingDimension.restaurant)
    var customRatingDimensions: [RatingDimension] = []

    /// Adjustment rules offered only when tipping here, on top of the category's.
    @Relationship(deleteRule: .cascade, inverse: \AdjustmentRule.restaurant)
    var customRules: [AdjustmentRule] = []

    var note: String = ""

    init(
        name: String,
        streetAddress: String = "",
        city: String = "",
        coordinate: CLLocationCoordinate2D? = nil,
        category: TipCategory? = nil,
        baseTipOverride: Double? = nil,
        note: String = ""
    ) {
        self.uuid = UUID()
        self.name = name
        self.streetAddress = streetAddress
        self.city = city
        self.category = category
        self.baseTipOverride = baseTipOverride
        self.note = note
        if let coordinate {
            self.latitude = coordinate.latitude
            self.longitude = coordinate.longitude
            self.hasCoordinate = true
        }
    }

    var coordinate: CLLocationCoordinate2D? {
        get {
            guard hasCoordinate else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        set {
            if let newValue {
                latitude = newValue.latitude
                longitude = newValue.longitude
                hasCoordinate = true
            } else {
                hasCoordinate = false
            }
        }
    }

    /// The tip percentage this place starts from before ratings and rules.
    var effectiveBaseTipPercent: Double {
        baseTipOverride ?? category?.baseTipPercent ?? 18
    }

    /// Minutes to wait before an arrival reminder here, `0` when reminders are
    /// off for this place. Resolves the per-place override against the category.
    var effectiveArrivalReminderMinutes: Int {
        let categoryMinutes = category?.arrivalReminderMinutes ?? 0
        guard let on = arrivalRemindersOn else { return categoryMinutes }
        guard on else { return 0 }
        return categoryMinutes > 0 ? categoryMinutes : ArrivalDefaults.fallbackMinutes
    }

    var sortedCustomRatingDimensions: [RatingDimension] {
        customRatingDimensions.sorted { $0.sortOrder < $1.sortOrder }
    }

    var sortedCustomRules: [AdjustmentRule] {
        customRules.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Every rating asked when tipping here: the category's, then this place's own.
    var allRatingDimensions: [RatingDimension] {
        (category?.sortedRatingDimensions ?? []) + sortedCustomRatingDimensions
    }

    /// Rules offered when tipping here: the category's (minus the ones skipped
    /// for this place), then this place's own.
    var activeRules: [AdjustmentRule] {
        (category?.sortedRules ?? []).filter { !disabledRuleIDs.contains($0.uuid) }
            + sortedCustomRules
    }

    func distance(from location: CLLocation) -> CLLocationDistance? {
        guard let coordinate else { return nil }
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return here.distance(from: location)
    }
}
