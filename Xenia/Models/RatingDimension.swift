//
//  RatingDimension.swift
//  Xenia
//
//  One thing you score at tip time — "Service", "Food", or anything you add
//  ("Cleanliness", "Speed"). Each dimension owns its scale and how much a point
//  away from neutral moves the tip. A dimension is owned by either a `TipCategory`
//  (asked everywhere in that category) or a single `Restaurant` (asked only there).
//

import Foundation
import SwiftData

@Model
final class RatingDimension {
    var uuid: UUID = UUID()

    var name: String = ""

    /// Top of the scale. The scale runs 1...maxScore.
    var maxScore: Int = RatingDefaults.maxScore
    /// The score that counts as "no opinion" — no effect on the tip.
    var neutralScore: Int = RatingDefaults.neutralScore
    /// Percentage points added per point above neutral (subtracted below).
    var weight: Double = RatingDefaults.weight

    var sortOrder: Int = 0

    /// Owning category, when this is a category-wide rating. Mutually exclusive
    /// with `restaurant`.
    var category: TipCategory?
    /// Owning place, when this is a rating asked only at one restaurant.
    var restaurant: Restaurant?

    init(
        name: String,
        maxScore: Int = RatingDefaults.maxScore,
        neutralScore: Int = RatingDefaults.neutralScore,
        weight: Double = RatingDefaults.weight,
        sortOrder: Int = 0
    ) {
        self.uuid = UUID()
        self.name = name
        self.maxScore = maxScore
        self.neutralScore = neutralScore
        self.weight = weight
        self.sortOrder = sortOrder
    }

    /// e.g. "1–5 · neutral 3 · 2%/pt"
    var summary: String {
        "1–\(maxScore) · neutral \(neutralScore) · \(Format.percent(weight))/pt"
    }
}
