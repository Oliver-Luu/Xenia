//
//  SeedData.swift
//  Xenia
//
//  Default categories and rules inserted on first launch so the app is usable
//  immediately. The user can edit or delete any of these.
//

import Foundation
import SwiftData

enum SeedData {

    /// Inserts the starter categories the first time the app runs. Does nothing
    /// once the store has any category.
    @MainActor
    static func installIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<TipCategory>())) ?? 0
        guard existing == 0 else { return }

        for (index, template) in templates.enumerated() {
            let category = TipCategory(
                name: template.name,
                symbolName: template.symbol,
                baseTipPercent: template.base,
                sortOrder: index
            )
            category.arrivalReminderMinutes = template.reminderMinutes
            context.insert(category)

            for (ratingIndex, rating) in template.ratings.enumerated() {
                let dimension = RatingDimension(
                    name: rating,
                    weight: template.weight,
                    sortOrder: ratingIndex
                )
                dimension.category = category
                category.ratingDimensions.append(dimension)
                context.insert(dimension)
            }

            // Default order: bigger positive bumps first, penalties last.
            let orderedRules = template.rules.sorted { $0.delta > $1.delta }
            for (ruleIndex, rule) in orderedRules.enumerated() {
                let model = AdjustmentRule(
                    title: rule.title,
                    detail: rule.detail,
                    deltaPercent: rule.delta,
                    isStepper: rule.isStepper,
                    maxSteps: rule.maxSteps,
                    sortOrder: ruleIndex
                )
                model.category = category
                category.rules.append(model)
                context.insert(model)
            }
        }

        try? context.save()
    }

    /// The default arrival-reminder delay for a starter category, or `nil` for a
    /// category the user made up.
    static func defaultReminderMinutes(forCategoryNamed name: String) -> Int? {
        templates.first { $0.name == name }?.reminderMinutes
    }

    private struct RuleTemplate {
        var title: String
        var detail: String = ""
        var delta: Double
        var isStepper: Bool = false
        var maxSteps: Int = 5
    }

    private struct CategoryTemplate {
        var name: String
        var symbol: String
        var base: Double
        var ratings: [String]
        var weight: Double
        /// Minutes after arriving before the tip reminder fires. `0` = no reminder.
        var reminderMinutes: Int = 45
        var rules: [RuleTemplate]
    }

    private static let templates: [CategoryTemplate] = [
        CategoryTemplate(
            name: String(localized: "Sit-Down Restaurant"),
            symbol: "fork.knife",
            base: 18,
            ratings: [String(localized: "Service"), String(localized: "Food"), String(localized: "Atmosphere")],
            weight: 2,
            reminderMinutes: 55,
            rules: [
                RuleTemplate(title: String(localized: "Server went above and beyond"),
                             detail: String(localized: "Menu guidance, comped something, remembered us"),
                             delta: 3),
                RuleTemplate(title: String(localized: "Had to flag someone down"),
                             detail: String(localized: "Slow refills, long waits to order or pay"),
                             delta: -3),
                RuleTemplate(title: String(localized: "Kitchen handled a special request"),
                             detail: String(localized: "Allergy, off-menu change, split plates"),
                             delta: 2),
                RuleTemplate(title: String(localized: "Large party"),
                             detail: String(localized: "Check for auto-gratuity before adding"),
                             delta: -4),
            ]
        ),
        CategoryTemplate(
            name: String(localized: "Fast Food / Counter"),
            symbol: "takeoutbag.and.cup.and.straw.fill",
            base: 0,
            ratings: [String(localized: "Service")],
            weight: 1,
            reminderMinutes: 3,
            rules: [
                RuleTemplate(title: String(localized: "They made a custom order"), delta: 3),
                RuleTemplate(title: String(localized: "Brought food to the table"), delta: 3),
                RuleTemplate(title: String(localized: "Order was wrong"), delta: -3),
            ]
        ),
        CategoryTemplate(
            name: String(localized: "Café / Coffee Shop"),
            symbol: "cup.and.saucer.fill",
            base: 10,
            ratings: [String(localized: "Service")],
            weight: 1.5,
            reminderMinutes: 3,
            rules: [
                RuleTemplate(title: String(localized: "Latte art / real effort"), delta: 5),
                RuleTemplate(title: String(localized: "Just poured drip coffee"), delta: -5),
                RuleTemplate(title: String(localized: "Also ordered food"), delta: 2),
            ]
        ),
        CategoryTemplate(
            name: String(localized: "Bar / Pub"),
            symbol: "wineglass.fill",
            base: 20,
            ratings: [String(localized: "Service")],
            weight: 2,
            reminderMinutes: 45,
            rules: [
                RuleTemplate(title: String(localized: "Craft cocktails"), delta: 5),
                RuleTemplate(title: String(localized: "Beer or wine pour only"), delta: -5),
                RuleTemplate(title: String(localized: "Extra round"), detail: String(localized: "Adds per round kept open"),
                             delta: 1, isStepper: true, maxSteps: 8),
            ]
        ),
        CategoryTemplate(
            name: String(localized: "Takeout / Pickup"),
            symbol: "bag.fill",
            base: 5,
            ratings: [],
            weight: 1,
            reminderMinutes: 2,
            rules: [
                RuleTemplate(title: String(localized: "Large or complicated order"), delta: 3),
                RuleTemplate(title: String(localized: "Curbside brought to the car"), delta: 2),
            ]
        ),
        CategoryTemplate(
            name: String(localized: "Delivery"),
            symbol: "car.fill",
            base: 15,
            ratings: [String(localized: "Service")],
            weight: 1.5,
            reminderMinutes: 0,
            rules: [
                RuleTemplate(title: String(localized: "Bad weather"), delta: 5),
                RuleTemplate(title: String(localized: "Long distance"), delta: 3),
                RuleTemplate(title: String(localized: "Left at door, no contact issues"), delta: 0),
                RuleTemplate(title: String(localized: "Very late / items missing"), delta: -5),
            ]
        ),
    ]
}
