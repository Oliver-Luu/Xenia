//
//  TipEngine.swift
//  Xenia
//
//  Pure, testable tip math. Takes a starting percentage, the rating scores, and
//  the active rule selections, and produces a breakdown plus final amounts.
//

import Foundation

/// How the final numbers get tidied up.
enum RoundingMode: String, CaseIterable, Codable {
    /// Snap the tip to the currency's minor unit (cents), nothing more.
    case none
    /// Round the tip to a whole currency unit.
    case tip
    /// Round the whole bill + tip to a whole currency unit, adjusting the tip.
    case total
}

/// One rule the user has engaged at tip time.
struct RuleSelection: Identifiable, Hashable {
    let ruleID: UUID
    var title: String
    var deltaPercent: Double
    /// Number of steps applied. A toggle is 0 (off) or 1 (on); a stepper is 0...maxSteps.
    var steps: Int

    var id: UUID { ruleID }

    var contribution: Double { deltaPercent * Double(steps) }
}

/// A single labeled term in the tip breakdown.
struct TipComponent: Identifiable {
    let id = UUID()
    let label: String
    let percent: Double
    /// The cash this term contributes to the tip, given the current bill (or the
    /// cash base, when there is no bill to take a percentage of).
    let amount: Double
}

/// One rating the user scored at tip time, carrying its own scale and weight.
struct RatingInput: Identifiable, Hashable {
    let id: UUID
    var name: String
    var score: Int
    var neutral: Int
    var weight: Double

    var contribution: Double { Double(score - neutral) * weight }
}

/// Everything needed to compute a tip, independent of SwiftData.
struct TipRequest {
    var baseTipPercent: Double
    var ratings: [RatingInput]
    var ruleSelections: [RuleSelection]
    var bill: Double
    var partySize: Int
    /// How to round the result.
    var rounding: RoundingMode = .none
    /// When set, the base tip is this flat cash amount instead of `baseTipPercent`.
    /// Ratings and rules still adjust the tip on top of it.
    var baseTipAmount: Double? = nil
    /// Minor-unit digits for the active currency (2 for USD, 0 for JPY, 3 for KWD).
    var currencyFractionDigits: Int = 2
}

struct TipResult {
    var components: [TipComponent]
    var rawPercent: Double
    /// Percentage after clamping to a sane 0...100 range.
    var percent: Double
    var tipAmount: Double
    var total: Double
    var perPersonTotal: Double
    var perPersonTip: Double
    /// What the tip comes to before rounding is applied.
    var suggestedTipAmount: Double
    /// The tip actually applied, expressed as a percentage of the bill.
    var effectivePercent: Double
}

enum TipEngine {

    static let minPercent: Double = 0
    static let maxPercent: Double = 100

    static func evaluate(_ request: TipRequest) -> TipResult {
        let bill = max(request.bill, 0)

        // The starting tip, expressed both as a percentage of the bill and as
        // cash. A cash base is folded back into a percentage of the bill so the
        // ratings and rules keep working in the same unit as everything else;
        // with no bill it has no percentage, so it carries its cash value alone.
        let basePercent: Double
        let baseCash: Double
        if let amount = request.baseTipAmount {
            baseCash = max(amount, 0)
            basePercent = bill > 0 ? baseCash / bill * 100 : 0
        } else {
            basePercent = request.baseTipPercent
            baseCash = bill * basePercent / 100
        }

        // What one percentage point of adjustment is worth in cash: a point of
        // the bill, or — with no bill — a point of the flat cash base.
        let reference = bill > 0 ? bill : baseCash

        var components: [TipComponent] = [
            TipComponent(label: String(localized: "Base"), percent: basePercent, amount: baseCash)
        ]

        for rating in request.ratings where rating.contribution != 0 {
            components.append(TipComponent(
                label: rating.name,
                percent: rating.contribution,
                amount: reference * rating.contribution / 100
            ))
        }

        for selection in request.ruleSelections where selection.steps > 0 && selection.contribution != 0 {
            let label = selection.steps > 1
                ? "\(selection.title) ×\(selection.steps)"
                : selection.title
            components.append(TipComponent(
                label: label,
                percent: selection.contribution,
                amount: reference * selection.contribution / 100
            ))
        }

        let rawPercent = components.reduce(0) { $0 + $1.percent }
        let percent = min(max(rawPercent, minPercent), maxPercent)

        let digits = max(request.currencyFractionDigits, 0)
        let scale = pow(10.0, Double(digits))

        // With a bill, the tip is that percentage of it. With no bill, the flat
        // cash base stands on its own but the ratings and rules still scale it up
        // or down, so the service the user got still moves the final tip. (The
        // "Base" term contributes 0% in that case, so rawPercent is the net
        // adjustment.)
        let suggestedTipAmount = bill > 0
            ? bill * percent / 100
            : max(baseCash * (1 + rawPercent / 100), 0)

        var tipAmount = suggestedTipAmount
        // A rounding mode should never turn a tip the user zeroed out (bad
        // service, penalties cancelling the base) into a few cents owed.
        if tipAmount > 0 {
            switch request.rounding {
            case .none:
                break
            case .tip:
                tipAmount = tipAmount.rounded()
            case .total:
                tipAmount = max(0, (bill + tipAmount).rounded() - bill)
            }
        }
        // Keep tip and total on the currency's minor unit and consistent with
        // each other (rounding modes can leave a floating-point remainder).
        tipAmount = (tipAmount * scale).rounded() / scale
        let total = ((bill + tipAmount) * scale).rounded() / scale
        let party = max(request.partySize, 1)
        let effectivePercent = bill > 0 ? tipAmount / bill * 100 : percent

        return TipResult(
            components: components,
            rawPercent: rawPercent,
            percent: percent,
            tipAmount: tipAmount,
            total: total,
            perPersonTotal: total / Double(party),
            perPersonTip: tipAmount / Double(party),
            suggestedTipAmount: suggestedTipAmount,
            effectivePercent: effectivePercent
        )
    }
}
