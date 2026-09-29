//
//  TipCategory.swift
//  Xenia
//
//  A reusable tipping profile, e.g. "Sit-Down Restaurant" or "Fast Food".
//  A category carries a base tip percentage, the rating dimensions it asks
//  about, and a set of custom adjustment rules. Saved restaurants point at a
//  category and may override pieces of it.
//

import Foundation
import SwiftData

@Model
final class TipCategory {
    /// Stable identifier used by restaurants to remember per-rule overrides
    /// even if the category is renamed.
    var uuid: UUID = UUID()

    var name: String = ""
    var symbolName: String = CategorySymbol.fallback

    /// Base tip as a percentage of the bill, e.g. 18 means 18%.
    var baseTipPercent: Double = 18

    /// Minutes to wait after arriving at a place in this category before the
    /// "work out your tip" reminder fires — roughly how long a visit here runs
    /// before you pay. `0` turns arrival reminders off for this category.
    var arrivalReminderMinutes: Int = 45

    var sortOrder: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \AdjustmentRule.category)
    var rules: [AdjustmentRule] = []

    @Relationship(deleteRule: .cascade, inverse: \RatingDimension.category)
    var ratingDimensions: [RatingDimension] = []

    @Relationship(deleteRule: .nullify, inverse: \Restaurant.category)
    var restaurants: [Restaurant] = []

    init(
        name: String,
        symbolName: String = CategorySymbol.fallback,
        baseTipPercent: Double = 18,
        sortOrder: Int = 0
    ) {
        self.uuid = UUID()
        self.name = name
        self.symbolName = symbolName
        self.baseTipPercent = baseTipPercent
        self.sortOrder = sortOrder
    }

    var sortedRules: [AdjustmentRule] {
        rules.sorted { $0.sortOrder < $1.sortOrder }
    }

    var sortedRatingDimensions: [RatingDimension] {
        ratingDimensions.sorted { $0.sortOrder < $1.sortOrder }
    }
}
