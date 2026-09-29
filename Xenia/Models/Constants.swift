//
//  Constants.swift
//  Xenia
//
//  Shared defaults for new rating dimensions and the category icon palette.
//

import Foundation

enum RatingDefaults {
    static let maxScore = 5
    static let neutralScore = 3
    static let weight: Double = 2
    /// Upper bound offered when a rating sets its own scale.
    static let maxScoreLimit = 10
}

enum ArrivalDefaults {
    /// Minutes used when a place forces arrival reminders on but its category
    /// has them switched off.
    static let fallbackMinutes = 20
}

/// A small curated set of SF Symbols offered when picking a category icon.
enum CategorySymbol {
    static let options: [String] = [
        "fork.knife",
        "takeoutbag.and.cup.and.straw.fill",
        "cup.and.saucer.fill",
        "wineglass.fill",
        "birthday.cake.fill",
        "carrot.fill",
        "popcorn.fill",
        "bag.fill",
        "car.fill",
        "scissors",
        "cross.case.fill",
        "hammer.fill",
        "sparkles",
        "star.fill",
    ]

    static let fallback = "fork.knife"
}
