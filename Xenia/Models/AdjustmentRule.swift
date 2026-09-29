//
//  AdjustmentRule.swift
//  Xenia
//
//  A single named modifier the user can apply at tip time, e.g.
//  "Exceptional server +3%" (a toggle) or "Extra drink rounds +1% each" (a stepper).
//  Owned by either a `TipCategory` (offered everywhere in that category) or a
//  single `Restaurant` (offered only at that place).
//

import Foundation
import SwiftData

@Model
final class AdjustmentRule {
    /// Stable identifier so a restaurant can disable a specific rule.
    var uuid: UUID = UUID()

    var title: String = ""
    var detail: String = ""

    /// Percentage points added when the rule is active (one step). May be negative.
    var deltaPercent: Double = 1

    /// When true the rule is a 0...`maxSteps` stepper; the delta is multiplied by
    /// the chosen step count. When false it is a simple on/off toggle.
    var isStepper: Bool = false
    var maxSteps: Int = 5

    var sortOrder: Int = 0

    /// Owning category, when this is a category-wide rule. Mutually exclusive
    /// with `restaurant`.
    var category: TipCategory?
    /// Owning place, when this is a rule offered only at one restaurant.
    var restaurant: Restaurant?

    init(
        title: String,
        detail: String = "",
        deltaPercent: Double = 1,
        isStepper: Bool = false,
        maxSteps: Int = 5,
        sortOrder: Int = 0
    ) {
        self.uuid = UUID()
        self.title = title
        self.detail = detail
        self.deltaPercent = deltaPercent
        self.isStepper = isStepper
        self.maxSteps = maxSteps
        self.sortOrder = sortOrder
    }
}
