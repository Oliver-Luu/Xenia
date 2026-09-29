//
//  TipRecord.swift
//  Xenia
//
//  A saved calculation kept in history. Values are denormalized (names copied,
//  not linked) so deleting a place or category never corrupts past records.
//

import Foundation
import SwiftData

/// A rating as it stood when the tip was saved.
struct RatingSnapshot: Codable, Hashable {
    var name: String
    var score: Int
    var outOf: Int
}

@Model
final class TipRecord {
    var date: Date = Date.now

    var placeName: String = ""
    var categoryName: String = ""

    var billAmount: Double = 0
    var tipPercent: Double = 0
    var tipAmount: Double = 0
    var total: Double = 0
    var partySize: Int = 1

    /// Ratings given, in the order the category asked them. Empty if none asked.
    var ratingScores: [RatingSnapshot] = []

    /// The money this tip was actually paid in, stamped at save time. Without it
    /// history would re-label every past tip in whatever currency happens to be
    /// in effect now — so a ¥3,000 tip in Tokyo would read as $3,000 on the flight
    /// home. Empty on rows saved before the field existed; read `currency`.
    var currencyCode: String = ""

    init(
        date: Date = .now,
        placeName: String,
        categoryName: String,
        billAmount: Double,
        tipPercent: Double,
        tipAmount: Double,
        total: Double,
        partySize: Int = 1,
        ratings: [RatingSnapshot] = [],
        currencyCode: String = Preferences.shared.resolvedCurrencyCode
    ) {
        self.date = date
        self.placeName = placeName
        self.categoryName = categoryName
        self.billAmount = billAmount
        self.tipPercent = tipPercent
        self.tipAmount = tipAmount
        self.total = total
        self.partySize = partySize
        self.ratingScores = ratings
        self.currencyCode = currencyCode
    }

    /// The currency to render this record in. Rows saved before the stamp existed
    /// fall back to the *home* currency rather than whatever is in effect now, so
    /// at least they stop moving around as the user travels.
    var currency: String {
        currencyCode.isEmpty
            ? (Locale.current.currency?.identifier ?? "USD")
            : currencyCode
    }

    var perPersonTotal: Double {
        partySize > 0 ? total / Double(partySize) : total
    }

    /// Tips totalled per currency, most recently used first. History spanning a
    /// trip holds more than one kind of money, and adding yen to dollars would
    /// produce a number that means nothing.
    static func totalsByCurrency(_ records: [TipRecord]) -> [(currency: String, total: Double)] {
        var totals: [String: Double] = [:]
        var lastUsed: [String: Date] = [:]
        for record in records {
            let code = record.currency
            totals[code, default: 0] += record.tipAmount
            lastUsed[code] = max(lastUsed[code] ?? .distantPast, record.date)
        }
        return totals
            .map { (currency: $0.key, total: $0.value) }
            .sorted {
                (lastUsed[$0.currency] ?? .distantPast) > (lastUsed[$1.currency] ?? .distantPast)
            }
    }
}
