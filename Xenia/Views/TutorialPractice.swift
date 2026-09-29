//
//  TutorialPractice.swift
//  Xenia
//
//  The hands-on part of the tutorial: a working tip calculator over a make-believe
//  restaurant. It runs the real `TipEngine` and the real Instrument controls, so
//  the numbers and the look track the app for free — but it holds its state in a
//  plain object and never touches SwiftData, so nothing here is saved.
//
//  Sections unlock as the script walks down the page (`PracticeStage`); what they
//  contain comes from `TutorialScript.scenario`.
//

import SwiftUI

// MARK: - Session

/// Everything the user has poked at in the practice calculator. Lives for the
/// length of one tutorial run so the work carries across pages.
@Observable
final class PracticeSession {

    let scenario: PracticeScenario

    var billText = ""
    var partySize = 1
    var ratingScores: [UUID: Int] = [:]
    var ruleSteps: [UUID: Int] = [:]
    var rounding: RoundingMode = .none

    init(scenario: PracticeScenario = TutorialScript.scenario) {
        self.scenario = scenario
    }

    // MARK: Reads

    var bill: Double { Format.amountValue(billText) }

    func score(for rating: PracticeScenario.Rating) -> Int {
        ratingScores[rating.id] ?? rating.neutral
    }

    func stepCount(for rule: PracticeScenario.Rule) -> Int {
        ruleSteps[rule.id] ?? 0
    }

    var result: TipResult {
        TipEngine.evaluate(
            TipRequest(
                baseTipPercent: scenario.baseTipPercent,
                ratings: scenario.ratings.map {
                    RatingInput(
                        id: $0.id,
                        name: $0.name,
                        score: score(for: $0),
                        neutral: $0.neutral,
                        weight: $0.weight
                    )
                },
                ruleSelections: scenario.rules.map {
                    RuleSelection(
                        ruleID: $0.id,
                        title: $0.title,
                        deltaPercent: $0.delta,
                        steps: stepCount(for: $0)
                    )
                },
                bill: bill,
                partySize: partySize,
                rounding: rounding,
                currencyFractionDigits: Format.minorUnitDigits()
            )
        )
    }

    // MARK: Goal checks

    var hasBill: Bool { bill > 0 }

    var hasScoredRating: Bool {
        scenario.ratings.contains { score(for: $0) != $0.neutral }
    }

    var hasEngagedRule: Bool {
        scenario.rules.contains { stepCount(for: $0) > 0 }
    }

    // MARK: Writes

    /// Same cash-register / literal entry rule the real bill field uses.
    func normalizeBill() {
        let digits = Format.minorUnitDigits()
        let clean = Preferences.shared.autoDecimal
            ? Format.autoDecimal(billText, fractionDigits: digits)
            : Format.sanitizedAmount(billText, fractionDigits: digits)
        if clean != billText { billText = clean }
    }

    /// Drops in the scenario's suggested bill, for anyone who'd rather not type.
    func useSuggestedBill() {
        billText = String(format: "%.\(Format.minorUnitDigits())f", scenario.suggestedBill)
    }
}

// MARK: - View

struct TutorialPracticeView: View {
    @Bindable var session: PracticeSession
    let stage: PracticeStage

    var billFocus: FocusState<Bool>.Binding

    /// Scroll target, so a tapped bill field can be pulled clear of the number pad.
    static let billAnchor = "practice.bill"

    private var scenario: PracticeScenario { session.scenario }

    var body: some View {
        VStack(alignment: .leading, spacing: Grid.x6) {
            placeBlock
            billBlock.id(Self.billAnchor)
            // Ratings are hidden on the adjustments page so it's purely about the
            // one-offs; they come back on the readout, where the full working shows.
            if stage >= .ratings, stage != .rules { ratingsBlock }
            if stage >= .rules { rulesBlock }
            if stage >= .readout { readoutBlock }
        }
        .onChange(of: session.billText) { _, _ in session.normalizeBill() }
    }

    // MARK: Place

    /// Introduced in full on the first practice page, then reduced to a one-line
    /// reminder — later pages need the room for the section they're teaching.
    @ViewBuilder
    private var placeBlock: some View {
        if stage == .bill {
            FieldGroup(label: "Where you are") {
                Panel {
                    HStack(alignment: .top, spacing: Grid.x3) {
                        VStack(alignment: .leading, spacing: Grid.x1) {
                            Text(scenario.placeName)
                                .font(.cardTitle)
                                .foregroundStyle(Palette.ink)
                            CategoryTag(name: scenario.categoryName)
                        }
                        Spacer(minLength: Grid.x2)
                        practiceTag
                    }
                    Text(scenario.note)
                        .font(.noteText)
                        .foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            Panel(padding: Grid.x3) {
                HStack(spacing: Grid.x2) {
                    Text(scenario.placeName)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    CategoryTag(name: scenario.categoryName)
                    Spacer(minLength: Grid.x2)
                    practiceTag
                }
            }
        }
    }

    private var practiceTag: some View {
        Text("PRACTICE")
            .font(.system(.caption2, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Palette.accentText)
    }

    // MARK: Bill

    private var billBlock: some View {
        VStack(alignment: .leading, spacing: Grid.x2) {
            HStack(alignment: .top, spacing: Grid.x4) {
                FieldGroup(label: "Bill") {
                    FieldWell(
                        placeholder: billPlaceholder,
                        text: $session.billText,
                        keyboard: Preferences.shared.autoDecimal ? .numberPad : .decimalPad,
                        alignment: .trailing,
                        prefix: Format.currencySymbol(),
                        focus: billFocus
                    )
                }
                FieldGroup(label: "Split") {
                    PlusMinus(
                        value: session.partySize,
                        range: 1...50,
                        display: session.partySize == 1 ? "1 way" : "\(session.partySize) ways"
                    ) { session.partySize = $0 }
                }
                .frame(width: 150)
            }

            if !session.hasBill {
                Button {
                    billFocus.wrappedValue = false
                    session.useSuggestedBill()
                } label: {
                    Text("Use \(Format.currency(scenario.suggestedBill))")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Palette.accentText)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Zero at the currency's own precision, matching the real bill field.
    private var billPlaceholder: String {
        let digits = Format.minorUnitDigits()
        return digits > 0 ? "0." + String(repeating: "0", count: digits) : "0"
    }

    // MARK: Ratings

    private var ratingsBlock: some View {
        FieldGroup(label: TipCopy.ratingsLabel, note: TipCopy.ratingsNote) {
            Panel {
                ForEach(Array(scenario.ratings.enumerated()), id: \.element.id) { index, rating in
                    if index > 0 { HairRule() }
                    let score = session.score(for: rating)
                    let delta = Double(score - rating.neutral) * rating.weight
                    RatingRow(
                        name: rating.name,
                        score: score,
                        maxScore: rating.maxScore,
                        delta: delta,
                        deltaLabel: Format.signedPercent(delta)
                    ) {
                        session.ratingScores[rating.id] = $0
                    }
                }
            }
        }
    }

    // MARK: Adjustments

    private var rulesBlock: some View {
        FieldGroup(label: TipCopy.adjustmentsLabel) {
            Panel {
                ForEach(Array(scenario.rules.enumerated()), id: \.element.id) { index, rule in
                    if index > 0 { HairRule() }
                    AdjustmentRow(
                        title: rule.title,
                        detail: rule.detail,
                        deltaPercent: rule.delta,
                        isStepper: rule.isStepper,
                        maxSteps: rule.maxSteps,
                        steps: session.stepCount(for: rule),
                        format: { Format.signedPercent($0) }
                    ) {
                        session.ruleSteps[rule.id] = $0
                    }
                }
            }
        }
    }

    // MARK: Readout

    private var readoutBlock: some View {
        let result = session.result
        return Panel(padding: Grid.x5) {
            HStack(alignment: .lastTextBaseline) {
                Text("TIP").sectionLabelStyle()
                Spacer()
                Text(Format.percent(result.effectivePercent))
                    .font(.readout)
                    .foregroundStyle(Palette.ink)
                    .monospacedDigit()
            }

            if result.rawPercent != result.percent {
                Text("Held at \(Format.percent(result.percent)) from \(Format.percent(result.rawPercent))")
                    .font(.noteText)
                    .foregroundStyle(Palette.inkFaint)
            }

            Rectangle().fill(Palette.ruleStrong).frame(height: 2)
                .padding(.vertical, Grid.x1)

            VStack(spacing: Grid.x2) {
                ForEach(result.components) { component in
                    LedgerRow(
                        label: component.label,
                        value: Format.signedPercent(component.percent),
                        negative: component.percent < 0
                    )
                }
            }

            HairRule().padding(.vertical, Grid.x1)

            VStack(spacing: Grid.x2) {
                LedgerRow(label: "Bill", value: Format.currency(session.bill))
                LedgerRow(label: "Tip", value: Format.currency(result.tipAmount))
                LedgerRow(label: "Total", value: Format.currency(result.total), emphasized: true)
                if session.partySize > 1 {
                    HairRule().padding(.vertical, Grid.x1)
                    LedgerRow(label: "Each pays", value: Format.currency(result.perPersonTotal))
                    LedgerRow(label: "Each tips", value: Format.currency(result.perPersonTip))
                }
            }

            HairRule().padding(.vertical, Grid.x1)

            RoundingRows(selection: $session.rounding)
        }
    }
}

// MARK: - Header strip

/// The running tip, pinned in the tutorial header on practice pages — the same
/// trick the real tip screen uses, so the figure stays in sight while the user is
/// scrolled down working the ratings and adjustments.
struct TutorialTipStrip: View {
    var session: PracticeSession

    var body: some View {
        let result = session.result
        HStack(alignment: .firstTextBaseline, spacing: Grid.x3) {
            Text("TIP").sectionLabelStyle()
            Spacer(minLength: Grid.x2)
            Text(Format.percent(result.effectivePercent))
                .font(.readoutMid)
                .monospacedDigit()
                .foregroundStyle(Palette.accentText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(Format.currency(result.tipAmount))
                .font(.figure)
                .monospacedDigit()
                .foregroundStyle(Palette.inkDim)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Practice tip, \(Format.percent(result.effectivePercent)), \(Format.currency(result.tipAmount))")
    }
}
